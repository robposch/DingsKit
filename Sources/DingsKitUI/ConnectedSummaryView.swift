import SwiftUI
import DingsKit

/// One thing the app just connected: a display name and, if the caller has
/// one, a short secondary detail. DingsKitUI never names what the item *is*
/// (a device, a person, anything else); only these two strings arrive.
public struct ConnectedSummaryItem: Identifiable, Sendable {
    public let id = UUID()
    public let name: String
    public let detail: String?

    public init(name: String, detail: String? = nil) {
        self.name = name
        self.detail = detail
    }
}

/// The onboarding page that names what was just connected, one row per item.
/// It is the first place either app shows the names a widget's picker will
/// later offer, which is what makes that picker discoverable, without this
/// view ever knowing what is being chosen between.
///
/// Title and subtitle are parameters because one app connects devices and
/// the other connects people; `widgetHint` is a parameter because the two
/// apps name their widgets differently.
public struct ConnectedSummaryView: View {
    private let title: String
    private let subtitle: String
    private let items: [ConnectedSummaryItem]
    private let widgetHint: String
    private let actionTitle: String
    private let action: () -> Void
    private let actionAccessibilityIdentifier: String?

    public init(
        title: String,
        subtitle: String,
        items: [ConnectedSummaryItem],
        widgetHint: String,
        actionTitle: String,
        action: @escaping () -> Void,
        actionAccessibilityIdentifier: String? = nil
    ) {
        self.title = title
        self.subtitle = subtitle
        self.items = items
        self.widgetHint = widgetHint
        self.actionTitle = actionTitle
        self.action = action
        self.actionAccessibilityIdentifier = actionAccessibilityIdentifier
    }

    /// Falls back to a single plain row rather than an empty list when
    /// nothing came back connected, so the page never reads as blank or
    /// broken. The fallback names nothing app-specific because DingsKitUI
    /// has no word for what would have been listed here.
    private var bullets: [OnboardingBullet] {
        guard !items.isEmpty else {
            return [
                OnboardingBullet(
                    symbolName: "questionmark.circle",
                    title: coreLocalized("Nothing connected yet"),
                    detail: ""
                )
            ]
        }
        return items.map { item in
            OnboardingBullet(symbolName: "checkmark.circle.fill", title: item.name, detail: item.detail ?? "")
        }
    }

    public var body: some View {
        OnboardingPageView(
            title: title,
            subtitle: subtitle,
            bullets: bullets,
            actionTitle: actionTitle,
            action: action,
            footnote: widgetHint,
            actionAccessibilityIdentifier: actionAccessibilityIdentifier
        )
    }
}
