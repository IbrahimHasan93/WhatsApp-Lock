import Foundation

/// Installs/removes a per-user LaunchAgent so WhatsApp Lock starts at login
/// and restarts itself if it's ever killed. This is a user-level LaunchAgent
/// (not a root LaunchDaemon), so a technically determined user could still
/// remove it via Terminal (`launchctl unload` + delete the plist) — see the
/// README for the tradeoffs of this "simple" tamper-resistance level.
final class LaunchAgentManager {
    static let shared = LaunchAgentManager()

    private let label = "com.ibrahim.whatsapplock"

    private var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }

    var isInstalled: Bool {
        FileManager.default.fileExists(atPath: plistURL.path)
    }

    /// Installs the LaunchAgent pointing at the CURRENTLY RUNNING executable.
    /// Important: run this from the final built app in /Applications, not
    /// from a `swift run` development build, so the path stays valid.
    @discardableResult
    func install() -> Bool {
        guard let execPath = Bundle.main.executablePath else { return false }

        let logsDir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs")
        try? FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)

        let plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": [execPath],
            "RunAtLoad": true,
            "KeepAlive": true,
            "ProcessType": "Interactive",
            "StandardOutPath": logsDir.appendingPathComponent("WhatsAppLock.log").path,
            "StandardErrorPath": logsDir.appendingPathComponent("WhatsAppLock.err.log").path
        ]

        guard let data = try? PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0) else {
            return false
        }

        do {
            try FileManager.default.createDirectory(at: plistURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: plistURL)
        } catch {
            return false
        }

        runLaunchctl(["load", "-w", plistURL.path])
        return true
    }

    func uninstall() {
        runLaunchctl(["unload", "-w", plistURL.path])
        try? FileManager.default.removeItem(at: plistURL)
    }

    private func runLaunchctl(_ args: [String]) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        task.arguments = args
        try? task.run()
        task.waitUntilExit()
    }
}
