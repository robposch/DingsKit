import Foundation

/// Which refresh path produced a run. Stamped on every recorded run so the user
/// can tell, after the fact, *which* mechanism actually fired — most usefully
/// whether the throttled `backgroundTask` ever runs while the device is locked,
/// versus the `widgetTimeline` reload carrying freshness on its own.
public enum RefreshSource: String, Codable, Sendable, CaseIterable {
    /// The app's `BGAppRefreshTask` handler — runs unattended, heavily
    /// throttled by iOS, the path we most want to confirm fires.
    case backgroundTask
    /// A widget timeline reload that found the cache stale and fetched itself.
    case widgetTimeline
    /// App in the foreground (cold launch, foreground return, pull-to-refresh).
    case appForeground
}

/// One recorded refresh attempt: when it ran, which path triggered it, whether
/// the fetch succeeded, and an optional short detail (error summary or a stat).
public struct RefreshRun: Codable, Equatable, Sendable {
    public let date: Date
    public let source: RefreshSource
    public let succeeded: Bool
    public let detail: String?

    public init(date: Date, source: RefreshSource, succeeded: Bool, detail: String?) {
        self.date = date
        self.source = source
        self.succeeded = succeeded
        self.detail = detail
    }
}

/// A small, durable ring buffer of recent refresh runs, kept in the App-Group
/// container so the widget extension and the app both write to one shared log
/// the app can display. Unlike `.info`-level unified logging (which is not
/// persisted), this survives so an unattended, while-locked run is still visible
/// when the user next opens the app.
public struct BackgroundRunLog: @unchecked Sendable {
    /// Most-recent runs kept; older ones are dropped. Enough to show a few days
    /// of unattended runs without growing the App-Group store unbounded.
    public static let maxEntries = 20
    private static let key = "backgroundRunLog"
    /// Process-wide, not per instance: callers build a fresh `BackgroundRunLog`
    /// wherever they record, so only a shared lock serializes them.
    private static let lock = NSLock()
    private let defaults: UserDefaults

    /// Production initializer. Returns `nil` if the App Group is unavailable.
    public init?(suiteName: String = AppGroupReadingsCache.defaultSuite) {
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            Log.cache.error("App Group unavailable for run log")
            return nil
        }
        self.defaults = defaults
    }

    /// Test initializer with an injected `UserDefaults`.
    public init(defaults: UserDefaults) { self.defaults = defaults }

    /// Recorded runs, newest first.
    public func entries() -> [RefreshRun] {
        guard let data = defaults.data(forKey: Self.key),
              let runs = try? JSONDecoder().decode([RefreshRun].self, from: data)
        else { return [] }
        return runs.reversed()
    }

    /// Append a run, capping the buffer at `maxEntries` (oldest dropped). Stored
    /// oldest-to-newest; `entries()` reverses for display.
    ///
    /// Serialized within this process. Across processes it is not: the app and
    /// the widget extension each read-modify-write the same App-Group key, so
    /// two of them recording in the same instant can drop one entry. That is
    /// accepted for a diagnostics log. A file lock in the shared container
    /// would close the gap, but iOS kills a process suspended while holding
    /// one (0xdead10cc), which is far worse than a missing log line.
    public func record(source: RefreshSource, succeeded: Bool, detail: String?, date: Date = Date()) {
        Self.lock.lock(); defer { Self.lock.unlock() }
        var runs: [RefreshRun] = {
            guard let data = defaults.data(forKey: Self.key) else { return [] }
            return (try? JSONDecoder().decode([RefreshRun].self, from: data)) ?? []
        }()
        runs.append(RefreshRun(date: date, source: source, succeeded: succeeded, detail: detail))
        if runs.count > Self.maxEntries { runs.removeFirst(runs.count - Self.maxEntries) }
        guard let data = try? JSONEncoder().encode(runs) else { return }
        defaults.set(data, forKey: Self.key)
    }

    public func clear() {
        Self.lock.lock(); defer { Self.lock.unlock() }
        defaults.removeObject(forKey: Self.key)
    }
}
