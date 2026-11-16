#if os(iOS)
import XCTest

/// Drives the iOS Home Screen the way a person does: places an app's widget
/// from the widget gallery, finds and removes placed widgets.
///
/// Works through SpringBoard's accessibility tree, whose labels can change
/// between iOS versions. Written against iOS 27.
@MainActor
public struct HomeScreen {
    public let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
    /// The app's name as SpringBoard shows it: the icon label, the widget
    /// gallery entry and the label of each placed widget.
    public let appName: String

    public init(appName: String) {
        self.appName = appName
    }

    /// Adds the app's first widget size from the gallery and leaves Home
    /// Screen editing.
    @discardableResult
    public func addWidget(file: StaticString = #filePath, line: UInt = #line) -> PlacedWidget {
        enterEditing(file: file, line: line)
        tapWhenPresent(springboard.buttons["Edit"], file: file, line: line)
        tapWhenPresent(springboard.buttons["Add Widget"], file: file, line: line)
        // The gallery lists apps alphabetically and only builds the rows on
        // screen, so search for the app rather than hope it is near the top.
        let search = springboard.searchFields["Search Widgets"]
        tapWhenPresent(search, file: file, line: line)
        search.typeText(appName)
        tapWhenPresent(springboard.cells[appName], file: file, line: line)
        tapWhenPresent(springboard.buttons.matching(NSPredicate(format: "label ENDSWITH 'Add Widget'")).firstMatch,
                       file: file, line: line)
        tapWhenPresent(springboard.buttons["Done"], file: file, line: line)
        let placed = widgetElements.firstMatch
        XCTAssertTrue(placed.waitForExistence(timeout: 10), "The widget was not placed", file: file, line: line)
        guard let widget = placedWidgets().first, let frame = currentFrame(of: widget) else {
            XCTFail("The widget was not placed", file: file, line: line)
            return PlacedWidget(frame: .zero, home: self)
        }
        return PlacedWidget(frame: frame, home: self)
    }

    /// The app's widgets on the visible page. The app icon carries the same
    /// label, so widgets are told apart by size: an icon is about 76pt wide,
    /// the smallest widget about 150pt.
    public func placedWidgets() -> [XCUIElement] {
        widgetElements.allElementsBoundByIndex.filter { element in
            guard let frame = currentFrame(of: element) else { return false }
            return frame.width > 120 && frame.height > 120
        }
    }

    /// The element's frame on screen, or `nil` if it is gone. Reading
    /// `frame` of a vanished element fails the test, as happens while a
    /// removal animates, so a snapshot checks first that it is there. The
    /// snapshot's own frame is not used: for a widget it is relative to its
    /// container, not the screen.
    func currentFrame(of element: XCUIElement) -> CGRect? {
        guard (try? element.snapshot()) != nil else { return nil }
        return element.frame
    }

    /// Removes widgets an earlier, interrupted run left behind, on every
    /// Home Screen page, then shows the app icon's page.
    public func removeLeftoverWidgets() {
        goToFirstPage()
        for _ in 0..<Self.maxPages {
            var attempts = 0
            while let widget = placedWidgets().first, attempts < 10 {
                remove(widget)
                attempts += 1
                sleep(2)
            }
            guard nextPage() else { break }
        }
        showAppPage()
    }

    /// Pages through the Home Screen until the app icon is on screen.
    public func showAppPage() {
        goToFirstPage()
        for _ in 0..<Self.maxPages {
            if visibleIcon != nil { return }
            guard nextPage() else { return }
        }
    }

    private static let maxPages = 8

    private func goToFirstPage() {
        XCUIDevice.shared.press(.home)
        sleep(1)
    }

    /// Swipes to the next Home Screen page. `false` on the last one; the
    /// App Library after it is not a page, so a swipe into it is undone.
    private func nextPage() -> Bool {
        let indicator = springboard.pageIndicators.firstMatch
        let before = indicator.value as? String
        springboard.swipeLeft()
        sleep(1)
        if isShowingAppLibrary {
            springboard.swipeRight()
            sleep(1)
            return false
        }
        return (indicator.value as? String) != before
    }

    private var isShowingAppLibrary: Bool {
        springboard.searchFields["App Library"].exists
    }

    /// The app's icon on the visible Home Screen page. An app can live in the
    /// App Library only, whose icon menu cannot edit the Home Screen.
    private var visibleIcon: XCUIElement? {
        guard !isShowingAppLibrary else { return nil }
        return springboard.icons.matching(identifier: appName).allElementsBoundByIndex.first(where: \.isHittable)
    }

    /// Presses at the widget's position rather than on the element: while a
    /// removal animates, the element can vanish between finding and pressing.
    func remove(_ widget: XCUIElement) {
        guard let frame = currentFrame(of: widget), !frame.isEmpty else { return }
        springboard.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: frame.midX, dy: frame.midY))
            .press(forDuration: 1.5)
        let remove = springboard.buttons["com.apple.springboardhome.application-shortcut-item.remove-widget"]
        guard remove.waitForExistence(timeout: 5) else {
            // Not a widget's menu: close it rather than leave it covering the screen.
            XCUIDevice.shared.press(.home)
            return
        }
        remove.tap()
        let confirm = springboard.buttons.matching(NSPredicate(format: "label == 'Remove'")).firstMatch
        if confirm.waitForExistence(timeout: 5) { confirm.tap() }
    }

    private var widgetElements: XCUIElementQuery {
        springboard.otherElements.matching(NSPredicate(format: "label == %@", appName))
    }

    /// Through the app icon's menu: a long press on an empty spot can land on
    /// a widget and open that widget's menu instead.
    private func enterEditing(file: StaticString, line: UInt) {
        guard !springboard.buttons["Done"].exists else { return }
        // SpringBoard also lists the icon off-screen (App Library, other
        // pages); press the one on the visible page.
        if visibleIcon == nil { showAppPage() }
        if let icon = visibleIcon {
            icon.press(forDuration: 1.5)
            tapWhenPresent(springboard.buttons["com.apple.springboardhome.application-shortcut-item.rearrange-icons"],
                           file: file, line: line)
        } else {
            // The app is in the App Library only. Leftover widgets are gone
            // by now, so an empty spot above the dock is wallpaper.
            springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.72)).press(forDuration: 1.5)
        }
    }
}

/// A widget placed on the Home Screen, identified by where it sits: a
/// query position could point at another widget once the layout shifts.
@MainActor
public struct PlacedWidget {
    let frame: CGRect
    let home: HomeScreen

    /// The widget's element on screen now. Right after returning to the
    /// Home Screen, SpringBoard is still animating and the widget is not yet
    /// where it was placed; this waits up to `settle` seconds for it, rather
    /// than falling back to another element with the app's name (such as
    /// its icon), whose texts a check would then search in vain.
    public var element: XCUIElement { element(settle: 10) }

    func element(settle: TimeInterval) -> XCUIElement {
        let deadline = Date().addingTimeInterval(settle)
        var candidates: [XCUIElement] = []
        repeat {
            candidates = home.springboard.otherElements
                .matching(NSPredicate(format: "label == %@", home.appName)).allElementsBoundByIndex
            let placed = candidates.first { candidate in
                guard let current = home.currentFrame(of: candidate) else { return false }
                return abs(current.midX - frame.midX) < 4 && abs(current.midY - frame.midY) < 4
            }
            if let placed { return placed }
            Thread.sleep(forTimeInterval: 0.5)
        } while Date() < deadline
        return candidates.first ?? home.springboard.otherElements[home.appName]
    }

    /// The app's widget elements. While a widget redraws, iOS keeps the old
    /// rendering in place under a second element of the same name and frame,
    /// so a text check must look in all of them, not in one picked by
    /// position. `removeLeftoverWidgets` leaves only the widget under test.
    private var widgetElements: XCUIElementQuery {
        home.springboard.otherElements.matching(NSPredicate(format: "label == %@", home.appName))
    }

    /// A text the widget shows, as its own text element.
    public func text(_ label: String) -> XCUIElement {
        widgetElements.staticTexts.matching(NSPredicate(format: "label == %@", label)).firstMatch
    }

    /// Any element of the widget whose label contains `text`. Widgets often
    /// combine several texts into one accessibility label ("Sam, 191 mg/dL").
    public func showing(_ text: String) -> XCUIElement {
        widgetElements.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    /// Opens iOS's widget editor and waits until it has loaded the widget's
    /// options, which can take a while.
    ///
    /// - Parameter fieldTitle: a field the editor always shows, used to tell
    ///   that it has loaded.
    @discardableResult
    public func openEditor(waitingFor fieldTitle: String,
                           file: StaticString = #filePath, line: UInt = #line) -> WidgetEditor {
        element.press(forDuration: 1.5)
        tapWhenPresent(home.springboard.buttons["com.apple.springboardhome.application-shortcut-item.configure-widget"],
                       file: file, line: line)
        // Any element: a single-value field's title is a text, a list field's
        // title is a section header.
        let title = home.springboard.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", fieldTitle)).firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 30), "The widget editor did not open", file: file, line: line)
        return WidgetEditor(springboard: home.springboard, fieldTitle: title)
    }

    public func remove() {
        home.remove(element)
    }
}

/// Taps once the element appears, failing the test if it does not.
@MainActor
func tapWhenPresent(_ element: XCUIElement, timeout: TimeInterval = 10,
                    file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertTrue(element.waitForExistence(timeout: timeout),
                  "Missing on screen: \(element.description)", file: file, line: line)
    element.tap()
}
#endif
