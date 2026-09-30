import Foundation

/// Which unit system a value is displayed in. The per-sensor conversion table
/// is provider-specific and lives with the consuming app; DingsKit owns only
/// the choice itself and its persistence (`UnitPreferenceStore`).
public enum UnitSystem: String, Codable, Sendable, CaseIterable {
    case metric
    case imperial
}
