import Testing
import Foundation
@testable import DingsKit
import DingsKitTestSupport

extension GlobalConfig {
    /// `Provider.legacyDisplayNames` is process-global and read from any thread
    /// (widget timeline, background refresh, UI). The public spelling apps use,
    /// `Provider.legacyDisplayNames = [...]`, must keep working, and concurrent
    /// access must be safe.
    @Suite(.serialized) struct LegacyDisplayNamesTests {
        private let legacy = Provider("legacy-display-names.test")

        init() {
            // `displayName` consults the registry first, which needs a config.
            // The provider above is never registered.
            TestDings.bootstrap()
        }

        @Test func assignmentIsReadBackAndFeedsDisplayName() {
            let original = Provider.legacyDisplayNames
            defer { Provider.legacyDisplayNames = original }

            Provider.legacyDisplayNames = [legacy: "Legacy Cloud"]
            #expect(Provider.legacyDisplayNames[legacy] == "Legacy Cloud")
            #expect(legacy.displayName == "Legacy Cloud")

            Provider.legacyDisplayNames[legacy] = nil
            #expect(legacy.displayName == legacy.rawValue)
        }

        @Test func concurrentReadsAndWritesAreSafe() async {
            let original = Provider.legacyDisplayNames
            defer { Provider.legacyDisplayNames = original }
            let legacy = self.legacy

            await withTaskGroup(of: Void.self) { group in
                for i in 0..<200 {
                    group.addTask {
                        if i.isMultiple(of: 2) {
                            Provider.legacyDisplayNames = [legacy: "Name \(i)"]
                        } else {
                            _ = legacy.displayName
                            _ = Provider.legacyDisplayNames.count
                        }
                    }
                }
            }
            let final = Provider.legacyDisplayNames[legacy]
            #expect(final?.hasPrefix("Name ") == true)
        }
    }
}
