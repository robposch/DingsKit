import Foundation

/// A sensor reading's kind. String-backed and open: the raw value is the
/// provider API's field name and the shipped wire format. Display metadata
/// (label, short label, SF Symbol) comes from the `SensorDescriptor`s the app
/// registered in `DingsConfig`; unregistered types degrade gracefully
/// (humanized label, `gauge` symbol) so an unknown-but-real sensor never
/// renders as a raw lowercase key.
public struct SensorType: RawRepresentable, Hashable, Codable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(_ rawValue: String) { self.rawValue = rawValue }
    /// Same as `init(rawValue:)`, spelled for mappers, where the argument is
    /// the provider API's own field name (`SensorType(apiValue: raw)`).
    public init(apiValue: String) { self.rawValue = apiValue }
    /// Same as `rawValue`; the read-side twin of `init(apiValue:)`.
    public var rawAPIValue: String { rawValue }

    public init(from decoder: Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(rawValue)
    }

    private var descriptor: SensorDescriptor? {
        Dings.config.sensors.first { $0.type == self }
    }

    public var label: String { descriptor?.label ?? Self.humanize(rawValue) }

    /// Compact label for very tight slots (circular Lock Screen caption). A
    /// registered `SensorDescriptor.shortLabel` is used as given; otherwise
    /// the label is cut to `shortLabelMaxLength` characters.
    public var shortLabel: String {
        descriptor?.shortLabel
            ?? String((descriptor?.label ?? Self.humanize(rawValue)).prefix(Self.shortLabelMaxLength))
                .trimmingCharacters(in: .whitespaces)
    }

    /// Character budget for a fallback `shortLabel`.
    public static let shortLabelMaxLength = 6

    public var symbolName: String { descriptor?.symbolName ?? "gauge" }

    /// "virusRisk" -> "Virus Risk"; fallback label for unregistered sensors.
    static func humanize(_ raw: String) -> String {
        guard !raw.isEmpty else { return raw }
        var words: [String] = []
        var current = ""
        for ch in raw {
            if ch.isUppercase && !current.isEmpty {
                words.append(current)
                current = String(ch)
            } else {
                current.append(ch)
            }
        }
        if !current.isEmpty { words.append(current) }
        return words.map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
    }
}

/// A provider-neutral severity for one reading. Each provider's mapper rates
/// its own values (the thresholds are domain knowledge that lives with the
/// app); everything downstream only needs this scale to tint and word it.
public enum QualityRating: String, Equatable, Sendable, Codable {
    case good, fair, poor, unrated

    /// Unlocalized lowercase word, empty for `.unrated`. For logs and
    /// identifiers; show `displayText` to users.
    public var text: String {
        switch self {
        case .good: return "good"
        case .fair: return "fair"
        case .poor: return "poor"
        case .unrated: return ""
        }
    }

    /// Localized, human-facing rating word ("Good"/"Fair"/"Poor"), empty for
    /// `.unrated`. Views state severity in *text* with this so the rating
    /// survives color-blind viewing and reaches VoiceOver — the tinted glyph
    /// alone carries it only by hue.
    public var displayText: String {
        switch self {
        case .good: return coreLocalized("Good")
        case .fair: return coreLocalized("Fair")
        case .poor: return coreLocalized("Poor")
        case .unrated: return ""
        }
    }
}

/// One measured value from a device: what it is, the number, the provider
/// API's own unit code, and the mapper's rating of it.
public struct SensorReading: Equatable, Sendable, Codable {
    public let type: SensorType
    public let value: Double
    public let unit: String
    public let quality: QualityRating

    public init(type: SensorType, value: Double, unit: String, quality: QualityRating) {
        self.type = type
        self.value = value
        self.unit = unit
        self.quality = quality
    }

    /// Human-facing unit string. Provider APIs use terse and inconsistent unit
    /// codes (`mgpc` and `ugpm3` both mean µg/m³); normalizing here makes
    /// every target (app, widget) render them identically.
    ///
    /// The table covers the codes the apps built on DingsKit have met so far,
    /// which are air-quality and weather-station units. An unknown code is
    /// shown as-is, so a provider with other units can pass display-ready
    /// strings. Making this table registrable per app is on the roadmap.
    public var displayUnit: String {
        switch unit {
        case "c": return "°C"
        case "f": return "°F"
        case "pct": return "%"
        case "bq": return "Bq/m³"
        case "ppm": return "ppm"
        case "ppb": return "ppb"
        case "mbar": return "mbar"
        case "ugpm3", "mgpc": return "µg/m³"
        case "riskindex", "riskIndex": return ""   // mold / virus risk: a 0–10 index, no unit
        // Weather-station observation units (fixed metric base units).
        case "mb": return "mbar"
        case "mps": return "m/s"
        case "deg": return "°"
        case "uvindex": return ""    // UV index: dimensionless
        case "wpm2": return "W/m²"
        case "lux": return "lx"
        case "mmph": return "mm/h"
        case "count": return ""      // lightning strike count: a bare tally
        case "epoch": return ""      // rendered as an absolute time, never a number
        case "kgpm3": return "kg/m³"
        case "db": return "dB"       // sound pressure level (vendor fields like spl_a / noise)
        case "index": return ""      // vendor VOC/NOx index and score fields: dimensionless
        default: return unit
        }
    }
}

/// One device's latest readings, tagged with the provider they came from.
/// The unit every layer passes around: clients return it, the cache stores
/// it, widgets render it. `serialNumber` is only unique within a provider.
public struct DeviceReadings: Equatable, Sendable, Codable {
    public let serialNumber: String
    public let name: String
    public let model: String
    public let readings: [SensorReading]
    public let batteryPercentage: Int?
    public let recorded: Date?
    public let provider: Provider

    public init(
        serialNumber: String,
        name: String,
        model: String,
        readings: [SensorReading],
        batteryPercentage: Int?,
        recorded: Date?,
        provider: Provider
    ) {
        self.serialNumber = serialNumber
        self.name = name
        self.model = model
        self.readings = readings
        self.batteryPercentage = batteryPercentage
        self.recorded = recorded
        self.provider = provider
    }

    private enum CodingKeys: String, CodingKey {
        case serialNumber, name, model, readings, batteryPercentage, recorded, provider
    }

    /// Custom decode so snapshots and widget configs written before the `provider`
    /// key existed keep decoding. When the key is absent, the provider is taken
    /// from `Dings.config.legacyDecodeProvider` (an app names its original
    /// provider); if that is `nil`, the payload is undecodable and we throw.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        serialNumber = try c.decode(String.self, forKey: .serialNumber)
        name = try c.decode(String.self, forKey: .name)
        model = try c.decode(String.self, forKey: .model)
        readings = try c.decode([SensorReading].self, forKey: .readings)
        batteryPercentage = try c.decodeIfPresent(Int.self, forKey: .batteryPercentage)
        recorded = try c.decodeIfPresent(Date.self, forKey: .recorded)
        if let decoded = try c.decodeIfPresent(Provider.self, forKey: .provider) {
            provider = decoded
        } else if let fallback = Dings.config.legacyDecodeProvider {
            provider = fallback
        } else {
            throw DecodingError.keyNotFound(CodingKeys.provider, .init(
                codingPath: c.codingPath,
                debugDescription: "No `provider` key and no Dings.config.legacyDecodeProvider set."))
        }
    }
}
