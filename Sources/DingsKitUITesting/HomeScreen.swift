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
        tapWhenPresent(springboard.cells[appName], file: file, line: line)
        tapWhenPresent(springboard.buttons.matching(NSPredicate(format: "label ENDSWITH 'Add Widget'")).firstMatch,
                       file: file, line: line)
        tapWhenPresent(springboard.buttons["Done"], file: file, line: line)
        let placed = widgetElements.firstMatch
        XCTAssertTrue(placed.waitForExistence(timeout: 10), "The widget was not placed", file: file, line: line)
        guard let widget = placedWidgets().first else {
            XCTFail("The widget was not placed", file: file, line: line)
            return PlacedWidget(element: placed, home: self)
        }
        return PlacedWidget(element: widget, home: self)
    }

    /// The app's widgets on the visible page. The app icon carries the same
    /// label, so widgets are told apart by size: an icon is about 76pt wide,
    /// the smallest widget about 150pt.
    public func placedWidgets() -> [XCUIElement] {
        widgetElements.allElementsBoundByIndex.filter { $0.frame.width > 120 && $0.frame.height > 120 }
    }

    /// Removes widgets an earlier, interrupted run left behind, which would
    /// otherwise be mistaken for this run's.
    public func removeLeftoverWidgets() {
        var attempts = 0
        while let widget = placedWidgets().first, attempts < 10 {
            remove(widget)
            attempts += 1
            sleep(2)
        }
    }

    /// Presses at the widget's position rather than on the element: while a
    /// removal animates, the element can vanish between finding and pressing.
    func remove(_ widget: XCUIElement) {
        guard widget.exists else { return }
        let frame = widget.frame
        guard !frame.isEmpty else { return }
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
        let icons = springboard.icons.matching(identifier: appName)
        XCTAssertTrue(icons.firstMatch.waitForExistence(timeout: 10),
                      "The \(appName) icon is not on the Home Screen", file: file, line: line)
        guard let icon = icons.allElementsBoundByIndex.first(where: \.isHittable) else {
            XCTFail("No visible \(appName) icon on the Home Screen", file: file, line: line)
            return
        }
        icon.press(forDuration: 1.5)
        tapWhenPresent(springboard.buttons["com.apple.springboardhome.application-shortcut-item.rearrange-icons"],
                       file: file, line: line)
    }
}

/// A widget placed on the Home Screen.
@MainActor
public struct PlacedWidget {
    public let element: XCUIElement
    let home: HomeScreen

    /// A text the widget shows.
    public func text(_ label: String) -> XCUIElement {
        element.staticTexts.matching(NSPredicate(format: "label == %@", label)).firstMatch
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
        XCTAssertTrue(home.springboard.staticTexts[fieldTitle].waitForExistence(timeout: 30),
                      "The widget editor did not open", file: file, line: line)
        return WidgetEditor(springboard: home.springboard)
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
