import AppKit
import SwiftUI

/// A small floating, undecorated window that asks the user to enter their
/// existing PIN. Reused both for "unlock WhatsApp" and for confirming
/// sensitive actions inside WhatsApp Lock itself (quitting the app, turning
/// off auto-start, changing the PIN).
final class PINPromptWindowController: NSWindowController {
    private var didResolve = false
    private let completion: (Bool) -> Void
    let coversScreen: Bool

    /// Safety net: the full-screen cover gives up (same as Cancel) after this
    /// long, so it can never trap the screen indefinitely.
    private static let coverTimeout: TimeInterval = 60

    /// When true, the prompt fills the entire screen with an opaque
    /// background instead of floating as a small panel. Used for the
    /// "WhatsApp is locked" prompt so WhatsApp's own window can never show
    /// through around the edges, regardless of whether hiding WhatsApp's
    /// window has visibly taken effect yet.
    init(pinManager: PINManager, title: String, subtitle: String, showCancel: Bool = true, coversScreen: Bool = false, biometricReason: String, completion: @escaping (Bool) -> Void) {
        self.completion = completion
        self.coversScreen = coversScreen

        let cardHeight: CGFloat = BiometricAuthenticator.isAvailable ? 260 : 220
        let screenFrame = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 340, height: cardHeight)
        let windowFrame = coversScreen ? screenFrame : NSRect(x: 0, y: 0, width: 340, height: cardHeight)

        let windowClass: NSWindow.Type = coversScreen ? KeyableBorderlessWindow.self : NSWindow.self
        let window = windowClass.init(
            contentRect: windowFrame,
            styleMask: coversScreen ? [.borderless] : [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        if coversScreen {
            window.isOpaque = true
            window.backgroundColor = .black
            window.level = .screenSaver
            window.hasShadow = false
        } else {
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.level = .floating
            window.center()
        }

        super.init(window: window)

        let rootView = PINPromptView(
            pinManager: pinManager,
            title: title,
            subtitle: subtitle,
            showCancel: showCancel,
            coversScreen: coversScreen,
            biometricReason: biometricReason,
            onResult: { [weak self] success in
                self?.resolve(success)
            }
        )
        window.contentView = NSHostingView(rootView: rootView)

        if coversScreen {
            // Strong capture on purpose: closes the window even if nothing
            // else holds this controller anymore.
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.coverTimeout) {
                self.resolve(false)
            }
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func present() {
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    /// Closes the prompt without reporting a result (e.g. WhatsApp quit
    /// while it was showing, so there's nothing left to unlock).
    func dismiss() {
        didResolve = true
        close()
    }

    private func resolve(_ success: Bool) {
        guard !didResolve else { return }
        didResolve = true
        completion(success)
        close()
    }
}

private struct PINPromptView: View {
    @ObservedObject private var model: PINPromptViewModel
    let title: String
    let subtitle: String
    let showCancel: Bool
    let coversScreen: Bool

    init(pinManager: PINManager, title: String, subtitle: String, showCancel: Bool, coversScreen: Bool, biometricReason: String, onResult: @escaping (Bool) -> Void) {
        self.title = title
        self.subtitle = subtitle
        self.showCancel = showCancel
        self.coversScreen = coversScreen
        _model = ObservedObject(wrappedValue: PINPromptViewModel(pinManager: pinManager, biometricReason: biometricReason, onResult: onResult))
    }

    var body: some View {
        ZStack {
            if coversScreen {
                Color.black.ignoresSafeArea()
            }

            card
                .padding(24)
                .frame(width: 340, height: model.biometricsAvailable ? 260 : 220)
                .background(coversScreen ? AnyView(cardBackground) : AnyView(EmptyView()))
        }
        .frame(maxWidth: coversScreen ? .infinity : 340, maxHeight: coversScreen ? .infinity : (model.biometricsAvailable ? 260 : 220))
        .onAppear { model.attemptBiometrics() }
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(.regularMaterial)
    }

    private var card: some View {
        VStack(spacing: 14) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 36))
                .foregroundStyle(.blue)

            Text(title)
                .font(.headline)

            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            SecureField("PIN", text: $model.pin)
                .textFieldStyle(.roundedBorder)
                .frame(width: 180)
                .onSubmit { model.submit() }

            if let error = model.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack(spacing: 12) {
                if showCancel {
                    Button("Cancel") { model.cancel() }
                        .keyboardShortcut(.cancelAction)
                }
                Button("Unlock") { model.submit() }
                    .keyboardShortcut(.defaultAction)
            }

            if model.biometricsAvailable {
                Button {
                    model.attemptBiometrics()
                } label: {
                    Label(
                        model.isAuthenticatingWithBiometrics ? "Waiting for Touch ID…" : "Use Touch ID instead",
                        systemImage: "touchid"
                    )
                    .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.blue)
                .disabled(model.isAuthenticatingWithBiometrics)
            }
        }
    }
}

private final class PINPromptViewModel: ObservableObject {
    @Published var pin: String = ""
    @Published var errorMessage: String?
    @Published var isAuthenticatingWithBiometrics = false

    let biometricsAvailable = BiometricAuthenticator.isAvailable

    private let pinManager: PINManager
    private let biometricReason: String
    private let onResult: (Bool) -> Void

    init(pinManager: PINManager, biometricReason: String, onResult: @escaping (Bool) -> Void) {
        self.pinManager = pinManager
        self.biometricReason = biometricReason
        self.onResult = onResult
    }

    /// Tries Touch ID; on failure or cancellation this just leaves the PIN
    /// field as the fallback rather than surfacing an error, since Touch ID
    /// has its own attempt limiting independent of the PIN's lockout.
    func attemptBiometrics() {
        guard biometricsAvailable, !isAuthenticatingWithBiometrics else { return }
        isAuthenticatingWithBiometrics = true
        BiometricAuthenticator.authenticate(reason: biometricReason) { [weak self] success in
            guard let self else { return }
            self.isAuthenticatingWithBiometrics = false
            if success {
                self.onResult(true)
            }
        }
    }

    func submit() {
        if pinManager.isLockedOut {
            errorMessage = "Too many attempts. Try again in \(pinManager.lockoutRemainingSeconds)s."
            return
        }
        guard !pin.isEmpty else { return }
        if pinManager.verify(pin) {
            onResult(true)
        } else {
            errorMessage = pinManager.isLockedOut
                ? "Too many attempts. Try again in \(pinManager.lockoutRemainingSeconds)s."
                : "Incorrect PIN"
            pin = ""
        }
    }

    func cancel() {
        onResult(false)
    }
}

/// A plain NSWindow with a borderless style mask reports `canBecomeKey ==
/// false` by default, so it can never accept keyboard focus for the PIN
/// field. This override is what lets the full-screen covering prompt
/// actually receive typing.
private final class KeyableBorderlessWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
