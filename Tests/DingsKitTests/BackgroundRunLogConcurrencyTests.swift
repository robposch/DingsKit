import Testing
import Foundation
@testable import DingsKit
import DingsKitTestSupport

/// `record` is a read-modify-write of one `UserDefaults` key. Within a process
/// it is serialized, so concurrent callers (the app's foreground refresh and a
/// background task finishing together) never drop each other's entries.
@Suite struct BackgroundRunLogConcurrencyTests {
    @Test func concurrentRecordsInOneProcessAreNotLost() async {
        let log = BackgroundRunLog(defaults: InMemoryUserDefaults())
        let perRound = BackgroundRunLog.maxEntries

        // Several rounds, because a lost update is a timing accident: one
        // round can pass by luck without the lock.
        for round in 0..<25 {
            log.clear()
            await withTaskGroup(of: Void.self) { group in
                for i in 0..<perRound {
                    group.addTask {
                        log.record(source: .appForeground, succeeded: true, detail: "\(round)-\(i)")
                    }
                }
            }
            let details = Set(log.entries().compactMap(\.detail))
            #expect(details.count == perRound, "round \(round) kept \(details.count) of \(perRound)")
        }
    }

    @Test func clearRacingRecordsLeavesAConsistentLog() async {
        let log = BackgroundRunLog(defaults: InMemoryUserDefaults())

        await withTaskGroup(of: Void.self) { group in
            for i in 0..<50 {
                group.addTask {
                    if i.isMultiple(of: 10) {
                        log.clear()
                    } else {
                        log.record(source: .widgetTimeline, succeeded: false, detail: "\(i)")
                    }
                }
            }
        }
        // Whatever interleaving happened, the stored value decodes and
        // respects the cap.
        #expect(log.entries().count <= BackgroundRunLog.maxEntries)
    }
}
