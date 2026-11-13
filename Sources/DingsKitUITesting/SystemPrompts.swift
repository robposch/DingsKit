#if os(iOS)
import XCTest

/// Prompts iOS shows over the app under test.
@MainActor
public enum SystemPrompts {
    /// Dismisses "Save Password?" if it appears within `timeout`. iOS offers
    /// it after a form with password-style fields is submitted. Its form
    /// changes between iOS versions: on iOS 27 it is a floating dialog that
    /// ignores an element tap on "Not Now", so this falls back to a
    /// coordinate tap, then to SpringBoard, which owns system dialogs.
    public static func dismissSavePassword(in app: XCUIApplication, timeout: TimeInterval = 5,
                                           file: StaticString = #filePath, line: UInt = #line) {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let notNow = app.buttons["Not Now"]
        guard notNow.waitForExistence(timeout: timeout) else { return }
        let attempts: [() -> Void] = [
            { notNow.tap() },
            { notNow.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap() },
            { if springboard.buttons["Not Now"].exists { springboard.buttons["Not Now"].tap() } },
        ]
        for attempt in attempts {
            attempt()
            // A fresh expectation each time: one can only be waited on once.
            let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: notNow)
            if XCTWaiter.wait(for: [gone], timeout: 3) == .completed { return }
        }
        XCTFail("The Save Password prompt did not go away", file: file, line: line)
    }
}

/// Screenshots kept in the test results, to see what a test saw.
@MainActor
public enum Screenshots {
    public static func attach(_ name: String, to testCase: XCTestCase) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        testCase.add(shot)
    }
}
#endif
