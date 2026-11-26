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
            let saved = credentialsToSave(entered: creds)
            try connections.saveCredentials(saved, for: provider)
            state = .connected(maskedID: Self.mask(maskSource(of: saved)))
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

    /// What to save after a successful validation: the entered credentials,
    /// unless the provider declares rotating fields and the stored bag
    /// continues the entered one.
    ///
    /// Validating runs the provider's client once. A client with a rotating
    /// credential (an OAuth refresh token the vendor retires on use) may
    /// rotate it during that fetch and save the new value, plus whatever it
    /// caches (an access token), to the store itself. Saving the entered bag
    /// over that would bring back the retired value, and the next refresh
    /// would fail.
    ///
    /// The stored bag is kept only when it equals the entered one on every
    /// non-rotating form field, and each rotating field either still holds
    /// the entered value or names it as the value it replaced. That ties the
    /// bag to the entered token line; a bag from another connection (an older
    /// one the user is replacing, rotated meanwhile by a background refresh)
    /// fails the check even with the same client ID and secret. Whether the
    /// bag changed during validation does not matter: a stored bag that
    /// already continued the entered value (the user re-entered a token this
    /// app had rotated) must be kept for the same reason.
    ///
    /// The kept bag is still saved, so a store that reacts to saves sees the
    /// final credentials. An unreadable store falls back to the entered
    /// credentials, as before rotations existed.
    private func credentialsToSave(entered: ProviderCredentials) -> ProviderCredentials {
        let rotations = spec.rotatingCredentials
        guard !rotations.isEmpty else { return entered }
        let stored: ProviderCredentials?
        do {
            stored = try connections.loadCredentials(provider)
        } catch {
            Log.credentials.error("connection (\(self.provider.rawValue)): stored credentials unreadable after validation; saving the entered ones")
            return entered
        }
        guard let stored, Self.continues(stored, entered, spec: spec) else { return entered }
        if stored != entered {
            Log.credentials.info("connection (\(self.provider.rawValue)): keeping the credentials the client renewed during validation")
        }
        return stored
    }

    /// Whether `stored` is the same connection as `entered`, possibly with
    /// its rotating fields renewed since.
    static func continues(_ stored: ProviderCredentials, _ entered: ProviderCredentials, spec: ProviderSpec) -> Bool {
        let rotatingIDs = Set(spec.rotatingCredentials.map(\.fieldID))
        let fixedMatch = spec.fields
            .filter { !rotatingIDs.contains($0.id) }
            .allSatisfy { stored[$0.id] == entered[$0.id] }
        guard fixedMatch else { return false }
        return spec.rotatingCredentials.allSatisfy { rotation in
            let value = entered[rotation.fieldID]
            if stored[rotation.fieldID] == value { return true }
            return !value.isEmpty && stored[rotation.previousValueKey] == value
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
