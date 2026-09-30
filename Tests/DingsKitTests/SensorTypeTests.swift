import Testing
import Foundation
@testable import DingsKit
import DingsKitTestSupport

private let withShort = SensorType("particulateMatterFine")
private let labelOnly = SensorType("humidity")
private let unregistered = SensorType("virusRisk")

private let sensors = [
    SensorDescriptor(type: withShort, label: "Fine particles", shortLabel: "PM2.5", symbolName: "aqi.medium"),
    SensorDescriptor(type: labelOnly, label: "Relative humidity", symbolName: "humidity"),
]

extension GlobalConfig {
    /// In `GlobalConfig` because display metadata resolves against the sensors
    /// registered in `Dings.config`.
    @Suite struct SensorTypeTests {
        init() { TestDings.bootstrap(sensors: sensors) }

        @Test func registeredTypeUsesItsDescriptor() {
            #expect(withShort.label == "Fine particles")
            #expect(withShort.shortLabel == "PM2.5")
            #expect(withShort.symbolName == "aqi.medium")
        }

        /// Without an explicit short label, the registered label is truncated
        /// to the budget.
        @Test func registeredWithoutShortLabelTruncatesItsLabel() {
            #expect(labelOnly.label == "Relative humidity")
            #expect(labelOnly.shortLabel == "Relati")
            #expect(labelOnly.symbolName == "humidity")
        }

        /// Unregistered types degrade to a humanized label and a generic
        /// symbol, never the raw lowercase key.
        @Test func unregisteredTypeIsHumanized() {
            #expect(unregistered.label == "Virus Risk")
            #expect(unregistered.shortLabel.count <= SensorType.shortLabelMaxLength)
            #expect(unregistered.shortLabel.hasPrefix("Virus"))
            #expect(unregistered.symbolName == "gauge")
        }

        @Test(arguments: [
            ("co2", "Co2"),
            ("radonShortTermAvg", "Radon Short Term Avg"),
            ("temp", "Temp"),
            ("", ""),
        ])
        func humanizeSplitsCamelCase(raw: String, expected: String) {
            #expect(SensorType(raw).label == expected)
        }

        /// Every fallback short label fits the circular Lock Screen budget.
        @Test(arguments: ["virusRisk", "humidity", "co2", "radonShortTermAvg", "x", ""])
        func fallbackShortLabelsFitTheBudget(raw: String) {
            #expect(SensorType(raw).shortLabel.count <= SensorType.shortLabelMaxLength)
        }

        /// Truncating a multi-word fallback label at the budget can land on the
        /// space between words ("Virus Risk" -> "Virus "); the space is trimmed
        /// so the caption stays centered.
        @Test func fallbackShortLabelHasNoTrailingWhitespace() {
            #expect(unregistered.shortLabel == "Virus")
        }

        @Test func budgetIsSix() {
            #expect(SensorType.shortLabelMaxLength == 6)
        }

        /// The raw value is the wire format: it encodes as a bare string.
        @Test func encodesAsBareRawValue() throws {
            let data = try JSONEncoder().encode([unregistered])
            #expect(String(bytes: data, encoding: .utf8) == #"["virusRisk"]"#)
            #expect(try JSONDecoder().decode([SensorType].self, from: data) == [unregistered])
            #expect(SensorType(apiValue: "virusRisk") == unregistered)
            #expect(unregistered.rawAPIValue == "virusRisk")
        }
    }
}

/// `displayUnit` is a pure mapping, independent of `Dings.config`.
@Suite struct SensorReadingDisplayUnitTests {
    private static let table: [(String, String)] = [
        ("c", "°C"), ("f", "°F"), ("pct", "%"), ("bq", "Bq/m³"),
        ("ppm", "ppm"), ("ppb", "ppb"), ("mbar", "mbar"), ("mb", "mbar"),
        ("ugpm3", "µg/m³"), ("mgpc", "µg/m³"),
        ("riskindex", ""), ("riskIndex", ""), ("uvindex", ""), ("count", ""), ("epoch", ""), ("index", ""),
        ("mps", "m/s"), ("deg", "°"), ("wpm2", "W/m²"), ("lux", "lx"), ("mmph", "mm/h"),
        ("kgpm3", "kg/m³"), ("db", "dB"),
    ]

    @Test(arguments: table)
    func knownCodesNormalize(code: String, expected: String) {
        let reading = SensorReading(type: SensorType("x"), value: 1, unit: code, quality: .unrated)
        #expect(reading.displayUnit == expected)
    }

    /// Anything unrecognised passes through unchanged rather than vanishing.
    @Test(arguments: ["mg/dL", "mmol/L", "", "C"])
    func unknownCodesPassThrough(code: String) {
        let reading = SensorReading(type: SensorType("x"), value: 1, unit: code, quality: .unrated)
        #expect(reading.displayUnit == code)
    }
}
