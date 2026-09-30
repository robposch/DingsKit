import Testing
import Foundation
@testable import DingsKit
import DingsKitTestSupport

extension GlobalConfig {
    /// In `GlobalConfig` because `DataModeStore.save` logs, and `Log` reads
    /// `Dings.config`.
    @Suite struct DataModeStoreTests {
        init() { TestDings.bootstrap() }

        @Test func defaultsToLive() throws {
            let defaults = InMemoryUserDefaults()
            #expect(DataModeStore(defaults: defaults).load() == .live)
        }

        @Test func savesAndLoadsDemo() throws {
            let defaults = InMemoryUserDefaults()
            let store = DataModeStore(defaults: defaults)
            store.save(.demo)
            #expect(store.load() == .demo)
        }

        /// Saving `.live` must overwrite an earlier `.demo`. A user who taps
        /// "Try a demo", backs out, and then connects real credentials ends up
        /// with exactly this sequence; if the stale `.demo` survived, the
        /// refresher would keep serving demo fixtures after a real connect.
        @Test func liveOverwritesALeftoverDemoFlag() throws {
            let defaults = InMemoryUserDefaults()
            let store = DataModeStore(defaults: defaults)
            store.save(.demo)
            #expect(store.load() == .demo)
            store.save(.live)
            #expect(store.load() == .live)
        }

        @Test func demoOverwritesALeftoverLiveFlag() throws {
            let defaults = InMemoryUserDefaults()
            let store = DataModeStore(defaults: defaults)
            store.save(.live)
            store.save(.demo)
            #expect(store.load() == .demo)
        }

        /// An unrecognised stored value (e.g. written by a newer app version)
        /// reads as `.live`, never as demo data.
        @Test func unknownStoredValueReadsAsLive() throws {
            let defaults = InMemoryUserDefaults()
            defaults.set("holiday", forKey: "dataMode")
            #expect(DataModeStore(defaults: defaults).load() == .live)
        }
    }
}
