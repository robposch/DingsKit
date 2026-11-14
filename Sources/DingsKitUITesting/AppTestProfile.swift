#if os(iOS)
import Foundation

/// What the shared journeys (`DingsJourneyTests`) need to know about an app.
/// Values come from the app's demo data and its own wording. Leave an
/// optional `nil` where the app has no such thing; journeys that need it are
/// then skipped.
public struct AppTestProfile: Sendable {
    /// The app's name on the Home Screen: icon label, widget gallery entry,
    /// placed widgets.
    public var appName: String

    // MARK: Onboarding

    /// The "Try a demo" button on the first screen.
    public var tryDemoButton: String
    /// Steps to reach `tryDemoButton` from launch, for apps with a welcome
    /// page before it (tap these button identifiers in order).
    public var stepsToTryDemo: [String] = []

    // MARK: Readings

    /// A title the readings screen shows for a demo item.
    public var demoItemTitle: String
    /// What the readings screen says for an account without items.
    public var emptyAccountTitle: String
    /// For apps with several providers: the provider the `partial-failure`
    /// scenario fails (the first in demo order), as the app names it, an
    /// item of that provider, and an item of another provider.
    public var partialFailure: PartialFailure?

    public struct PartialFailure: Sendable {
        public var providerName: String
        public var failedItemTitle: String
        public var otherItemPrefix: String

        public init(providerName: String, failedItemTitle: String, otherItemPrefix: String) {
            self.providerName = providerName
            self.failedItemTitle = failedItemTitle
            self.otherItemPrefix = otherItemPrefix
        }
    }

    // MARK: Widgets

    /// The Home Screen widget's editor and what it offers with demo data.
    public var widget: WidgetProfile?

    public struct WidgetProfile: Sendable {
        /// The editor's field title.
        public var field: String
        /// What an unconfigured widget says.
        public var unconfiguredText: String
        /// A search term that finds `option` in a long list of options.
        public var search: String
        /// An option to pick, as the editor lists it.
        public var option: String
        /// What the widget shows once `option` is picked.
        public var shows: [String]
        /// An option the editor must not offer.
        public var notOffered: String?

        public init(field: String, unconfiguredText: String, search: String, option: String,
                    shows: [String], notOffered: String? = nil) {
            self.field = field
            self.unconfiguredText = unconfiguredText
            self.search = search
            self.option = option
            self.shows = shows
            self.notOffered = notOffered
        }
    }

    public init(appName: String, tryDemoButton: String, stepsToTryDemo: [String] = [],
                demoItemTitle: String, emptyAccountTitle: String,
                partialFailure: PartialFailure? = nil, widget: WidgetProfile? = nil) {
        self.appName = appName
        self.tryDemoButton = tryDemoButton
        self.stepsToTryDemo = stepsToTryDemo
        self.demoItemTitle = demoItemTitle
        self.emptyAccountTitle = emptyAccountTitle
        self.partialFailure = partialFailure
        self.widget = widget
    }
}

/// Launch arguments shared by the Dings apps' UI-test hooks.
public enum DingsLaunch {
    /// Start in demo mode on the readings screen.
    public static let demo = ["--uitest-demo"]
    /// Start with nothing connected, on the setup screen.
    public static let fresh = ["--uitest-fresh"]
    /// Serve a `TestScenario` as live data.
    public static func scenario(_ spec: String) -> [String] { ["--uitest-scenario", spec] }
}
#endif
