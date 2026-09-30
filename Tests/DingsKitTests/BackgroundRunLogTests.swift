import Testing
import Foundation
@testable import DingsKit
import DingsKitTestSupport

/// `BackgroundRunLog` never touches `Dings.config` (it does not log), so this
/// suite stays outside `GlobalConfig` and runs in parallel.
@Suite struct BackgroundRunLogTests {
    private let base = Date(timeIntervalSince1970: 1_700_000_000)

    @Test func emptyByDefault() throws {
        let defaults = InMemoryUserDefaults()
        #expect(BackgroundRunLog(defaults: defaults).entries().isEmpty)
    }

    @Test func recordsAndReturnsNewestFirst() throws {
        let defaults = InMemoryUserDefaults()
        let log = BackgroundRunLog(defaults: defaults)
        log.record(source: .widgetTimeline, succeeded: true, detail: "first", date: base)
        log.record(source: .backgroundTask, succeeded: false, detail: "second", date: base.addingTimeInterval(60))

        let entries = log.entries()
        try #require(entries.count == 2)
        #expect(entries[0].detail == "second")
        #expect(entries[0].source == .backgroundTask)
        #expect(entries[0].succeeded == false)
        #expect(entries[1].detail == "first")
    }

    @Test func capsAtTwentyKeepingMostRecent() throws {
        let defaults = InMemoryUserDefaults()
        let log = BackgroundRunLog(defaults: defaults)
        for i in 1...25 {
            log.record(source: .backgroundTask, succeeded: true, detail: "run-\(i)", date: base.addingTimeInterval(Double(i)))
        }
        let entries = log.entries()
        #expect(entries.count == 20)
        #expect(entries.first?.detail == "run-25")
        #expect(entries.last?.detail == "run-6")
    }

    @Test func persistsAcrossInstances() throws {
        let defaults = InMemoryUserDefaults()
        BackgroundRunLog(defaults: defaults).record(source: .appForeground, succeeded: true, detail: nil, date: base)
        let reread = BackgroundRunLog(defaults: defaults).entries()
        try #require(reread.count == 1)
        #expect(reread[0].source == .appForeground)
    }

    @Test func clearEmpties() throws {
        let defaults = InMemoryUserDefaults()
        let log = BackgroundRunLog(defaults: defaults)
        log.record(source: .backgroundTask, succeeded: true, detail: nil, date: base)
        log.clear()
        #expect(log.entries().isEmpty)
    }
}
