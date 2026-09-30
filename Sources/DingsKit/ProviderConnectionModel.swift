import Foundation
import Observation

/// Drives the generic setup form for one registry-driven provider: holds the
/// entered field values (keyed by `CredentialFieldSpec.id`), validates them
/// against the provider's API, and persists them on success.
@MainActor
@Observable
public final class ProviderConnectionModel: Identifiable {
    /// Distinct, non-ambiguous states so the UI never looks "empty" when it isn't.
    /// An app with a hand-written setup form of its own can reuse this enum
    /// so every form shares one state vocabulary.
    public enum State: Equatable, Sendable {
        case empty                        // nothing saved → entry form
        case validating                   // checking entered credentials
        case invalid(String)              // entered credentials don't work → form + reason
        case connected(maskedID: String)  // saved, validated, ready → connection card
    }

    public let spec: ProviderSpec
    public private(set) var state: State = .empty
    public var values: [String: String] = [:]

    private let connections: ConnectionsStore
    private let validator: any ProviderCredentialValidating

    public var provider: Provider { spec.provider }
    public nonisolated var id: Provider { spec.provider }

    #if canImport(Security)
    public init(
        spec: ProviderSpec,
        connections: ConnectionsStore = ConnectionsStore(),
        validator: any ProviderCredentialValidating = LiveProviderCredentialValidator()
    ) {
        self.spec = spec
        self.connections = connections
        self.validator = validator
    }
    #else
    // Keychain-backed defaults need the Security framework; without it the
    // caller must inject the stores.
    public init(
        spec: ProviderSpec,
        connections: ConnectionsStore,
        validator: any ProviderCredentialValidating
    ) {
        self.spec = spec
        self.connections = connections
        self.validator = validator
    }
    #endif

    public func load() {
        let stored = try? connections.loadCredentials(provider)
        if let stored {
            state = .connected(maskedID: Self.mask(maskSource(of: stored)))
            Log.credentials.info("connection (\(self.provider.rawValue)): saved credentials present")
        } else {
            state = .empty
            Log.credentials.info("connection (\(self.provider.rawValue)): none saved")
        }
    }

    public func disconnect(_ onDisconnected: () -> Void) {
        try? connections.clear(provider)
        values = [:]
        state = .empty
        Log.credentials.notice("connection (\(self.provider.rawValue)): disconnected (cleared)")
        onDisconnected()
    }

    /// True while any declared field is still blank — drives the form's
    /// connect-button enablement.
    public var incomplete: Bool {
        spec.fields.contains { values[$0.id, default: ""].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    public func validateAndSave(_ onConnected: () -> Void) async {
        var fields: [String: String] = [:]
        for field in spec.fields {
            fields[field.id] = values[field.id, default: ""].trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let creds = ProviderCredentials(fields: fields)
        state = .validating
        Log.credentials.info("connection (\(self.provider.rawValue)): validating (\(fields.count) field(s))")
        do {
            let deviceCount = try await validator.validate(provider: provider, credentials: creds)
            try connections.saveCredentials(creds, for: provider)
            state = .connected(maskedID: Self.mask(maskSource(of: creds)))
            Log.credentials.info("connection (\(self.provider.rawValue)): validated & saved — \(deviceCount) device(s)")
            onConnected()
        } catch let error as ProviderAPIError {
            state = .invalid(error.userMessage)
            Log.credentials.error("connection (\(self.provider.rawValue)): invalid — \(error.userMessage)")
        } catch let error as LocalizedError where error.errorDescription != nil {
            // A provider error that already carries user-facing copy. An
            // app's own per-provider error types are defined above this
            // package, so they cannot be caught by concrete type here — but
            // they route their copy through `errorDescription`, and a
            // sign-in the provider itself rejected is not "unexpected".
            let message = error.errorDescription ?? error.localizedDescription
            state = .invalid(message)
            Log.credentials.error("connection (\(self.provider.rawValue)): invalid — \(message)")
        } catch {
            state = .invalid(coreLocalized("Unexpected error: \(error.localizedDescription)"))
            Log.credentials.error("connection (\(self.provider.rawValue)): error — \(error.localizedDescription)")
        }
    }

    /// The value shown masked on the connection card: the first declared
    /// field, which by convention is the identifying one (a client ID or
    /// username) rather than the secret.
    private func maskSource(of credentials: ProviderCredentials) -> String {
        guard let first = spec.fields.first else { return "" }
        return credentials[first.id]
    }

    private static func mask(_ id: String) -> String {
        id.count > 4 ? "••••" + id.suffix(4) : "••••"
    }
}
