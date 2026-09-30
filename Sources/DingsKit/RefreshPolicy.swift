import Foundation

/// Single source of truth for how often the app polls the provider cloud.
/// The values come from `Dings.config.refresh` (`RefreshPolicyValues`).
///
/// The defaults suit sensors that upload every few minutes to an hour behind
/// a rate-limited API. Worked example from the first consumer: devices report
/// every 2.5 to 60 minutes depending on a setting the API does not expose, and
/// the vendor caps requests at 120 per hour. Polling at a fixed 10-minute
/// floor is fresh enough for the common setup and, at about 3 calls per
/// refresh, uses roughly 18 requests an hour. An app whose provider has a
/// different cadence or cap should set its own values.
public enum RefreshPolicy {

    /// Minimum spacing between cloud fetches, and the cache-staleness threshold
    /// shared by the app (foreground + periodic), the widget, and background
    /// refresh. Defaults to 10 minutes.
    public static var interval: TimeInterval { Dings.config.refresh.interval }

    /// How far out the widget asks WidgetKit to reload its timeline. A little
    /// longer than `interval` to stay within WidgetKit's ~40–70 reloads/day
    /// budget; the app stays the primary fetcher and reloads the widget directly
    /// whenever it refreshes, so the widget's own cadence is only a fallback.
    public static var widgetReloadInterval: TimeInterval { Dings.config.refresh.widgetReloadInterval }

    /// Minimum gap between *user-initiated* refreshes — cold launch, foreground
    /// return, pull-to-refresh. Opening the app is a strong "show me current
    /// data" signal, so the app refreshes eagerly; this short window only stops
    /// rapid app-switching from spamming the API. Deliberately far smaller than
    /// `interval`, which governs *unattended* polling (periodic tick, widget,
    /// background) and exists to protect the provider's rate limit.
    public static var foregroundDedupe: TimeInterval { Dings.config.refresh.foregroundDedupe }

    /// Age of the *fetch* beyond which compact widget surfaces (Lock Screen
    /// circular/inline) show an explicit staleness cue instead of a silent
    /// value. Normal operation refreshes well inside this (app opens, ~15 min
    /// widget reloads), so the cue appears only when every refresh path has
    /// stalled for a while.
    public static var staleCueAfter: TimeInterval { Dings.config.refresh.staleCueAfter }

    /// Age of a device's own *measurement* beyond which the app's "Measured"
    /// row is tinted as a warning. Battery devices report at most hourly, so
    /// three hours means multiple missed reports — the device is likely
    /// offline or out of range.
    public static var deviceStaleCueAfter: TimeInterval { Dings.config.refresh.deviceStaleCueAfter }

    /// Whether enough time has elapsed since the last successful refresh to
    /// fetch again. `nil` (never refreshed) is always due.
    ///
    /// - Parameter minInterval: the staleness window. Defaults to the unattended
    ///   `interval` (10 min); pass `foregroundDedupe` for user-initiated refreshes
    ///   so opening the app fetches promptly instead of waiting out the poll floor.
    public static func shouldRefresh(
        since lastRefreshed: Date?,
        now: Date = Date(),
        minInterval: TimeInterval = interval
    ) -> Bool {
        CacheFreshness.isStale(fetchedAt: lastRefreshed, now: now, maxAge: minInterval)
    }
}
