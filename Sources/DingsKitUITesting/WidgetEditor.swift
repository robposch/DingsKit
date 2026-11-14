#if os(iOS)
import XCTest

/// iOS's editor for a placed widget, opened with
/// `PlacedWidget.openEditor(waitingFor:)`.
@MainActor
public struct WidgetEditor {
    let springboard: XCUIApplication
    /// The field title the editor was recognised by; gone once it closes.
    let fieldTitle: XCUIElement

    /// Whether the editor shows a list field ("Add New Item"), such as a
    /// multi-select of sensors.
    public var showsListField: Bool {
        addItemButton.exists
    }

    /// Picks an option for a single-value field. The field's button shows its
    /// title while empty and the chosen value afterwards, so it is found
    /// through the row that carries the title.
    public func choose(_ fieldTitle: String, optionBeginningWith option: String,
                       file: StaticString = #filePath, line: UInt = #line) {
        let row = springboard.cells.containing(NSPredicate(format: "label == %@", fieldTitle)).firstMatch
        tapWhenPresent(row.buttons.firstMatch, file: file, line: line)
        tapWhenPresent(springboard.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", option)).firstMatch,
                       file: file, line: line)
    }

    /// Opens the list field's options. Check them with `offers(_:)`, then
    /// `pick(_:)` one.
    public func openListOptions(file: StaticString = #filePath, line: UInt = #line) {
        tapWhenPresent(addItemButton, file: file, line: line)
    }

    /// Types into the options' search field. iOS only builds the rows on
    /// screen, so an option far down a long list must be searched for.
    public func search(_ text: String, file: StaticString = #filePath, line: UInt = #line) {
        let field = springboard.searchFields.firstMatch
        tapWhenPresent(field, file: file, line: line)
        field.typeText(text)
    }

    /// Whether the open list of options contains this one.
    public func offers(_ option: String, timeout: TimeInterval = 0) -> Bool {
        let text = optionText(option)
        return timeout > 0 ? text.waitForExistence(timeout: timeout) : text.exists
    }

    public func pick(_ option: String, file: StaticString = #filePath, line: UInt = #line) {
        tapWhenPresent(optionText(option), file: file, line: line)
    }

    /// Closes the editor by tapping outside it, and checks it closed: a tap
    /// while the sheet is still animating in is ignored, so it is repeated.
    public func close(file: StaticString = #filePath, line: UInt = #line) {
        for _ in 0..<3 {
            springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95)).tap()
            let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: fieldTitle)
            if XCTWaiter.wait(for: [gone], timeout: 3) == .completed { return }
        }
        XCTFail("The widget editor did not close", file: file, line: line)
    }

    private var addItemButton: XCUIElement {
        springboard.buttons["editor.list.add-item"]
    }

    private func optionText(_ option: String) -> XCUIElement {
        springboard.staticTexts.matching(NSPredicate(format: "label == %@", option)).firstMatch
    }
}
#endif
