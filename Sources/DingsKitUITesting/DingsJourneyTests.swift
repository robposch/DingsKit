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
        // The title exactly: an explanation below it may start with the same words.
        XCTAssertTrue(app.staticTexts[profile.emptyAccountTitle].waitForExistence(timeout: 15),
                      "The empty account has no \"\(profile.emptyAccountTitle)\" title")
    }

    /// Hours-old readings say how old they are.
    public func testStaleReadingsShowTheirAge() throws {
        let profile = try requireProfile()
        let app = launch(DingsLaunch.scenario("stale"))
        XCTAssertTrue(element(beginningWith: profile.demoItemTitle, in: app).waitForExistence(timeout: 15))
        let age = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "3 hours ago")).firstMatch
        XCTAssertTrue(scroll(to: age, in: app), "The readings do not say they are 3 hours old")
    }

    /// With readings cached, a refresh that fails, on opening or by pulling,
    /// keeps them on screen and says so, rather than an error screen.
    public func testAFailedRefreshKeepsTheReadings() throws {
        let profile = try requireProfile()
        var app = launch(DingsLaunch.scenario("live"))
        XCTAssertTrue(element(beginningWith: profile.demoItemTitle, in: app).waitForExistence(timeout: 15))
        app.terminate()

        app = launch(DingsLaunch.scenario("all-failed+keep-cache"))
        XCTAssertTrue(element(beginningWith: profile.demoItemTitle, in: app).waitForExistence(timeout: 15),
                      "Opening the app while every service fails drops the cached readings")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
            .press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85)))
        let notice = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS[c] %@", "couldn’t refresh")).firstMatch
        XCTAssertTrue(notice.waitForExistence(timeout: 15), "A failed refresh does not say so")
        XCTAssertTrue(element(beginningWith: profile.demoItemTitle, in: app).exists, "A failed refresh dropped the readings")
        XCTAssertFalse(element(beginningWith: "Couldn’t load", in: app).exists, "A failed refresh replaced the readings")
    }

    // MARK: Settings

    /// Scrolls `app` until `element` exists, for rows a list has not built yet.
    public func scroll(to element: XCUIElement, in app: XCUIApplication, attempts: Int = 8) -> Bool {
        var tries = 0
        while !element.exists && tries < attempts { app.swipeUp(); tries += 1 }
        return element.exists
    }

    private func openSettings(_ app: XCUIApplication) {
        let button = app.buttons["readings.settings"]
        XCTAssertTrue(button.waitForExistence(timeout: 15), "No Settings button on the readings screen")
        button.tap()
    }

    /// Settings opens from the readings screen; About shows the version and
    /// every legal link.
    public func testSettingsAboutShowsVersionAndLegalLinks() throws {
        let profile = try requireProfile()
        let app = launch(DingsLaunch.demo)
        openSettings(app)
        let version = element(beginningWith: "Version", in: app)
        XCTAssertTrue(scroll(to: version, in: app), "About shows no version")
        for title in profile.legalLinks {
            XCTAssertTrue(scroll(to: element(beginningWith: title, in: app), in: app), "About lacks the link \(title)")
        }
    }

    /// The refresh log opens from Settings and lists the refresh the
    /// readings screen just made.
    public func testRefreshActivityListsTheLatestRefresh() throws {
        _ = try requireProfile()
        let app = launch(DingsLaunch.demo)
        openSettings(app)
        let row = app.buttons["settings.refreshActivity"]
        XCTAssertTrue(scroll(to: row, in: app), "Settings has no refresh activity row")
        row.tap()
        // The screen's title, not its "Clear log" button: that sits below a
        // long list and is not built until scrolled to.
        XCTAssertTrue(app.navigationBars["Refresh activity"].waitForExistence(timeout: 10),
                      "The refresh log did not open")
        XCTAssertTrue(element(beginningWith: "App open", in: app).waitForExistence(timeout: 5),
                      "The refresh log does not list the refresh the app just made")
        XCTAssertFalse(element(beginningWith: "No refreshes recorded yet", in: app).exists)
    }

    /// "Exit demo" leaves demo mode and returns to the first setup screen.
    public func testExitDemoReturnsToSetup() throws {
        let profile = try requireProfile()
        let app = launch(DingsLaunch.demo)
        let exit = app.buttons["readings.exitDemo"]
        XCTAssertTrue(exit.waitForExistence(timeout: 15))
        exit.tap()
        XCTAssertTrue(app.buttons[profile.tryDemoButton].waitForExistence(timeout: 10)
                      || scroll(to: app.buttons[profile.tryDemoButton], in: app),
                      "Exit demo did not return to the first screen")
        XCTAssertFalse(demoBanner(in: app).exists)
    }

    // MARK: Accessibility

    /// Runs iOS's accessibility audit on the screen `app` shows now and
    /// returns what it finds, one line per issue, without failing.
    public func auditIssues(_ app: XCUIApplication, screen: String) -> [String] {
        var found: [String] = []
        do {
            try app.performAccessibilityAudit { issue in
                let element = issue.element.map { "\($0.elementType.rawValue) '\($0.label)' id=\($0.identifier)" } ?? "-"
                found.append("[\(screen)] \(issue.auditType): \(issue.compactDescription) | \(element)")
                return true
            }
        } catch {
            found.append("[\(screen)] audit could not run: \(error)")
        }
        return found
    }

    /// iOS's audit on the main screens: contrast, elements without a
    /// description, tap targets too small, wrong traits. Two kinds of finding
    /// are excused, each for a stated reason:
    /// - the system's own "Done" button in a sheet, which the app does not draw;
    /// - a contrast finding with no element, i.e. decorative graphics;
    /// - "contrast nearly passed", a warning that iOS's own secondary label
    ///   color triggers. "Contrast failed" still fails.
    /// Its text-size checks are left to `testLargerTextGrowsAndStacks`, which
    /// measures instead: on iOS 27 they flag texts that demonstrably grow.
    public func testAccessibilityAuditPasses() throws {
        let profile = try requireProfile()
        var app = launch(DingsLaunch.demo)
        XCTAssertTrue(element(beginningWith: profile.demoItemTitle, in: app).waitForExistence(timeout: 15))
        try audit(app, screen: "readings")
        // An icon button whose words go missing still passes the audit: iOS
        // reads out the symbol's name instead ("Gear shape"). Check the words.
        XCTAssertEqual(app.buttons["readings.settings"].label, "Settings",
                       "VoiceOver does not call the Settings button \"Settings\"")
        openSettings(app)
        sleep(2)
        try audit(app, screen: "settings")
        app.terminate()
        app = launch(DingsLaunch.fresh)
        XCTAssertTrue(app.buttons[profile.tryDemoButton].waitForExistence(timeout: 10)
                      || scroll(to: app.buttons[profile.tryDemoButton], in: app))
        try audit(app, screen: "setup")
        // Again at the bottom, so text that started below the screen's edge
        // is checked where it can be read.
        app.swipeUp()
        app.swipeUp()
        try audit(app, screen: "setup, scrolled down")
    }

    /// The part of the screen between the navigation bar and the bottom
    /// edge's fade, where text is drawn on its own background.
    private func readableArea(of app: XCUIApplication) -> CGRect {
        let screen = app.windows.firstMatch.frame
        let bar = app.navigationBars.firstMatch
        let top = bar.exists ? bar.frame.maxY : screen.minY
        let bottom = screen.maxY - 50
        return CGRect(x: screen.minX, y: top, width: screen.width, height: max(0, bottom - top))
    }

    private func audit(_ app: XCUIApplication, screen: String) throws {
        try app.performAccessibilityAudit(for: [.contrast, .elementDetection, .hitRegion,
                                                .sufficientElementDescription, .trait]) { issue in
            guard let element = issue.element else {
                return issue.auditType == .contrast   // decorative graphics
            }
            // A warning, not a failure: iOS's standard secondary label color
            // (section headers, captions) lands here, as in Apple's own apps.
            if issue.compactDescription.contains("nearly passed") { return true }
            let isSystemDone = element.elementType == .button && element.label == "Done" && element.identifier.isEmpty
            if isSystemDone { return true }
            // Text under the fade iOS draws at the top (behind the navigation
            // bar) and bottom edges has its contrast measured against that
            // fade. Only text in the readable area between them is judged;
            // the rest is checked once it is scrolled into view.
            if issue.auditType == .contrast, !self.readableArea(of: app).contains(element.frame) { return true }
            XCTFail("[\(screen)] \(issue.compactDescription): \(element.label.isEmpty ? element.identifier : element.label)")
            return true
        }
    }

    /// At the largest accessibility text size, text really grows, and a
    /// label and its control stack instead of squeezing side by side.
    public func testLargerTextGrowsAndStacks() throws {
        let profile = try requireProfile()
        func launchAt(_ size: String) -> XCUIApplication {
            launch(DingsLaunch.demo + ["-UIPreferredContentSizeCategoryName", size])
        }
        var app = launchAt("UICTContentSizeCategoryL")
        let normalText = element(beginningWith: profile.growingTextOnReadings, in: app)
        XCTAssertTrue(scroll(to: normalText, in: app), "No \(profile.growingTextOnReadings) on the readings screen")
        let normalHeight = normalText.frame.height
        app.terminate()

        app = launchAt("UICTContentSizeCategoryAccessibilityXXXL")
        let largeText = element(beginningWith: profile.growingTextOnReadings, in: app)
        XCTAssertTrue(scroll(to: largeText, in: app))
        XCTAssertGreaterThan(largeText.frame.height, normalHeight * 1.5,
                             "\(profile.growingTextOnReadings) does not grow with the text size")
        app.terminate()

        app = launchAt("UICTContentSizeCategoryAccessibilityXXXL")
        let banner = app.staticTexts["Demo data"]
        let exit = app.buttons["readings.exitDemo"]
        XCTAssertTrue(exit.waitForExistence(timeout: 15))
        XCTAssertTrue(banner.exists)
        XCTAssertGreaterThan(exit.frame.minY, banner.frame.maxY - 1,
                             "Exit demo should sit below Demo data at the largest text size")
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
        if config.isList {
            editor.openListOptions()
            if let search = config.search { editor.search(search) }
            XCTAssertTrue(editor.offers(config.option, timeout: 5), "The editor does not offer \(config.option)")
            if let notOffered = config.notOffered {
                XCTAssertFalse(editor.offers(notOffered), "The editor must not offer \(notOffered)")
            }
            editor.pick(config.option)
        } else {
            editor.choose(config.field, optionBeginningWith: config.option)
        }
        editor.close()

        for text in config.shows {
            XCTAssertTrue(widget.showing(text).waitForExistence(timeout: 20), "The widget does not show \(text)")
        }

        editor = widget.openEditor(waitingFor: config.field)
        editor.close()
        XCTAssertTrue(widget.showing(config.shows[0]).waitForExistence(timeout: 20))
        XCTAssertFalse(widget.showing(config.unconfiguredText).exists)
    }
}
#endif
