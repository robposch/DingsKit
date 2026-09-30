import Foundation

/// One error surface shared by every generic (registry-driven) provider, so
/// each new integration doesn't grow its own `XxxError` twin the way
/// the original bespoke providers did. Legacy providers keep their enums;
/// everything added after those first providers throws this.
public enum ProviderAPIError: Error, Equatable, Sendable {
    case missingCredentials(Provider)
    /// `hint` carries the provider-specific recovery step ("create a new key
    /// at …"), written by the client that detected the 401.
    case invalidCredentials(Provider, hint: String)
    case network(Provider, String)
    case decoding(Provider, String)
    case http(Provider, Int)
    case storage(Provider, String)
}

/// Same rationale as a bespoke provider's own error type: route the user-facing copy through
/// `localizedDescription` so run-log diagnostics show the real message.
extension ProviderAPIError: LocalizedError {
    public var errorDescription: String? { userMessage }
}

public extension ProviderAPIError {
    var userMessage: String {
        switch self {
        case .missingCredentials(let provider):
            return coreLocalized("\(provider.displayName): no saved credentials.")
        case .invalidCredentials(let provider, let hint):
            return coreLocalized("\(provider.displayName) rejected the credentials: \(hint)")
        case .network(let provider, let message):
            return coreLocalized("\(provider.displayName) network error: \(message)")
        case .decoding(let provider, let message):
            return coreLocalized("Could not parse the \(provider.displayName) response: \(message)")
        case .http(let provider, let status):
            return coreLocalized("\(provider.displayName) returned HTTP \(status). Try again later.")
        case .storage(let provider, let message):
            return coreLocalized("\(provider.displayName) storage error: \(message)")
        }
    }
}
