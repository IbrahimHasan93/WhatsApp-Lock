import AppKit
import Darwin

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var startAtLoginMenuItem: NSMenuItem!

    private let pinManager = PINManager()
    private var appMonitor: AppMonitor?

    // Keep strong references so these windows aren't deallocated while shown.
    private var pinSetupWindowController: PINSetupWindowController?
    private var pinPromptWindowController: PINPromptWindowController?

    // Keep the signal sources alive for the app's lifetime; see
    // installTerminationSignalHandlers().
    private var terminationSignalSources: [DispatchSourceSignal] = []

    // WhatsApp stays hidden/locked until this becomes true; reset to false
    // whenever WhatsApp loses focus (switching to another app) or fully
    // quits, so switching back to WhatsApp — via Cmd+Tab, the Dock, or a
    // fresh launch — always requires the PIN/Touch ID again.
    private var isWhatsAppCurrentlyUnlocked = false

    // Set when macOS announces logout/restart/shutdown, so the PIN gate in
    // applicationShouldTerminate(_:) doesn't block the system from quitting us.
    private var isSystemPoweringOff = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        installTerminationSignalHandlers()
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willPowerOffNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.isSystemPoweringOff = true }

        if pinManager.isPINSet {
            startMonitoring()
        } else {
            presentInitialPINSetup()
        }
    }

    // MARK: - Status bar menu

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "lock.fill", accessibilityDescription: "WhatsApp Lock")
        }

        let menu = NSMenu()

        let titleItem = NSMenuItem(title: "WhatsApp Lock", action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        menu.addItem(titleItem)
        menu.addItem(.separator())

        menu.addItem(withTitle: "Change PIN…", action: #selector(changePINRequested), keyEquivalent: "")

        startAtLoginMenuItem = NSMenuItem(title: "Start at Login", action: #selector(toggleStartAtLogin), keyEquivalent: "")
        startAtLoginMenuItem.state = LaunchAgentManager.shared.isInstalled ? .on : .off
        menu.addItem(startAtLoginMenuItem)

        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit WhatsApp Lock", action: #selector(quitRequested), keyEquivalent: "q")

        for item in menu.items {
            item.target = self
        }
        statusItem.menu = menu
    }

    // MARK: - First-run PIN setup

    private func presentInitialPINSetup() {
        let controller = PINSetupWindowController(pinManager: pinManager) { [weak self] in
            self?.pinSetupWindowController = nil
            self?.startMonitoring()
        }
        pinSetupWindowController = controller
        controller.present()
    }

    // MARK: - Monitoring

    private func startMonitoring() {
        guard appMonitor == nil else { return }
        let monitor = AppMonitor(delegate: self)
        appMonitor = monitor
        monitor.start()
    }

    // MARK: - Menu actions

    @objc private func changePINRequested() {
        requireCurrentPIN(
            title: "Confirm current PIN",
            subtitle: "Enter your current PIN to set a new one.",
            biometricReason: "Confirm it's you to change your PIN"
        ) { [weak self] confirmed in
            guard let self, confirmed else { return }
            let controller = PINSetupWindowController(pinManager: self.pinManager) { [weak self] in
                self?.pinSetupWindowController = nil
            }
            self.pinSetupWindowController = controller
            controller.present()
        }
    }

    @objc private func toggleStartAtLogin() {
        if LaunchAgentManager.shared.isInstalled {
            // Turning OFF auto-start weakens the lock, so require the PIN.
            requireCurrentPIN(
                title: "Confirm PIN",
                subtitle: "Enter your PIN to turn off Start at Login.",
                biometricReason: "Confirm it's you to turn off Start at Login"
            ) { [weak self] confirmed in
                guard let self, confirmed else { return }
                LaunchAgentManager.shared.uninstall()
                self.startAtLoginMenuItem.state = .off
            }
        } else {
            LaunchAgentManager.shared.install()
            startAtLoginMenuItem.state = LaunchAgentManager.shared.isInstalled ? .on : .off
        }
    }

    @objc private func quitRequested() {
        // The actual PIN/Touch ID gate lives in applicationShouldTerminate(_:)
        // so it applies no matter how termination was requested.
        NSApp.terminate(nil)
    }

    // MARK: - Quit gating

    /// A plain `kill <pid>` sends SIGTERM, which by default terminates the
    /// process immediately with no chance to react. Ignoring the signal's
    /// default action and routing it through the same
    /// applicationShouldTerminate(_:) gate as every other quit path means a
    /// plain `kill` also requires the PIN/Touch ID.
    ///
    /// `kill -9` (SIGKILL) and Activity Monitor's "Force Quit" cannot be
    /// caught this way or any other way — that's a hard guarantee of the
    /// signal itself on every Unix process, not a gap specific to this app.
    private func installTerminationSignalHandlers() {
        for sig in [SIGTERM, SIGINT] {
            signal(sig, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            source.setEventHandler {
                NSApp.terminate(nil)
            }
            source.resume()
            terminationSignalSources.append(source)
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if isSystemPoweringOff { return .terminateNow }
        guard pinManager.isPINSet else { return .terminateNow }
        // Don't stack a second PIN prompt on top of one already showing
        // (e.g. WhatsApp's own unlock prompt) — just refuse this attempt.
        guard pinPromptWindowController == nil else { return .terminateCancel }

        requireCurrentPIN(
            title: "Confirm PIN",
            subtitle: "Enter your PIN to quit WhatsApp Lock.",
            biometricReason: "Confirm it's you to quit WhatsApp Lock"
        ) { confirmed in
            NSApp.reply(toApplicationShouldTerminate: confirmed)
        }
        return .terminateLater
    }

    private func requireCurrentPIN(title: String, subtitle: String, biometricReason: String, completion: @escaping (Bool) -> Void) {
        let controller = PINPromptWindowController(
            pinManager: pinManager,
            title: title,
            subtitle: subtitle,
            showCancel: true,
            biometricReason: biometricReason
        ) { [weak self] success in
            self?.pinPromptWindowController = nil
            completion(success)
        }
        pinPromptWindowController = controller
        controller.present()
    }
}

// MARK: - AppMonitorDelegate

extension AppDelegate: AppMonitorDelegate {
    func appMonitorDidDetectTargetLaunch(_ runningApp: NSRunningApplication) {
        guard !isWhatsAppCurrentlyUnlocked else { return }

        runningApp.hide()

        if let controller = pinPromptWindowController {
            controller.present()
            return
        }

        let controller = PINPromptWindowController(
            pinManager: pinManager,
            title: "WhatsApp is locked",
            subtitle: "Enter your PIN to open WhatsApp.",
            showCancel: true,
            coversScreen: true,
            biometricReason: "Unlock WhatsApp"
        ) { [weak self] success in
            guard let self else { return }
            self.pinPromptWindowController = nil
            if success {
                self.isWhatsAppCurrentlyUnlocked = true
                self.revealWhatsApp(runningApp)
            } else {
                runningApp.terminate()
            }
        }
        pinPromptWindowController = controller
        controller.present()
    }

    func appMonitorDidDetectTargetDeactivation() {
        isWhatsAppCurrentlyUnlocked = false
    }

    func appMonitorDidDetectTargetTermination() {
        isWhatsAppCurrentlyUnlocked = false
        // Only the full-screen WhatsApp unlock prompt belongs to WhatsApp;
        // close it for real (dropping the reference alone left an orphaned,
        // unresponsive window covering the screen). Leave quit/change-PIN
        // prompts alone.
        if let controller = pinPromptWindowController, controller.coversScreen {
            controller.dismiss()
            pinPromptWindowController = nil
        }
    }

    /// Brings WhatsApp to the front after a correct PIN. A single activate()
    /// call right as our own full-screen prompt is closing is sometimes
    /// dropped by macOS, so we ask again shortly after as a fallback.
    private func revealWhatsApp(_ runningApp: NSRunningApplication) {
        runningApp.unhide()
        runningApp.activate(options: [.activateIgnoringOtherApps])
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            runningApp.activate(options: [.activateIgnoringOtherApps])
        }
    }
}
