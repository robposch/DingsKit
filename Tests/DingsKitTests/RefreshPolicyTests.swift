import Testing
import Foundation
@testable import DingsKit
import DingsKitTestSupport

extension GlobalConfig {
    /// In `GlobalConfig` because `RefreshPolicy`'s values and defaults come
    /// from `Dings.config.refresh`; each test installs a known policy.
    @Suite struct RefreshPolicyTests {
        private static let interval: TimeInterval = 600
        private static let dedupe: TimeInterval = 30

        init() {
            var refresh = RefreshPolicyValues()
            refresh.interval = Self.interval
            refresh.widgetReloadInterval = 900
            refresh.foregroundDedupe = Self.dedupe
            refresh.staleCueAfter = 3_600
            refresh.deviceStaleCueAfter = 10_800
            Dings._resetForTesting(DingsConfig(
                appGroupSuite: "group.dingskit.tests", keychainService: "dingskit.tests",
                keychainAccessGroup: nil, logSubsystem: "dingskit.tests",
                backgroundTaskID: "dingskit.tests.refresh", refresh: refresh))
        }

        @Test func exposesConfiguredValues() {
            #expect(RefreshPolicy.interval == 600)
            #expect(RefreshPolicy.widgetReloadInterval == 900)
            #expect(RefreshPolicy.foregroundDedupe == 30)
            #expect(RefreshPolicy.staleCueAfter == 3_600)
            #expect(RefreshPolicy.deviceStaleCueAfter == 10_800)
        }

        @Test func neverRefreshedIsAlwaysDue() {
            #expect(RefreshPolicy.shouldRefresh(since: nil))
            #expect(CacheFreshness.isStale(fetchedAt: nil))
        }

        /// The boundary is inclusive: exactly `interval` old is due.
        @Test func dueExactlyAtTheIntervalNotBefore() {
            let clock = FakeClock()
            let lastRefreshed = clock.now()

            clock.current = lastRefreshed.addingTimeInterval(Self.interval - 1)
            #expect(!RefreshPolicy.shouldRefresh(since: lastRefreshed, now: clock.now()))

            clock.current = lastRefreshed.addingTimeInterval(Self.interval)
            #expect(RefreshPolicy.shouldRefresh(since: lastRefreshed, now: clock.now()))
        }

        /// User-initiated refreshes pass the short dedupe window instead of the
        /// unattended poll floor.
        @Test func foregroundDedupeWindowIsMuchShorter() {
            let clock = FakeClock()
            let lastRefreshed = clock.now()
            clock.current = lastRefreshed.addingTimeInterval(Self.dedupe + 1)

            #expect(!RefreshPolicy.shouldRefresh(since: lastRefreshed, now: clock.now()))
            #expect(RefreshPolicy.shouldRefresh(
                since: lastRefreshed, now: clock.now(), minInterval: RefreshPolicy.foregroundDedupe))
        }

        /// A timestamp from the future (clock skew between processes) is fresh,
        /// not due.
        @Test func futureTimestampIsNotStale() {
            let clock = FakeClock()
            let future = clock.now().addingTimeInterval(120)
            #expect(!CacheFreshness.isStale(fetchedAt: future, now: clock.now()))
        }

        @Test func cacheFreshnessDefaultsToThePolicyInterval() {
            let clock = FakeClock()
            let fetched = clock.now().addingTimeInterval(-Self.interval)
            #expect(CacheFreshness.isStale(fetchedAt: fetched, now: clock.now()))
            #expect(!CacheFreshness.isStale(fetchedAt: fetched, now: clock.now(), maxAge: Self.interval + 1))
        }
    }
}
