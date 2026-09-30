import SwiftUI

/// One row in an onboarding page's bullet list: a symbol, a bold title, and a
/// secondary detail line. `detail` may be an empty string, in which case
/// `OnboardingPageView` renders the row as a symbol and title only; that lets
/// a caller model an "optional" detail without widening this type to
/// `String?` and forcing every other consumer to unwrap it.
public struct OnboardingBullet: Identifiable, Sendable {
    // Derived from `symbolName` + `title` rather than a stored `UUID()`: a
    // `UUID()` default is evaluated fresh every time the owning view's body
    // rebuilds the bullet array, so `ForEach` saw a new identity on every
    // render, rebuilding rows and discarding VoiceOver focus even though
    // nothing about the row actually changed.
    public var id: String { symbolName + title }
    public let symbolName: String
    public let title: String
    public let detail: String

    public init(symbolName: String, title: String, detail: String) {
        self.symbolName = symbolName
        self.title = title
        self.detail = detail
    }
}

/// Shared full-screen onboarding page chrome: a large title, a secondary
/// subtitle, a scrolling list of bullet rows, an optional footnote below the
/// list, and a prominent primary button pinned under the scroll content.
/// Both onboarding pages that follow (what the data actually does, what was
/// just connected) are built on this one shell so the two flows read as one
/// design instead of two hand-rolled ones. Every string is a parameter;
/// this type carries no vocabulary of its own.
public struct OnboardingPageView: View {
    private let title: String
    private let subtitle: String
    private let bullets: [OnboardingBullet]
    private let actionTitle: String
    private let action: () -> Void
    private let footnote: String?
    private let explicitActionAccessibilityIdentifier: String?

    /// - Parameter footnote: An optional line rendered below the bullet list,
    ///   above the primary button. Not part of the bullet list itself because
    ///   a caller may need one line of context (e.g. where to find a
    ///   per-widget picker) that reads as an aside rather than another fact
    ///   with equal visual weight to the bullets above it.
    /// - Parameter actionAccessibilityIdentifier: A stable identifier for the
    ///   primary button. Defaults to `nil`, which falls back to slugging
    ///   `actionTitle` (see `actionAccessibilityIdentifier` below). Once
    ///   `actionTitle` is localized, that slug changes with the device
    ///   language, silently breaking any UI test that targeted it; pass an
    ///   explicit, language-independent identifier to keep it stable.
    public init(
        title: String,
        subtitle: String,
        bullets: [OnboardingBullet],
        actionTitle: String,
        action: @escaping () -> Void,
        footnote: String? = nil,
        actionAccessibilityIdentifier: String? = nil
    ) {
        self.title = title
        self.subtitle = subtitle
        self.bullets = bullets
        self.actionTitle = actionTitle
        self.action = action
        self.footnote = footnote
        self.explicitActionAccessibilityIdentifier = actionAccessibilityIdentifier
    }

    /// The explicit identifier if the caller supplied one, otherwise slugged
    /// from `actionTitle` as before. The slugged fallback stays only for
    /// callers that never pass an explicit value; it is still text-dependent
    /// and callers that care about a stable identifier across localizations
    /// should pass one.
    private var actionAccessibilityIdentifier: String {
        if let explicitActionAccessibilityIdentifier { return explicitActionAccessibilityIdentifier }
        let slug = actionTitle.lowercased().filter { $0.isLetter || $0.isNumber }
        return "onboarding.action.\(slug)"
    }

    public var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(title)
                            .font(.largeTitle.bold())
                        Text(subtitle)
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 20) {
                        // Keyed by position, not `OnboardingBullet.id`: two bullets
                        // can share a symbol and title (two connected items with
                        // one name), and duplicate ids break `ForEach`.
                        ForEach(Array(bullets.enumerated()), id: \.offset) { _, bullet in
                            bulletRow(bullet)
                        }
                    }

                    if let footnote, !footnote.isEmpty {
                        Text(footnote)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()
            }

            Divider()

            Button(action: action) {
                Text(actionTitle)
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding()
            .accessibilityIdentifier(actionAccessibilityIdentifier)
        }
    }

    private func bulletRow(_ bullet: OnboardingBullet) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: bullet.symbolName)
                .font(.title2)
                .foregroundStyle(.secondary)
                .frame(width: 28)
                .accessibilityHidden(true)   // the title/detail below say it
            VStack(alignment: .leading, spacing: 4) {
                Text(bullet.title)
                    .font(.headline)
                if !bullet.detail.isEmpty {
                    Text(bullet.detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        // One VoiceOver element per row, reading symbol context (via the
        // title/detail text, not a restated label) then title then detail in
        // order, rather than fragmenting into a separate stop per line or
        // silently dropping the detail behind an explicit accessibilityLabel
        // on the row.
        .accessibilityElement(children: .combine)
    }
}
