import SwiftUI
import DingsKit

/// How much room the surface has for a freshness stamp.
public enum FreshnessDensity: Sendable {
    /// Label word plus a relative time. No widget uses this any more (both
    /// apps' Home Screen widgets moved to `.compact` so their stamps match);
    /// an app screen adopting it must pass `ticking: false` (see
    /// `FreshnessLine.init`) since the default follows the widget case, not
    /// the app-screen one.
    case full
    /// Glyph plus a relative time. Every Home Screen widget in both apps.
    case compact
    /// Glyph plus a short age ("3m"), for accessory (Lock Screen) families.
    /// No app has adopted it yet: LuftDings' accessory views keep their own
    /// short-age helper with shipped translations, and switching would
    /// change that wording. `ticking` has no effect on this density (see
    /// below).
    case minimal
}

/// Whether the parts share one line or stack.
public enum FreshnessLayout: Sendable { case inline, stacked }

/// One rendering of `Freshness.parts`, degrading word to glyph as the surface
/// shrinks. Both apps use this so a freshness stamp cannot drift between them,
/// and so the overflow that forced accessory views to hand-roll a glyph is
/// solved once rather than per call site.
public struct FreshnessLine: View {
    private let recorded: Date?
    private let fetchedAt: Date
    private let density: FreshnessDensity
    private let layout: FreshnessLayout
    private let ticking: Bool

    /// - Parameter ticking: Whether the relative time self-updates between
    ///   renders. This is a property of the *surface*, not of `density`: a
    ///   widget wants a stamp that keeps counting up between timeline
    ///   reloads at no reload cost, while an app screen does not, because a
    ///   self-ticking relative style re-lays-out every second and re-layout
    ///   on every tick is exactly what caused a prior incident there.
    ///   Defaults to `true` because every current consumer is a widget; an
    ///   app screen adopting `.full` must pass `ticking: false` explicitly.
    ///   Ignored by `.minimal`, which always renders a static short age
    ///   regardless of this flag.
    public init(recorded: Date?, fetchedAt: Date,
                density: FreshnessDensity = .compact,
                layout: FreshnessLayout = .inline,
                ticking: Bool = true) {
        self.recorded = recorded
        self.fetchedAt = fetchedAt
        self.density = density
        self.layout = layout
        self.ticking = ticking
    }

    private var parts: [(kind: Freshness.Kind, date: Date)] {
        Freshness.parts(recorded: recorded, fetchedAt: fetchedAt)
    }

    /// One column for every glyph. The clock and the sync arrows are
    /// different widths, so without this the two stacked lines start their
    /// text at different x and read as misaligned. Sized for the caption
    /// fonts every compact/minimal consumer uses, scaling with Dynamic Type.
    @ScaledMetric(relativeTo: .caption2) private var glyphWidth: CGFloat = 16

    /// The glyph, in its fixed column, hidden from VoiceOver because each
    /// density's accessibility label already states the kind in words.
    private func glyph(_ kind: Freshness.Kind) -> some View {
        Image(systemName: kind.symbolName)
            .frame(width: glyphWidth, alignment: .center)
            .accessibilityHidden(true)
    }

    public var body: some View {
        switch layout {
        case .inline:
            HStack(spacing: 6) {
                ForEach(parts.indices, id: \.self) { i in
                    // Matches the deleted widget-local renderer's separator: a
                    // plain middle dot with a space either side, styled by
                    // whatever the caller applied to the whole line (font,
                    // foregroundStyle), same as the parts themselves.
                    if i > 0 { Text(verbatim: " · ") }
                    part(parts[i])
                }
            }
        case .stacked:
            // Each part already starts its own line, so no separator is needed.
            VStack(alignment: .leading, spacing: 1) { ForEach(parts.indices, id: \.self) { part(parts[$0]) } }
        }
    }

    /// Both halves are already localized; a `String` (not a literal, which
    /// would become a `LocalizedStringKey` looked up in the host app's
    /// bundle) keeps the label verbatim.
    private func spokenLabel(_ p: (kind: Freshness.Kind, date: Date)) -> String {
        "\(p.kind.label) \(p.date.formatted(.relative(presentation: .named)))"
    }

    @ViewBuilder
    private func part(_ p: (kind: Freshness.Kind, date: Date)) -> some View {
        switch density {
        case .full:
            // The app screen has room for the word and reads better with it.
            // Whether the time itself ticks is the caller's call, not this
            // density's: widgets need it, app screens don't (see `ticking`).
            HStack(spacing: 4) {
                Text(p.kind.label)
                if ticking {
                    Text(p.date, style: .relative)
                } else {
                    Text(p.date, format: .relative(presentation: .named))
                }
            }
            // Without this, VoiceOver reads the word and the relative time as
            // two separate elements ("Measured", then "12 min, 0 sec")
            // instead of the one fact this view exists to state. Same
            // reasoning as `.compact` below.
            .accessibilityLabel(spokenLabel(p))
        case .compact:
            // Baseline-aligned: centering the glyph on the text's box put the
            // sync arrows visibly lower than the clock.
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                glyph(p.kind)
                if ticking {
                    Text(p.date, style: .relative)
                } else {
                    Text(p.date, format: .relative(presentation: .named))
                }
            }
            // The glyph is decorative and hidden above, so without an explicit
            // label VoiceOver would announce only the bare relative time with
            // no indication of which kind it is. Folding the word back in here
            // (rather than just substituting it) keeps the elapsed time too:
            // a label that dropped it would silently un-announce the one fact
            // this view exists to state.
            .accessibilityLabel(spokenLabel(p))
        case .minimal:
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                glyph(p.kind)
                Text(Freshness.shortAge(p.date))
            }
            .accessibilityLabel(spokenLabel(p))
        }
    }
}
