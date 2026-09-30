import Foundation

/// What the refresh pipeline needs from any provider: the latest readings for
/// all of the user's devices, mapped into provider-tagged `DeviceReadings`.
/// Registry-driven providers implement this and `ProviderSpec.makeClient`
/// constructs them from stored credentials. A client that needs wiring the
/// registry cannot express is handed to `ReadingsRefresher` through
/// `clientOverrides` instead.
public protocol ProviderClient: Sendable {
    func fetchAllReadings() async throws -> [DeviceReadings]
}

/// Validation seam for a provider's entered credentials. Returns the device
/// count on success so the setup screen can confirm discovery worked.
///
/// Registry-driven providers throw `ProviderAPIError`, but this seam does not
/// guarantee it: a provider may keep its own error enum, and that travels
/// through unwrapped. Anything presenting these errors must therefore handle
/// arbitrary `Error` values, and any provider error type needs a
/// `LocalizedError` conformance so it renders as copy rather than as
/// "The operation couldn't be completed. (Module.Type error N.)".
public protocol ProviderCredentialValidating: Sendable {
    func validate(provider: Provider, credentials: ProviderCredentials) async throws -> Int
}

/// Live validator: builds the provider's client from the registry and fetches
/// once. A successful fetch proves the credentials and doubles as discovery.
public struct LiveProviderCredentialValidator: ProviderCredentialValidating {
    private let transport: Transport

    public init(transport: Transport = URLSessionTransport()) {
        self.transport = transport
    }

    public func validate(provider: Provider, credentials: ProviderCredentials) async throws -> Int {
        guard let spec = ProviderSpec.spec(for: provider) else {
            throw ProviderAPIError.missingCredentials(provider)
        }
        return try await spec.makeClient(credentials, transport).fetchAllReadings().count
    }
}
