import Foundation

/// Chooses which timestamp(s) to show as a reading's freshness: the sensor
/// measurement time and/or the fetch time — each under an unambiguous label.
public enum Freshness {
    /// Which of the two timestamps a part shows: when the sensor took the
    /// reading (`measured`) or when the app last fetched it (`synced`).
    public enum Kind: String, Sendable {
        case measured = "Measured"
        case synced = "Synced"

        /// Localized display label; `rawValue` stays the stable identifier.
        /// Views must render this, not `rawValue`, or the words show up in
        /// English inside localized UI.
        public var label: String { coreLocalized(.init(rawValue)) }

        /// The compact rendering of the same fact the label states. Compact
        /// surfaces cannot fit "Measured 3 minutes ago" once the duration
        /// string grows, so they show this instead of the word.
        public var symbolName: String {
            switch self {
            case .measured: return "clock"
            case .synced: return "arrow.triangle.2.circlepath"
            }
        }
    }

    /// The freshness parts to display, in order. With a measurement time:
    /// `[.measured(recorded), .synced(fetchedAt)]`. Without one: `[.synced(fetchedAt)]`.
    public static func parts(recorded: Date?, fetchedAt: Date) -> [(kind: Kind, date: Date)] {
        if let recorded { return [(.measured, recorded), (.synced, fetchedAt)] }
        return [(.synced, fetchedAt)]
    }

    /// "3m", "2h", "4d". Accessory families have no room for a sentence, and a
    /// self-ticking relative style re-lays-out every second on the Lock Screen.
    /// Lives here (not on the view) so the vocabulary sits beside the rest of
    /// `Freshness`'s wording, goes through `coreLocalized` like `Kind.label`
    /// does, and is reachable from `DingsKitTests`, which the SwiftUI-only
    /// `DingsKitUI` target has no test target for.
    ///
    /// `now` defaults so tests can pin it; a future `date` (now < date) clamps
    /// to zero rather than printing a negative age.
    public static func shortAge(_ date: Date, now: Date = Date()) -> String {
        let seconds = max(0, now.timeIntervalSince(date))
        if seconds < 60 { return coreLocalized("now") }
        if seconds < 3_600 { return coreLocalized("\(Int(seconds / 60))m") }
        if seconds < 86_400 { return coreLocalized("\(Int(seconds / 3_600))h") }
        return coreLocalized("\(Int(seconds / 86_400))d")
    }
}
