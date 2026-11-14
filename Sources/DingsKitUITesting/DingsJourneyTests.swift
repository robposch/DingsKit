#if os(iOS)
import XCTest

/// The journeys every Dings app shares, run against the app's own build.
/// An app subclasses this in its UI test target and overrides `profile`; the
/// inherited tests then run for that app:
///
/// ```swift
/// final class MyAppJourneyTests: DingsJourneyTests {
///     override class var profile: AppTestProfile? { AppTestProfile(...) }
/// }
/// ```
///
/// The base class has no profile and skips every journey, so it does no harm
/// when XCTest finds it too.
@MainActor
open class DingsJourneyTests: XCTestCase {
    /// The app under test. `nil` in the base class.
    open class var profile: AppTestProfile? { nil }

    /// The profile, or a skip when there is none (the base class itself).
    public func requireProfile() throws -> AppTestProfile {
        guard let profile = Self.profile else { throw XCTSkip("Shared journeys run in an app's subclass") }
        return profile
    }

    override open func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    public func launch(_ arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += arguments
        app.launch()
        return app
    }

    /// The demo banner, whatever element type the app's list makes of it.
    public func demoBanner(in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)["readings.demoBanner"]
    }

    /// Any element whose label begins with `text`.
    public func element(beginningWith text: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", text)).firstMatch
    }

    // MARK: Onboarding

    /// "Try a demo" walks through "how the data works" and "you're
    /// connected" and lands on the readings screen with the demo banner.
    public func testTryADemoLandsOnDemoReadings() throws {
        let profile = try requireProfile()
        let app = launch(DingsLaunch.fresh)
        for step in profile.stepsToTryDemo {
            let button = app.buttons[step]
            XCTAssertTrue(button.waitForExistence(timeout: 10), "Missing step \(step)")
            button.tap()
        }
        let tryDemo = app.buttons[profile.tryDemoButton]
        // Form rows enter the accessibility tree only once scrolled into view.
        var scrolls = 0
        while !tryDemo.waitForExistence(timeout: 2) && scrolls < 6 { app.swipeUp(); scrolls += 1 }
        tryDemo.tap()

        let continueButton = app.buttons["onboarding.action.continue"]
        XCTAssertTrue(continueButton.waitForExistence(timeout: 15))
        continueButton.tap()
        let getStarted = app.buttons["onboarding.action.getstarted"]
        XCTAssertTrue(getStarted.waitForExistence(timeout: 10))
        getStarted.tap()

        XCTAssertTrue(demoBanner(in: app).waitForExistence(timeout: 15))
        XCTAssertTrue(element(beginningWith: profile.demoItemTitle, in: app).waitForExistence(timeout: 10))
    }

    // MARK: Readings under each data situation

    /// A scenario serves its data as live: no demo banner.
    public func testLiveDataLooksConnected() throws {
        let profile = try requireProfile()
        let app = launch(DingsLaunch.scenario("live"))
        XCTAssertTrue(element(beginningWith: profile.demoItemTitle, in: app).waitForExistence(timeout: 15))
        XCTAssertFalse(demoBanner(in: app).exists, "Live data must not show the demo banner")
    }

    public func testOneProviderFailingNamesItAndKeepsTheOthers() throws {
        let profile = try requireProfile()
        guard let failure = profile.partialFailure else { throw XCTSkip("The app has a single provider") }
        let app = launch(DingsLaunch.scenario("partial-failure"))
        XCTAssertTrue(element(beginningWith: "\(failure.providerName): couldn’t refresh", in: app)
                        .waitForExistence(timeout: 15))
        XCTAssertTrue(element(beginningWith: failure.otherItemPrefix, in: app).exists,
                      "The other providers' items should still show")
        XCTAssertFalse(element(beginningWith: failure.failedItemTitle, in: app).exists)
    }

    public func testEveryProviderFailingShowsTheFailureScreen() throws {
        _ = try requireProfile()
        let app = launch(DingsLaunch.scenario("all-failed"))
        XCTAssertTrue(element(beginningWith: "Couldn’t load", in: app).waitForExistence(timeout: 15))
    }

    public func testAnEmptyAccountSaysSo() throws {
        let profile = try requireProfile()
        let app = launch(DingsLaunch.scenario("empty"))
        XCTAssertTrue(element(beginningWith: profile.emptyAccountTitle, in: app).waitForExistence(timeout: 15))
    }

    // MARK: Widgets

    /// A placed widget asks until something is chosen in its editor, then
    /// shows it; opening and closing the editor again changes nothing.
    public func testAPlacedWidgetShowsWhatItsEditorChose() throws {
        let profile = try requireProfile()
        guard let config = profile.widget else { throw XCTSkip("The app has no configurable widget") }
        let home = HomeScreen(appName: profile.appName)
        let app = launch(DingsLaunch.demo)
        XCTAssertTrue(element(beginningWith: profile.demoItemTitle, in: app).waitForExistence(timeout: 15))
        XCUIDevice.shared.press(.home)
        home.removeLeftoverWidgets()

        let widget = home.addWidget()
        defer { widget.remove() }
        XCTAssertTrue(widget.text(config.unconfiguredText).waitForExistence(timeout: 15))

        var editor = widget.openEditor(waitingFor: config.field)
        editor.openListOptions()
        editor.search(config.search)
        XCTAssertTrue(editor.offers(config.option, timeout: 5), "The editor does not offer \(config.option)")
        if let notOffered = config.notOffered {
            XCTAssertFalse(editor.offers(notOffered), "The editor must not offer \(notOffered)")
        }
        editor.pick(config.option)
        editor.close()

        for text in config.shows {
            XCTAssertTrue(widget.text(text).waitForExistence(timeout: 20), "The widget does not show \(text)")
        }

        editor = widget.openEditor(waitingFor: config.field)
        editor.close()
        XCTAssertTrue(widget.text(config.shows[0]).waitForExistence(timeout: 20))
        XCTAssertFalse(widget.text(config.unconfiguredText).exists)
    }
}
#endif
