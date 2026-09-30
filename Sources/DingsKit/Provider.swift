import Foundation

/// Which cloud a device's readings came from. Tags every `DeviceReadings` so
/// the refresh pipeline can merge/replace per provider while everything
/// downstream (cache, widgets, pickers) stays provider-agnostic.
///
/// String-backed and open: consuming apps declare their own constants
/// (`extension Provider { static let myService = Provider("myservice") }`).
/// The raw value is a wire format (caches, keychain account names, widget
/// configs) and must never change once shipped.
public struct Provider: RawRepresentable, Hashable, Codable, Sendable, Identifiable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(_ rawValue: String) { self.rawValue = rawValue }
    public var id: String { rawValue }

    public init(from decoder: Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(rawValue)
    }

    /// Human-facing service name. Resolves from the registered `ProviderSpec`s;
    /// unknown providers fall back to their raw value so nothing renders empty.
    public var displayName: String {
        ProviderSpec.spec(for: self)?.displayName
            ?? Provider.legacyDisplayNames[self]
            ?? rawValue
    }

    /// Names for providers that exist without a registered spec (a consuming
    /// app's bespoke hand-rolled provider paths). Populated via `DingsConfig`-adjacent
    /// app code; empty for apps whose providers all carry specs.
    public static var legacyDisplayNames: [Provider: String] {
        get {
            legacyDisplayNamesLock.lock(); defer { legacyDisplayNamesLock.unlock() }
            return storedLegacyDisplayNames
        }
        set {
            legacyDisplayNamesLock.lock(); defer { legacyDisplayNamesLock.unlock() }
            storedLegacyDisplayNames = newValue
        }
    }

    // Guarded by `legacyDisplayNamesLock`: `displayName` reads this from any
    // thread (widget timeline, background refresh, UI).
    private static let legacyDisplayNamesLock = NSLock()
    nonisolated(unsafe) private static var storedLegacyDisplayNames: [Provider: String] = [:]
}
