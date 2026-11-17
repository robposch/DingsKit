#if os(iOS)
import Testing
import SwiftUI
@testable import DingsKit
import DingsKitUI
import DingsKitTestSupport

/// Reference images of the screens every Dings app shares. A change to one
/// of them shows up here as a failing comparison with the image to look at.
@MainActor
@Suite struct SharedScreenSnapshotTests {
    init() {
        TestDings.bootstrap(disclosure: DisclosureContent(
            disclaimer: "Unofficial app. Connects to Example Cloud using your own API credentials. Not affiliated with Example.",
            severity: .info))
    }

    @Test func howYourDataWorks() {
        Snapshot.assert(HowDataWorksView(serviceName: "Example Cloud", actionTitle: "Continue", action: {}),
                        named: "how-data-works", height: 874)
    }

    @Test func youAreConnected() {
        Snapshot.assert(ConnectedSummaryView(
            title: "You're connected", subtitle: "Here's what's reporting readings now.",
            items: [ConnectedSummaryItem(name: "Living Room", detail: "Monitor · Example"),
                    ConnectedSummaryItem(name: "Garden", detail: "Station · Example")],
            widgetHint: "Add a widget to your Home Screen to see this without opening the app.",
            actionTitle: "Get started", action: {}), named: "connected-summary", height: 874)
    }

    @Test func disclaimer() {
        Snapshot.assert(DisclaimerBox(style: .prominent).padding(), named: "disclaimer-prominent")
        Snapshot.assert(DisclaimerBox(style: .footer).padding(), named: "disclaimer-footer")
    }

    @Test func refreshErrorBanner() {
        Snapshot.assert(RefreshErrorBanner(message: "Example Cloud returned HTTP 503. Try again later.").padding(),
                        named: "refresh-error-banner")
    }

    @Test func readingsStates() {
        Snapshot.assert(ReadingsStateView(state: .loading, retry: {}), named: "state-loading", height: 400)
        Snapshot.assert(ReadingsStateView(state: .empty(title: "No devices", systemImage: "sensor",
                                                        description: "No devices were found on the connected accounts."),
                                          retry: {}), named: "state-empty", height: 400)
        Snapshot.assert(ReadingsStateView(state: .failed(message: "Example Cloud returned HTTP 503. Try again later."),
                                          retry: {}), named: "state-failed", height: 400)
    }

    @Test func onboardingPage() {
        Snapshot.assert(OnboardingPageView(
            title: "Welcome", subtitle: "Your own sensors, on your Home Screen.",
            bullets: [OnboardingBullet(symbolName: "sensor", title: "Your device", detail: "Readings from your own account."),
                      OnboardingBullet(symbolName: "key", title: "Your key", detail: "Kept in your Keychain.")],
            actionTitle: "Continue", action: {}, footnote: "Not affiliated with any vendor."),
                        named: "onboarding-page", height: 874)
    }

    @Test func widgetPlaceholders() {
        Snapshot.assert(WidgetPlaceholderView(symbolName: "questionmark.circle", title: "Choose readings",
                                              hint: "Touch and hold to edit")
                            .frame(width: 170, height: 170), named: "widget-placeholder")
        Snapshot.assert(AccessoryPlaceholderView(symbolName: "questionmark.circle", title: "Pick")
                            .frame(width: 58, height: 58), named: "accessory-placeholder")
    }
}
#endif
