import AppIntents
import WidgetKit

/// Tap-to-refresh for the widget (iOS 17 interactive widgets). Runs the same
/// client-side fetch the app uses, writes the shared App-Group cache, and
/// reloads the timeline: an on-demand refresh that doesn't wait on WidgetKit's
/// background reload budget. Shared by every consuming app's widget target;
/// none of the wiring here is app-specific.
///
/// Fail-soft: a network or credential error leaves the cache untouched so the
/// widget keeps showing its last good data. In demo mode the refresher serves
/// demo data (via `DingsConfig.makeRefresher` or `DingsConfig.demoTransport`),
/// so the button works there too.
@available(visionOS 26, *) // WidgetCenter; the package's visionOS floor is 1
public struct RefreshReadingsIntent: AppIntent {
    // AppIntents resolves intent metadata against the *main* bundle only (the
    // metadata processor rejects any other), so these two strings cannot come
    // from the kit's catalog: the host app translates them in its own.
    public static let title: LocalizedStringResource = "Refresh readings"
    // periphery:ignore - AppIntent protocol requirement, read by the system, not by us
    public static let description = IntentDescription("Fetch the latest readings now.")
    /// Keep the user on the Home Screen; the refresh runs in the background.
    public static let openAppWhenRun: Bool = false

    public init() {}

    public func perform() async throws -> some IntentResult {
        let cache = AppGroupReadingsCache()
        let lastFetch = cache?.load()?.fetchedAt
        guard RefreshPolicy.shouldRefresh(since: lastFetch, minInterval: RefreshPolicy.foregroundDedupe) else {
            Log.widget.info("widget tap refresh skipped: within \(Int(RefreshPolicy.foregroundDedupe))s dedupe window")
            // Skipping the *fetch* is right (the data is already fresh), but the tap
            // must not be silent. Returning without a reload renders the button dead:
            // tap the Switcher (which refreshes everything), then tap a circular
            // within the window, and nothing at all happens, which reads as "the
            // one-value widgets can't refresh". Reloading re-renders from cache, so
            // the freshness stamp moves and the tap is visibly acknowledged.
            WidgetCenter.shared.reloadAllTimelines()
            return .result()
        }
        let refresher = Dings.config.makeRefresher?(cache)
            ?? ReadingsRefresher(
                connections: ConnectionsStore(),
                cache: cache,
                demoTransport: Dings.config.demoTransport?() ?? MockTransport())
        do {
            try await refresher.refresh()
            Log.widget.info("widget refresh: cache updated")
        } catch {
            Log.widget.notice("widget refresh failed: \(error.localizedDescription)")
        }
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}
