import Testing
import Foundation
@testable import DingsKit

@Suite struct FreshnessTests {
    @Test func measuredPresentReturnsBothPartsInOrder() {
        let recorded = Date(timeIntervalSince1970: 1_000_000)
        let fetched = Date(timeIntervalSince1970: 1_003_600)
        let parts = Freshness.parts(recorded: recorded, fetchedAt: fetched)
        #expect(parts.count == 2)
        #expect(parts[0].kind == .measured)
        #expect(parts[0].date == recorded)
        #expect(parts[1].kind == .synced)
        #expect(parts[1].date == fetched)
    }

    @Test func noMeasuredReturnsSyncedOnly() {
        let fetched = Date(timeIntervalSince1970: 1_003_600)
        let parts = Freshness.parts(recorded: nil, fetchedAt: fetched)
        #expect(parts.count == 1)
        #expect(parts[0].kind == .synced)
        #expect(parts[0].date == fetched)
    }

    @Test func equalDatesStillReturnsBothParts() {
        let t = Date(timeIntervalSince1970: 1_000_000)
        let parts = Freshness.parts(recorded: t, fetchedAt: t)
        #expect(parts.count == 2)
        #expect(parts.map(\.kind) == [.measured, .synced])
        #expect(parts.allSatisfy { $0.date == t })
    }

    @Test func kindRawValuesAreTheWordingContract() {
        #expect(Freshness.Kind.measured.rawValue == "Measured")
        #expect(Freshness.Kind.synced.rawValue == "Synced")
    }

    /// Glyph and word are two renderings of one fact, so the symbol belongs
    /// beside the vocabulary rather than at each call site.
    @Test func kindsCarryTheirOwnSymbol() {
        #expect(Freshness.Kind.measured.symbolName == "clock")
        #expect(Freshness.Kind.synced.symbolName == "arrow.triangle.2.circlepath")
        #expect(Freshness.Kind.measured.symbolName != Freshness.Kind.synced.symbolName)
    }

    // MARK: - shortAge

    private static let anchor = Date(timeIntervalSince1970: 1_000_000)

    private static func age(secondsAgo: Double) -> String {
        Freshness.shortAge(anchor.addingTimeInterval(-secondsAgo), now: anchor)
    }

    @Test func shortAgeJustUnderAMinuteIsNow() {
        #expect(Self.age(secondsAgo: 59) == "now")
    }

    @Test func shortAgeAtExactlyOneMinuteRollsToMinutes() {
        #expect(Self.age(secondsAgo: 60) == "1m")
    }

    @Test func shortAgeJustUnderAnHourIsStillMinutes() {
        // 3599s = 59m59s, floor-divided to 59 whole minutes.
        #expect(Self.age(secondsAgo: 3_599) == "59m")
    }

    @Test func shortAgeAtExactlyOneHourRollsToHours() {
        #expect(Self.age(secondsAgo: 3_600) == "1h")
    }

    @Test func shortAgeJustUnderADayIsStillHours() {
        // 86399s = 23h59m59s, floor-divided to 23 whole hours.
        #expect(Self.age(secondsAgo: 86_399) == "23h")
    }

    @Test func shortAgeAtExactlyOneDayRollsToDays() {
        #expect(Self.age(secondsAgo: 86_400) == "1d")
    }

    /// A `date` after `now` (e.g. clock skew between the widget process and
    /// the reading) must clamp to zero elapsed seconds rather than printing a
    /// negative age.
    @Test func shortAgeClampsAFutureDateToNowRatherThanGoingNegative() {
        let future = Self.anchor.addingTimeInterval(120)
        #expect(Freshness.shortAge(future, now: Self.anchor) == "now")
    }
}
