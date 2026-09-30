import Foundation

/// The single sensor the "Switcher" Lock Screen widget currently shows, stored in
/// the App Group so the arrow intent (which writes it) and the widget provider
/// (which reads it) share one value. Global per widget kind by design: all
/// Switcher instances track the same selection. Mirrors `UnitPreferenceStore`.
public struct StepperSensorStore: @unchecked Sendable {
    private static let key = "stepperSelectedSensor"
    private let defaults: UserDefaults

    public init?(suiteName: String = AppGroupReadingsCache.defaultSuite) {
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            Log.cache.error("App Group unavailable for stepper selection")
            return nil
        }
        self.defaults = defaults
    }

    public init(defaults: UserDefaults) { self.defaults = defaults }

    /// The stored sensor, or `nil` if none has been chosen yet.
    public func load() -> SensorType? {
        guard let raw = defaults.string(forKey: Self.key) else { return nil }
        return SensorType(apiValue: raw)
    }

    public func save(_ type: SensorType) {
        defaults.set(type.rawAPIValue, forKey: Self.key)
        Log.cache.info("stepper selection saved: \(type.rawAPIValue)")
    }
}
