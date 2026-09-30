import Foundation

/// Credentials for a registry-driven provider: an ordered-agnostic bag of
/// named secrets ("apiKey", "applicationKey", "token", …). One shape for all
/// generic providers so the keychain store, the setup form, and the client
/// factory don't need a bespoke struct per service. Field IDs come from the
/// provider's `ProviderSpec.fields`.
public struct ProviderCredentials: Equatable, Sendable, Codable {
    public var fields: [String: String]

    public init(fields: [String: String]) {
        self.fields = fields
    }

    /// Convenience accessor: missing keys read as empty, never nil, so client
    /// code can validate lengths instead of unwrapping.
    public subscript(_ key: String) -> String {
        get { fields[key] ?? "" }
        set { fields[key] = newValue }
    }
}

/// Persistence seam for one provider's credentials. Apps ship
/// `KeychainProviderCredentialStore`; tests use
/// `InMemoryProviderCredentialStore` from `DingsKitTestSupport`.
public protocol ProviderCredentialStore: Sendable {
    func load() throws -> ProviderCredentials?
    func save(_ credentials: ProviderCredentials) throws
    func clear() throws
}
