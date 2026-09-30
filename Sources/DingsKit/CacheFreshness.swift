import Foundation

/// Stateless helper that decides whether a cached snapshot is stale.
///
/// All callers (app foreground, background refresh, widget stale-fetch) share
/// the same staleness threshold so behavior is consistent.
public enum CacheFreshness {

    /// Returns `true` when the snapshot is considered stale and a network
    /// refresh is warranted.
    ///
    /// - Parameters:
    ///   - fetchedAt: The timestamp recorded when the snapshot was last written.
    ///                `nil` (no cache) is always stale.
    ///   - now:       Current time. Defaults to `Date()`; inject for testing.
    ///   - maxAge:    Seconds after which a snapshot is considered stale.
    ///                Defaults to `RefreshPolicy.interval` (10 min) — the device
    ///                cloud-reporting floor — so all callers share one cadence.
    public static func isStale(
        fetchedAt: Date?,
        now: Date = Date(),
        maxAge: TimeInterval = RefreshPolicy.interval
    ) -> Bool {
        guard let fetchedAt else { return true }
        return now.timeIntervalSince(fetchedAt) >= maxAge
    }
}
