import AppKit
import SwiftUI

/// Window shown on first run (and when changing the PIN) to let the user
/// choose a new PIN, with confirmation.
final class PINSetupWindowController: NSWindowController {
    private var didResolve = false
    private let completion: () -> Void

    init(pinManager: PINManager, completion: @escaping () -> Void) {
        self.completion = completion

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 260),
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.center()

        super.init(window: window)

        let rootView = PINSetupView(pinManager: pinManager, onDone: { [weak self] in
            self?.resolve()
        })
        window.contentView = NSHostingView(rootView: rootView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func present() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func resolve() {
        guard !didResolve else { return }
        didResolve = true
        completion()
        close()
    }
}

private struct PINSetupView: View {
    @ObservedObject private var model: PINSetupViewModel

    init(pinManager: PINManager, onDone: @escaping () -> Void) {
        _model = ObservedObject(wrappedValue: PINSetupViewModel(pinManager: pinManager, onDone: onDone))
    }

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "lock.shield")
                .font(.system(size: 36))
                .foregroundStyle(.blue)

            Text("Set a PIN for WhatsApp Lock")
                .font(.headline)

            Text("You'll need this PIN every time you want to open WhatsApp.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(width: 260)

            SecureField("New PIN (4+ digits)", text: $model.pin)
                .textFieldStyle(.roundedBorder)
                .frame(width: 200)

            SecureField("Confirm PIN", text: $model.confirmPin)
                .textFieldStyle(.roundedBorder)
                .frame(width: 200)
                .onSubmit { model.submit() }

            if let error = model.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Button("Save PIN") { model.submit() }
                .keyboardShortcut(.defaultAction)
        }
        .padding(24)
        .frame(width: 360, height: 260)
    }
}

private final class PINSetupViewModel: ObservableObject {
    @Published var pin: String = ""
    @Published var confirmPin: String = ""
    @Published var errorMessage: String?

    private let pinManager: PINManager
    private let onDone: () -> Void

    init(pinManager: PINManager, onDone: @escaping () -> Void) {
        self.pinManager = pinManager
        self.onDone = onDone
    }

    func submit() {
        guard pin.count >= 4 else {
            errorMessage = "PIN must be at least 4 digits."
            return
        }
        guard pin == confirmPin else {
            errorMessage = "PINs don't match."
            confirmPin = ""
            return
        }
        pinManager.setPIN(pin)
        onDone()
    }
}
