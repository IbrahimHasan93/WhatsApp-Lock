import LocalAuthentication

/// Thin wrapper around LocalAuthentication so Touch ID can be offered
/// alongside the PIN anywhere a PIN is required. Touch ID's own attempt
/// limiting lives in the Secure Enclave, independent of PINManager's
/// PIN lockout, so a failed or cancelled Touch ID attempt never affects
/// the PIN lockout counter — it just leaves the PIN field as the fallback.
enum BiometricAuthenticator {
    static var isAvailable: Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
    }

    static func authenticate(reason: String, completion: @escaping (Bool) -> Void) {
        let context = LAContext()
        context.localizedCancelTitle = "Use PIN instead"

        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil) else {
            completion(false)
            return
        }

        context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) { success, _ in
            DispatchQueue.main.async {
                completion(success)
            }
        }
    }
}
