import Testing
import Foundation
@testable import DingsKit
import DingsKitTestSupport

private let slow = Provider("slow-test")
private let fast = Provider("fast-test")

/// Counts fetches and returns one device, or fails.
private final class CountingClient: ProviderClient, @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    let provider: Provider
    let fails: Bool
    init(_ provider: Provider, fails: Bool = false) {
        self.provider = provider
        self.fails = fails
    }
    var fetches: Int { lock.withLock { count } }
    func fetchAllReadings() async throws -> [DeviceReadings] {
        lock.withLock { count += 1 }
        if fails { throw ProviderAPIError.http(provider, 503) }
        return [device("\(provider.rawValue)-new", provider)]
    }
}

/// Records how often the refresher wrote the snapshot.
private final class CountingCache: ReadingsCache, @unchecked Sendable {
    private let lock = NSLock()
    private var snapshot: CachedReadings?
    private var writes = 0
    init(_ snapshot: CachedReadings?) { self.snapshot = snapshot }
    var saved: CachedReadings? { lock.withLock { snapshot } }
    var saveCount: Int { lock.withLock { writes } }
    func load() -> CachedReadings? { lock.withLock { snapshot } }
    func save(_ readings: CachedReadings) throws { lock.withLock { snapshot = readings; writes += 1 } }
    func clear() { lock.withLock { snapshot = nil } }
}

private struct Fixture {
    let refresher: ReadingsRefresher
    let slowClient: CountingClient
    let fastClient: CountingClient
}

private func device(_ serial: String, _ provider: Provider) -> DeviceReadings {
    DeviceReadings(serialNumber: serial, name: serial, model: "Model", readings: [],
                   batteryPercentage: nil, recorded: nil, provider: provider)
}

extension GlobalConfig {
    /// A provider can declare a longer unattended floor than the app's
    /// `interval` (an API with a per-device daily quota). In `GlobalConfig`
    /// because the floors come from `Dings.config.refresh`.
    @Suite("Per-provider refresh intervals")
    struct ProviderIntervalTests {

        // MARK: - Policy

        @Test func everyProviderUsesTheSharedIntervalByDefault() {
            TestDings.bootstrap()
            #expect(RefreshPolicyValues().providerIntervals.isEmpty)
            #expect(RefreshPolicy.interval(for: slow) == RefreshPolicy.interval)
            #expect(RefreshPolicy.interval(for: fast) == 600)
        }

        @Test func aDeclaredIntervalAppliesToThatProviderOnly() {
            Self.bootstrap(slowInterval: 900)
            #expect(RefreshPolicy.interval(for: slow) == 900)
            #expect(RefreshPolicy.interval(for: fast) == 600)
        }

        /// Unattended runs are already spaced by `interval`; a shorter
        /// per-provider value cannot make a provider poll faster.
        @Test func aDeclaredIntervalNeverUndercutsTheSharedOne() {
            Self.bootstrap(slowInterval: 300)
            #expect(RefreshPolicy.interval(for: slow) == 600)
        }

        // MARK: - Unattended runs

        /// The slow provider fetched 5 minutes ago (floor 15): an unattended
        /// run leaves it out, keeps its devices and stamp, and still fetches
        /// the other provider and writes the snapshot.
        @Test func anUnattendedRunLeavesOutAProviderWithinItsOwnFloor() async throws {
            Self.bootstrap(slowInterval: 900)
            let slowStamp = Date().addingTimeInterval(-300)
            let cache = Self.cache(slowStamp: slowStamp, fastStamp: Date().addingTimeInterval(-700))
            let fixture = try Self.refresher(cache: cache)
            let (refresher, slowClient, fastClient) = (fixture.refresher, fixture.slowClient, fixture.fastClient)
            let before = Date()

            let result = try await refresher.refresh(.unattended)

            #expect(slowClient.fetches == 0)
            #expect(fastClient.fetches == 1)
            #expect(result.devices.map(\.serialNumber) == ["slow-old", "fast-test-new"])
            #expect(result.providerFetchedAt[slow] == slowStamp)
            #expect(try #require(result.providerFetchedAt[fast]) >= before)
            #expect(result.outcomes == [
                ProviderRefreshOutcome(provider: slow, succeeded: true, message: nil, notDue: true),
                ProviderRefreshOutcome(provider: fast, succeeded: true, message: nil),
            ])
            #expect(result.outcomeSummary == "slow-test – · fast-test ✓")
            #expect(cache.saveCount == 1)
            #expect(try #require(cache.saved).providerFetchedAt[slow] == slowStamp)
        }

        @Test func anUnattendedRunFetchesAProviderOnceItsFloorPassed() async throws {
            Self.bootstrap(slowInterval: 900)
            let cache = Self.cache(slowStamp: Date().addingTimeInterval(-901), fastStamp: Date())
            let fixture = try Self.refresher(cache: cache)
            let (refresher, slowClient) = (fixture.refresher, fixture.slowClient)

            _ = try await refresher.refresh(.unattended)

            #expect(slowClient.fetches == 1)
        }

        /// Never fetched, or only a snapshot without per-provider stamps:
        /// nothing says it is fresh, so it is due.
        @Test func aProviderWithoutAFetchStampIsDue() async throws {
            Self.bootstrap(slowInterval: 900)
            let cache = Self.cache(slowStamp: nil, fastStamp: Date())
            let fixture = try Self.refresher(cache: cache)
            let (refresher, slowClient) = (fixture.refresher, fixture.slowClient)

            _ = try await refresher.refresh(.unattended)

            #expect(slowClient.fetches == 1)
        }

        /// A stamp in the future (the clock ran ahead, then was corrected)
        /// must not hold the provider back until the clock catches up.
        @Test func aFetchStampInTheFutureIsDue() async throws {
            Self.bootstrap(slowInterval: 900)
            let cache = Self.cache(slowStamp: Date().addingTimeInterval(3_600), fastStamp: Date())
            let fixture = try Self.refresher(cache: cache)
            let (refresher, slowClient) = (fixture.refresher, fixture.slowClient)

            _ = try await refresher.refresh(.unattended)

            #expect(slowClient.fetches == 1)
        }

        /// Only the slow provider is connected and it is within its floor:
        /// nothing is fetched, the cache is not rewritten (its fetch time must
        /// not move), and the cached readings come back.
        @Test func whenEveryProviderSitsOutNothingIsFetchedOrWritten() async throws {
            Self.bootstrap(slowInterval: 900)
            let slowStamp = Date().addingTimeInterval(-60)
            let cache = Self.cache(slowStamp: slowStamp, fastStamp: nil)
            let fixture = try Self.refresher(cache: cache, configured: [slow])
            let (refresher, slowClient) = (fixture.refresher, fixture.slowClient)

            let result = try await refresher.refresh(.unattended)

            #expect(slowClient.fetches == 0)
            #expect(cache.saveCount == 0)
            #expect(result.devices.map(\.serialNumber) == ["slow-old"])
            #expect(result.providerFetchedAt[slow] == slowStamp)
            #expect(result.outcomeSummary == "slow-test –")
        }

        /// The other provider fails while the slow one sits out: nothing was
        /// fetched, so the run fails as before and leaves the cache alone.
        @Test func aFailureWithEveryOtherProviderSittingOutStillThrows() async throws {
            Self.bootstrap(slowInterval: 900)
            let cache = Self.cache(slowStamp: Date().addingTimeInterval(-60), fastStamp: Date().addingTimeInterval(-700))
            let refresher = try Self.refresher(cache: cache, fastFails: true).refresher

            await #expect(throws: ProviderAPIError.self) { try await refresher.refresh(.unattended) }
            #expect(cache.saveCount == 0)
        }

        // MARK: - Unchanged behaviour

        /// Opening the app, pull-to-refresh and the widget button fetch every
        /// provider, whatever its floor.
        @Test func anOnDemandRefreshIgnoresTheProviderFloor() async throws {
            Self.bootstrap(slowInterval: 900)
            let cache = Self.cache(slowStamp: Date().addingTimeInterval(-60), fastStamp: Date())
            let fixture = try Self.refresher(cache: cache)
            let (refresher, slowClient, fastClient) = (fixture.refresher, fixture.slowClient, fixture.fastClient)

            _ = try await refresher.refresh()

            #expect(slowClient.fetches == 1)
            #expect(fastClient.fetches == 1)
        }

        /// Without declared floors an unattended run is today's refresh:
        /// every provider is fetched, however recently it was.
        @Test func withoutDeclaredFloorsAnUnattendedRunFetchesEveryProvider() async throws {
            TestDings.bootstrap()
            let cache = Self.cache(slowStamp: Date().addingTimeInterval(-60), fastStamp: Date().addingTimeInterval(-60))
            let fixture = try Self.refresher(cache: cache)
            let (refresher, slowClient, fastClient) = (fixture.refresher, fixture.slowClient, fixture.fastClient)

            let result = try await refresher.refresh(.unattended)

            #expect(slowClient.fetches == 1)
            #expect(fastClient.fetches == 1)
            #expect(result.outcomes.allSatisfy { !$0.notDue })
            #expect(cache.saveCount == 1)
        }

        // MARK: - Helpers

        private static func bootstrap(slowInterval: TimeInterval) {
            var refresh = RefreshPolicyValues()
            refresh.providerIntervals = [slow: slowInterval]
            TestDings.bootstrap(refresh: refresh)
        }

        private static func cache(slowStamp: Date?, fastStamp: Date?) -> CountingCache {
            var stamps: [Provider: Date] = [:]
            stamps[slow] = slowStamp
            stamps[fast] = fastStamp
            return CountingCache(CachedReadings(
                devices: [device("slow-old", slow), device("fast-old", fast)],
                rateLimitRemaining: nil,
                fetchedAt: [slowStamp, fastStamp].compactMap { $0 }.max() ?? Date(timeIntervalSince1970: 0),
                providerFetchedAt: stamps))
        }

        private static func refresher(
            cache: CountingCache,
            configured: [Provider] = [slow, fast],
            fastFails: Bool = false
        ) throws -> Fixture {
            let slowClient = CountingClient(slow)
            let fastClient = CountingClient(fast, fails: fastFails)
            var stores: [Provider: any ProviderCredentialStore] = [:]
            for provider in configured {
                let store = InMemoryProviderCredentialStore()
                try store.save(ProviderCredentials(fields: ["token": "t"]))
                stores[provider] = store
            }
            let refresher = ReadingsRefresher(
                connections: ConnectionsStore(stores: stores, order: configured),
                cache: cache,
                dataModeStore: nil,
                clientOverrides: [slow: { _ in slowClient }, fast: { _ in fastClient }],
                testScenario: nil)
            return Fixture(refresher: refresher, slowClient: slowClient, fastClient: fastClient)
        }
    }
}
