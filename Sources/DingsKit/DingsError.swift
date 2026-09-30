import Foundation

/// Neutral error surface for the shared infrastructure: networking, refresh
/// orchestration, caching. Provider-specific errors (`ProviderAPIError` for
/// registry providers, or a provider's own enum) stay with their providers;
/// anything genuinely app-agnostic throws this instead, so the shared core
/// carries no vendor's error type.
///
/// DingsKit itself throws `.storage`, `.missingCredentials` and `.network`.
/// `.cache` and `.timeout` exist for consuming apps' own pipelines; note that
/// `withTimeout` throws the separate `TimeoutError`, not `.timeout`.
public enum DingsError: Error, Equatable, Sendable {
    case storage(String)
    case cache(String)
    case timeout
    case missingCredentials(String)
    case network(String)
}

/// Surface the user-facing copy through `localizedDescription` too, so any
/// `error.localizedDescription` call site (the unified log, the run-log
/// diagnostics) shows the real message instead of Foundation's generic
/// "The operation couldn't be completed (… error N)".
extension DingsError: LocalizedError {
    public var errorDescription: String? { userMessage }
}

public extension DingsError {
    /// Human-facing copy, localized through the kit's catalog.
    var userMessage: String {
        switch self {
        case .storage(let message):
            return coreLocalized("Storage error: \(message)")
        case .cache(let message):
            return coreLocalized("Cache error: \(message)")
        case .timeout:
            return coreLocalized("The request timed out.")
        case .missingCredentials(let message):
            return coreLocalized("Missing credentials: \(message)")
        case .network(let message):
            return coreLocalized("Network error: \(message)")
        }
    }
}
