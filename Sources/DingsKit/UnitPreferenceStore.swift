import Foundation

/// Single shared source of truth for the unit system, in the App Group so the
/// app and every widget read the same value.
public struct UnitPreferenceStore: @unchecked Sendable {
    private static let key = "unitSystem"
    private let defaults: UserDefaults

    public init?(suiteName: String = AppGroupReadingsCache.defaultSuite) {
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            Log.cache.error("App Group unavailable for unit preference")
            return nil
        }
        self.defaults = defaults
    }

    public init(defaults: UserDefaults) { self.defaults = defaults }

    public func load() -> UnitSystem {
        guard let raw = defaults.string(forKey: Self.key), let system = UnitSystem(rawValue: raw) else {
            return .metric
        }
        return system
    }

    public func save(_ system: UnitSystem) {
        defaults.set(system.rawValue, forKey: Self.key)
        Log.cache.info("unit preference saved: \(system.rawValue)")
    }
}
