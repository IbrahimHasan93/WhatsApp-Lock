import AppKit

protocol AppMonitorDelegate: AnyObject {
    func appMonitorDidDetectTargetLaunch(_ app: NSRunningApplication)
    func appMonitorDidDetectTargetDeactivation()
    func appMonitorDidDetectTargetTermination()
}

/// Watches for WhatsApp launching/activating/terminating using NSWorkspace
/// notifications, and reports back to its delegate.
final class AppMonitor {
    private weak var delegate: AppMonitorDelegate?
    private(set) var targetBundleIdentifiers: Set<String> = []
    private let workspace = NSWorkspace.shared

    init(delegate: AppMonitorDelegate) {
        self.delegate = delegate
        self.targetBundleIdentifiers = Self.discoverWhatsAppBundleIDs()
    }

    /// Looks at the actual installed WhatsApp.app (if present) to read its real
    /// bundle identifier, and also keeps a couple of known fallbacks in case
    /// WhatsApp isn't installed yet when this app first launches.
    static func discoverWhatsAppBundleIDs() -> Set<String> {
        var ids: Set<String> = []
        let candidatePaths = [
            "/Applications/WhatsApp.app",
            NSHomeDirectory() + "/Applications/WhatsApp.app"
        ]
        for path in candidatePaths {
            if FileManager.default.fileExists(atPath: path),
               let bundle = Bundle(path: path),
               let id = bundle.bundleIdentifier {
                ids.insert(id)
            }
        }
        // Known WhatsApp for Mac bundle identifiers, as a fallback if discovery
        // above finds nothing (e.g. WhatsApp not installed yet at first launch).
        ids.formUnion(["net.whatsapp.WhatsApp", "desktop.WhatsApp"])
        return ids
    }

    func start() {
        let nc = workspace.notificationCenter
        nc.addObserver(self, selector: #selector(appLaunched(_:)), name: NSWorkspace.didLaunchApplicationNotification, object: nil)
        nc.addObserver(self, selector: #selector(appActivated(_:)), name: NSWorkspace.didActivateApplicationNotification, object: nil)
        nc.addObserver(self, selector: #selector(appDeactivated(_:)), name: NSWorkspace.didDeactivateApplicationNotification, object: nil)
        nc.addObserver(self, selector: #selector(appTerminated(_:)), name: NSWorkspace.didTerminateApplicationNotification, object: nil)

        // Catch the case where WhatsApp is already running when we start up.
        for running in workspace.runningApplications where isTarget(running) {
            delegate?.appMonitorDidDetectTargetLaunch(running)
        }
    }

    func stop() {
        workspace.notificationCenter.removeObserver(self)
    }

    private func isTarget(_ app: NSRunningApplication) -> Bool {
        guard let bundleID = app.bundleIdentifier else { return false }
        return targetBundleIdentifiers.contains(bundleID)
    }

    @objc private func appLaunched(_ note: Notification) {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication, isTarget(app) else { return }
        delegate?.appMonitorDidDetectTargetLaunch(app)
    }

    @objc private func appActivated(_ note: Notification) {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication, isTarget(app) else { return }
        delegate?.appMonitorDidDetectTargetLaunch(app)
    }

    @objc private func appDeactivated(_ note: Notification) {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication, isTarget(app) else { return }
        delegate?.appMonitorDidDetectTargetDeactivation()
    }

    @objc private func appTerminated(_ note: Notification) {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication, isTarget(app) else { return }
        delegate?.appMonitorDidDetectTargetTermination()
    }
}
