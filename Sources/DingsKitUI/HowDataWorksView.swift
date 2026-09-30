import Foundation
import SwiftUI
import DingsKit

/// The onboarding page that turns three things users otherwise experience as
/// bugs into stated consequences of the client-side-only architecture: no
/// server means no push, so iOS decides the refresh cadence, and "Measured"
/// and "Synced" can legitimately disagree. This is the one DingsKitUI view
/// allowed shared vocabulary: the explainer copy below is the point of the
/// page, so `serviceName` is the only word either app injects.
///
/// The copy below routes through `coreLocalized` (DingsKit's own
/// `Bundle.module` lookup, made `public` for this) rather than bare string
/// literals: `Text(_:)`'s verbatim `StringProtocol` overload never resolves
/// against any catalog, so an unwrapped literal here would render in English
/// on every device regardless of system language.
public struct HowDataWorksView: View {
    private let serviceName: String
    private let actionTitle: String
    private let action: () -> Void
    private let actionAccessibilityIdentifier: String?

    public init(
        serviceName: String,
        actionTitle: String,
        action: @escaping () -> Void,
        actionAccessibilityIdentifier: String? = nil
    ) {
        self.serviceName = serviceName
        self.actionTitle = actionTitle
        self.action = action
        self.actionAccessibilityIdentifier = actionAccessibilityIdentifier
    }

    public var body: some View {
        OnboardingPageView(
            title: coreLocalized("How your data works"),
            subtitle: coreLocalized("A few things worth knowing before your first widget."),
            bullets: [
                OnboardingBullet(
                    symbolName: "iphone",
                    title: coreLocalized("Everything stays on your device"),
                    // Looks up the literal "%@" pattern and substitutes
                    // `serviceName` afterwards, so the catalog key is exactly
                    // the string written here.
                    detail: String(
                        format: coreLocalized("The app talks to %@ directly, using your own credentials. Nothing passes through a server we control."),
                        serviceName)
                ),
                OnboardingBullet(
                    symbolName: "clock.arrow.circlepath",
                    title: coreLocalized("iOS decides when to refresh"),
                    detail: coreLocalized("There is no server pushing updates, so iOS wakes the app only a few times a day. That is why a widget can show an older reading, and every widget has a refresh button you can tap.")
                ),
                OnboardingBullet(
                    symbolName: "calendar.badge.clock",
                    title: coreLocalized("Two times, two meanings"),
                    detail: coreLocalized("\"Measured\" is when the sensor took the reading, and \"Synced\" is when the app last fetched it. They differ on purpose.")
                )
            ],
            actionTitle: actionTitle,
            action: action,
            actionAccessibilityIdentifier: actionAccessibilityIdentifier
        )
    }
}
