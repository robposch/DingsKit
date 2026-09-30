import Foundation

/// What one `ReadingsRefresher.refresh()` pass produced: the merged devices
/// plus how each provider fared, so the caller can show data and explain a
/// partial failure at the same time.
public struct ReadingsResult: Sendable {
    public let devices: [DeviceReadings]
    public let rateLimitRemaining: Int?
    /// Per-provider fetch outcomes from a multi-provider refresh; empty for a
    /// direct single-client fetch (or demo mode).
    public let outcomes: [ProviderRefreshOutcome]
    /// When each provider last fetched successfully — carried over from the
    /// previous snapshot for a provider that failed this run. Empty for a
    /// direct single-client fetch.
    public let providerFetchedAt: [Provider: Date]

    public init(devices: [DeviceReadings], rateLimitRemaining: Int?,
                outcomes: [ProviderRefreshOutcome] = [],
                providerFetchedAt: [Provider: Date] = [:]) {
        self.devices = devices
        self.rateLimitRemaining = rateLimitRemaining
        self.outcomes = outcomes
        self.providerFetchedAt = providerFetchedAt
    }

    /// Compact per-provider outcome line for the refresh run log,
    /// e.g. "Provider 1 ✓ · Provider 2 ✗ token rejected". `nil` when there is nothing
    /// worth saying — no outcomes, or a single provider that just succeeded.
    public var outcomeSummary: String? {
        guard !outcomes.isEmpty else { return nil }
        if outcomes.count == 1, outcomes[0].succeeded { return nil }
        return outcomes.map { outcome in
            let mark = outcome.succeeded ? "✓" : "✗"
            let suffix = outcome.succeeded ? "" : outcome.message.map { " \($0)" } ?? ""
            return "\(outcome.provider.displayName) \(mark)\(suffix)"
        }.joined(separator: " · ")
    }
}

/// How one provider's fetch went during a `ReadingsRefresher.refresh()` pass.
public struct ProviderRefreshOutcome: Equatable, Sendable {
    public let provider: Provider
    public let succeeded: Bool
    /// Failure detail (the error's user message); `nil` on success.
    public let message: String?

    public init(provider: Provider, succeeded: Bool, message: String?) {
        self.provider = provider
        self.succeeded = succeeded
        self.message = message
    }
}

/// A provider client that observes the vendor's rate-limit headers. Checked
/// after each successful fetch; last reporter wins.
public protocol RateLimitReporting {
    var rateLimitRemaining: Int? { get }
}
