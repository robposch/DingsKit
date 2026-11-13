import Testing
import Foundation
@testable import DingsKit
import DingsKitTestSupport

private let first = Provider("first-scenario-test")
private let second = Provider("second-scenario-test")
private let level = SensorType("level")
private let recordedAt = Date(timeIntervalSince1970: 1_800_000_000)

private struct Canned: ProviderClient {
    let devices: [DeviceReadings]
    func fetchAllReadings() async throws -> [DeviceReadings] { devices }
}

private struct Broken: ProviderClient {
    struct Failure: Error {}
    func fetchAllReadings() async throws -> [DeviceReadings] { throw Failure() }
}

private func device(_ serial: String, _ provider: Provider) -> DeviceReadings {
    DeviceReadings(
        serialNumber: serial, name: "Device \(serial)", model: "Model",
        readings: [SensorReading(type: level, value: 1, unit: "pct", quality: .good)],
        batteryPercentage: nil, recorded: recordedAt, provider: provider)
}

/// Two providers with demo data, as an app with two bespoke demo clients.
private let demoSources: [(Provider, @Sendable () throws -> any ProviderClient)] = [
    (first, { Canned(devices: [device("f1", first), device("f2", first)]) }),
    (second, { Canned(devices: [device("s1", second)]) }),
]

private func refresher(
    _ scenario: TestScenario?, cache: InMemoryReadingsCache = InMemoryReadingsCache(),
    demo: [(Provider, @Sendable () throws -> any ProviderClient)] = demoSources
) -> ReadingsRefresher {
    ReadingsRefresher(
        connections: ConnectionsStore(stores: [:], order: []),
        cache: cache,
        dataModeStore: nil,
        demoClients: demo,
        testScenario: scenario)
}

extension GlobalConfig {
    @Suite("Test scenarios")
    struct TestScenarioTests {
        init() { TestDings.bootstrap() }

        // MARK: Parsing

        @Test func parsesEachPreset() {
            #expect(TestScenario(spec: "partial-failure") == TestScenario(failure: .first))
            #expect(TestScenario(spec: "partial-failure:netatmo") == TestScenario(failure: .providers(["netatmo"])))
            #expect(TestScenario(spec: "all-failed") == TestScenario(failure: .all))
            #expect(TestScenario(spec: "empty") == TestScenario(isEmpty: true))
            #expect(TestScenario(spec: "stale") == TestScenario(age: 3 * 3600))
            #expect(TestScenario(spec: "stale:45") == TestScenario(age: 45 * 60))
            #expect(TestScenario(spec: "item-removed:abc") == TestScenario(removedItems: ["abc"]))
            #expect(TestScenario(spec: "live") == TestScenario())
        }

        @Test func combinesPresetsWithPlus() {
            #expect(TestScenario(spec: "partial-failure+stale:10")
                    == TestScenario(failure: .first, age: 600))
        }

        @Test func rejectsUnknownSpecs() {
            #expect(TestScenario(spec: "nonsense") == nil)
            #expect(TestScenario(spec: "stale:soon") == nil)
            #expect(TestScenario(spec: "") == nil)
        }

        // MARK: Refresh

        /// Looks live: no demo flag, so no demo banner, and real outcomes.
        @Test func liveScenarioServesDemoDataAsLiveWithOutcomes() async throws {
            let cache = InMemoryReadingsCache()
            let result = try await refresher(TestScenario(), cache: cache).refresh()

            #expect(result.devices.map(\.serialNumber) == ["f1", "f2", "s1"])
            #expect(!result.outcomes.contains { !$0.succeeded })
            #expect(result.outcomes.map(\.provider) == [first, second])
            #expect(cache.saved?.isDemo == false)
        }

        @Test func partialFailureFailsTheFirstProviderOnly() async throws {
            let result = try await refresher(TestScenario(failure: .first)).refresh()

            #expect(result.devices.map(\.serialNumber) == ["s1"])
            #expect(result.outcomes.map(\.succeeded) == [false, true])
            #expect(result.outcomes[0].message?.contains("503") == true)
        }

        /// A provider that fails keeps what the cache had, as in live mode.
        @Test func failedProviderKeepsItsCachedDevices() async throws {
            let cache = InMemoryReadingsCache()
            _ = try await refresher(TestScenario(), cache: cache).refresh()
            let result = try await refresher(TestScenario(failure: .providers([first.rawValue])), cache: cache).refresh()

            #expect(result.devices.map(\.serialNumber) == ["f1", "f2", "s1"])
            #expect(result.outcomes.map(\.succeeded) == [false, true])
        }

        @Test func allFailedThrowsAndLeavesTheCacheAlone() async throws {
            let cache = InMemoryReadingsCache()
            _ = try await refresher(TestScenario(), cache: cache).refresh()
            let before = cache.saved

            await #expect(throws: (any Error).self) {
                try await refresher(TestScenario(failure: .all), cache: cache).refresh()
            }
            #expect(cache.saved == before)
        }

        @Test func emptyAccountReturnsNoDevices() async throws {
            let result = try await refresher(TestScenario(isEmpty: true)).refresh()
            #expect(result.devices.isEmpty)
            #expect(!result.outcomes.contains { !$0.succeeded })
        }

        @Test func staleShiftsReadingsAndSyncStampsIntoThePast() async throws {
            let cache = InMemoryReadingsCache()
            let before = Date()
            let result = try await refresher(TestScenario(age: 3600), cache: cache).refresh()

            #expect(!result.devices.contains { $0.recorded != recordedAt.addingTimeInterval(-3600) })
            let stamp = try #require(result.providerFetchedAt[first])
            #expect(stamp <= before.addingTimeInterval(-3600 + 1))
            let snapshotStamp = try #require(cache.saved?.fetchedAt)
            #expect(snapshotStamp <= before.addingTimeInterval(-3600 + 1))
        }

        @Test func removedItemIsGone() async throws {
            let result = try await refresher(TestScenario(removedItems: ["f2"])).refresh()
            #expect(result.devices.map(\.serialNumber) == ["f1", "s1"])
        }

        /// A demo fixture that cannot load is not a scenario failure: that
        /// provider simply takes no part.
        @Test func brokenDemoFixtureIsSkipped() async throws {
            let demo: [(Provider, @Sendable () throws -> any ProviderClient)] = [
                (first, { Broken() }), (second, { Canned(devices: [device("s1", second)]) }),
            ]
            let result = try await refresher(TestScenario(), demo: demo).refresh()
            #expect(result.outcomes.map(\.provider) == [second])
            #expect(result.devices.map(\.serialNumber) == ["s1"])
        }

        // MARK: Store

        @Test func storeRoundTripsAndActivationFollowsTheLaunchArguments() {
            let store = TestScenarioStore(defaults: InMemoryUserDefaults())
            store.activate(arguments: ["app", "--uitest-scenario", "partial-failure+stale"])
            #expect(store.load() == TestScenario(failure: .first, age: 3 * 3600))

            // A launch without the argument clears it, so a scenario never
            // outlives the test run that set it.
            store.activate(arguments: ["app"])
            #expect(store.load() == nil)
        }

        /// Each test starts from nothing, so readings a previous test cached
        /// cannot leak into the next.
        @Test func activatingAScenarioEmptiesTheReadingsCache() {
            let store = TestScenarioStore(defaults: InMemoryUserDefaults())
            let cache = InMemoryReadingsCache(seeded: CachedReadings(
                devices: [device("old", first)], rateLimitRemaining: nil, fetchedAt: recordedAt))
            store.activate(arguments: ["app", "--uitest-scenario", "live"], cache: cache)
            #expect(cache.saved == nil)
        }

        /// For a test that checks what a failure keeps from an earlier run.
        @Test func keepCacheLeavesTheReadingsCacheAlone() {
            let store = TestScenarioStore(defaults: InMemoryUserDefaults())
            let seeded = CachedReadings(devices: [device("old", first)], rateLimitRemaining: nil, fetchedAt: recordedAt)
            let cache = InMemoryReadingsCache(seeded: seeded)
            store.activate(arguments: ["app", "--uitest-scenario", "partial-failure+keep-cache"], cache: cache)
            #expect(cache.saved == seeded)
            #expect(store.load() == TestScenario(failure: .first, keepsCache: true))
        }

        @Test func launchWithoutAScenarioLeavesTheReadingsCacheAlone() {
            let store = TestScenarioStore(defaults: InMemoryUserDefaults())
            let seeded = CachedReadings(devices: [device("old", first)], rateLimitRemaining: nil, fetchedAt: recordedAt)
            let cache = InMemoryReadingsCache(seeded: seeded)
            store.activate(arguments: ["app"], cache: cache)
            #expect(cache.saved == seeded)
        }

        @Test func unknownSpecOnTheCommandLineActivatesNothing() {
            let store = TestScenarioStore(defaults: InMemoryUserDefaults())
            store.activate(arguments: ["app", "--uitest-scenario", "nonsense"])
            #expect(store.load() == nil)
        }
    }
}
