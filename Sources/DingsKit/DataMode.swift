import Foundation

/// Whether the app shows live provider data or built-in demo data.
public enum DataMode: String, Sendable, Equatable {
    case live
    case demo
}

/// App-Group-backed persistence for `DataMode`, mirroring `UnitPreferenceStore`.
public struct DataModeStore: @unchecked Sendable {
    private static let key = "dataMode"
    private let defaults: UserDefaults

    public init?(suiteName: String = AppGroupReadingsCache.defaultSuite) {
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            Log.cache.error("App Group unavailable for data mode")
            return nil
        }
        self.defaults = defaults
    }

    public init(defaults: UserDefaults) { self.defaults = defaults }

    public func load() -> DataMode {
        guard let raw = defaults.string(forKey: Self.key), let mode = DataMode(rawValue: raw) else {
            return .live
        }
        return mode
    }

    public func save(_ mode: DataMode) {
        defaults.set(mode.rawValue, forKey: Self.key)
        Log.cache.info("data mode saved: \(mode.rawValue)")
    }
}
