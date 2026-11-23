import Testing
import Foundation
import DingsKit
import DingsKitUI

/// The widget age stamp names one whole unit: "12 minutes", never
/// "12 min, 34 sec". Seconds made the stamp too wide for the footer and mean
/// nothing for these readings.
@Suite struct FreshnessAgeFormatTests {
    private let then = Date(timeIntervalSince1970: 1_800_000_000)

    private func age(_ seconds: TimeInterval, _ locale: String) -> String {
        guard #available(iOS 18.0, macOS 15.0, watchOS 11.0, visionOS 2.0, *) else { return "" }
        return String(Freshness.ageStyle(since: then).locale(Locale(identifier: locale))
            .format(then.addingTimeInterval(seconds)).characters)
    }

    @Test func minutesWithoutSeconds() {
        let text = age(12 * 60 + 34, "en_US")
        #expect(text.contains("12"))
        #expect(!text.contains("34"))
        #expect(!text.lowercased().contains("sec"))
        #expect(!text.contains("ago"))
    }

    @Test func germanMinutesWithoutSeconds() {
        let text = age(12 * 60 + 34, "de_DE")
        #expect(text.contains("12"))
        #expect(!text.contains("34"))
        #expect(!text.contains("Sek"))
        #expect(!text.contains("vor"))
    }

    @Test func roundsDownNeverFresher() {
        #expect(age(12 * 60 + 59, "en_US").contains("12"))
    }

    @Test func hoursShowOneUnit() {
        let text = age(5 * 3600 + 17 * 60, "en_US")
        #expect(text.contains("5"))
        #expect(!text.contains("17"))
    }

    @Test func daysShowOneUnitWithoutNamedDays() {
        let text = age(2 * 86_400 + 3 * 3600, "de_DE")
        #expect(text.contains("2"))
        #expect(!text.contains("3"))
        #expect(!text.contains("vorgestern"))
    }

    @Test func underAMinuteNamesNoSeconds() {
        let text = age(30, "en_US")
        #expect(!text.contains("30"))
        #expect(!text.lowercased().contains("sec"))
    }

    /// A device clock running ahead gives a measurement time in the future.
    /// The age must not count it as time passed: it anchors at "now".
    @Test func aFutureTimeAnchorsAtNow() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(Freshness.ageAnchor(now.addingTimeInterval(300), now: now) == now)
        #expect(Freshness.ageAnchor(now.addingTimeInterval(-300), now: now) == now.addingTimeInterval(-300))
    }
}
