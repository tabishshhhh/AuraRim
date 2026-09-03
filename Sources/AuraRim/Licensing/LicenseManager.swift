import Foundation

/// License lifecycle (spec §28). A one-time license model with a provider
/// behind `LicenseProviderProtocol` so the backend (Lemon Squeezy / Polar /
/// custom) is never hardcoded through the app.
enum LicenseState: Sendable, Equatable {
    case unactivated
    case activating
    case active(key: String)
    case invalid(reason: String)
    case activationLimitReached
    case networkUnavailable

    var isActive: Bool { if case .active = self { return true }; return false }
}

/// Result of an activation attempt.
struct ActivationResult: Sendable {
    var success: Bool
    var message: String
}

/// Abstraction over a licensing backend. Swap the implementation without
/// touching feature code.
protocol LicenseProviderProtocol: Sendable {
    func activate(key: String) async -> ActivationResult
    func validate(key: String) async -> ActivationResult
    func deactivate(key: String) async -> ActivationResult
}

/// Offline-friendly manager. Stores the key in the Keychain and trusts a prior
/// successful activation when the network is unavailable (spec §28: "gracefully
/// handle being offline after successful activation").
@MainActor
final class LicenseManager {
    private let provider: LicenseProviderProtocol
    private let keychain = KeychainManager(service: AppBrand.bundleIdentifier)
    private let keyAccount = "license-key"

    private(set) var state: LicenseState = .unactivated
    var onChange: ((LicenseState) -> Void)?

    init(provider: LicenseProviderProtocol = StubLicenseProvider()) {
        self.provider = provider
    }

    /// Restore a stored key at launch; treat a previously stored key as active
    /// without requiring a network round-trip.
    func restore() {
        if let key = keychain.read(account: keyAccount), !key.isEmpty {
            set(.active(key: key))
        }
    }

    func activate(key: String) async {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { set(.invalid(reason: "Enter a license key.")); return }
        set(.activating)
        let result = await provider.activate(key: trimmed)
        if result.success {
            keychain.write(trimmed, account: keyAccount)
            set(.active(key: trimmed))
        } else {
            set(.invalid(reason: result.message))
        }
    }

    func deactivate() async {
        if case let .active(key) = state {
            _ = await provider.deactivate(key: key)
        }
        keychain.delete(account: keyAccount)
        set(.unactivated)
    }

    private func set(_ s: LicenseState) {
        state = s
        onChange?(s)
        Log.licensing.info("License state changed")
    }
}

/// Development stub: accepts any non-trivial key. Replace with a real provider.
struct StubLicenseProvider: LicenseProviderProtocol {
    func activate(key: String) async -> ActivationResult {
        // A real provider performs a signed network call. The stub accepts keys
        // that look like `XXXX-XXXX-XXXX-XXXX` for local development.
        let ok = key.count >= 8
        return ActivationResult(success: ok,
                                message: ok ? "Activated" : "That key doesn't look right.")
    }
    func validate(key: String) async -> ActivationResult {
        ActivationResult(success: key.count >= 8, message: "")
    }
    func deactivate(key: String) async -> ActivationResult {
        ActivationResult(success: true, message: "Deactivated")
    }
}
