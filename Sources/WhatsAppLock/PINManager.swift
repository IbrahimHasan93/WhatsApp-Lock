import Foundation
import CryptoKit
import Security

/// Stores a salted SHA-256 hash of the PIN (never the PIN itself) in
/// ~/Library/Application Support/WhatsAppLock/config.json, with basic
/// brute-force throttling.
struct PINStore: Codable {
    var saltBase64: String
    var hashHex: String
    var failedAttempts: Int = 0
    var lockedUntil: Date? = nil
}

final class PINManager {
    private let fileURL: URL
    private var store: PINStore?

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = appSupport.appendingPathComponent("WhatsAppLock", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        self.fileURL = dir.appendingPathComponent("config.json")
        load()
    }

    var isPINSet: Bool { store != nil }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        store = try? JSONDecoder().decode(PINStore.self, from: data)
    }

    private func save() {
        guard let store, let data = try? JSONEncoder().encode(store) else { return }
        try? data.write(to: fileURL, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }

    /// Sets (or overwrites) the PIN.
    func setPIN(_ pin: String) {
        var salt = [UInt8](repeating: 0, count: 16)
        _ = SecRandomCopyBytes(kSecRandomDefault, salt.count, &salt)
        let saltData = Data(salt)
        let hash = Self.hash(pin: pin, salt: saltData)
        store = PINStore(saltBase64: saltData.base64EncodedString(), hashHex: hash)
        save()
    }

    /// Verifies a candidate PIN. Applies a short lockout after 5 wrong attempts in a row.
    @discardableResult
    func verify(_ pin: String) -> Bool {
        guard var currentStore = store else { return false }

        if let lockedUntil = currentStore.lockedUntil, lockedUntil > Date() {
            return false
        }

        guard let saltData = Data(base64Encoded: currentStore.saltBase64) else { return false }
        let candidate = Self.hash(pin: pin, salt: saltData)

        if candidate == currentStore.hashHex {
            currentStore.failedAttempts = 0
            currentStore.lockedUntil = nil
            store = currentStore
            save()
            return true
        } else {
            currentStore.failedAttempts += 1
            if currentStore.failedAttempts >= 5 {
                currentStore.lockedUntil = Date().addingTimeInterval(30)
                currentStore.failedAttempts = 0
            }
            store = currentStore
            save()
            return false
        }
    }

    var isLockedOut: Bool {
        guard let lockedUntil = store?.lockedUntil else { return false }
        return lockedUntil > Date()
    }

    var lockoutRemainingSeconds: Int {
        guard let lockedUntil = store?.lockedUntil else { return 0 }
        return max(0, Int(lockedUntil.timeIntervalSinceNow.rounded(.up)))
    }

    private static func hash(pin: String, salt: Data) -> String {
        var data = salt
        data.append(contentsOf: Array(pin.utf8))
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
