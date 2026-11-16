import Testing
import Foundation
@testable import DingsKit
import DingsKitTestSupport

extension GlobalConfig {
/// `ReadingsRefresher.cachedResult()`: what an app shows at launch, before
/// its first refresh finishes, so a failing first refresh keeps the last
/// readings on screen instead of replacing them with an error.
/// In `GlobalConfig` because the refresher logs through `Dings.config`.
@Suite struct CachedResultTests {
    init() { TestDings.bootstrap() }

    private let provider = Provider("cached-test")
    private let fetched = Date(timeIntervalSince1970: 1_800_000_000)

    private func device(_ serial: String) -> DeviceReadings {
        DeviceReadings(serialNumber: serial, name: "Device \(serial)", model: "Model",
                       readings: [SensorReading(type: SensorType("level"), value: 1, unit: "pct", quality: .good)],
                       batteryPercentage: nil, recorded: fetched, provider: provider)
    }

    private func refresher(cached: CachedReadings?, mode: DataMode) -> ReadingsRefresher {
        let modeStore = DataModeStore(defaults: InMemoryUserDefaults())
        modeStore.save(mode)
        return ReadingsRefresher(connections: ConnectionsStore(stores: [:], order: []),
                                 cache: InMemoryReadingsCache(seeded: cached),
                                 dataModeStore: modeStore, testScenario: nil)
    }

    @Test func liveReadingsShowWhileLive() throws {
        let cached = CachedReadings(devices: [device("a"), device("b")], rateLimitRemaining: 42,
                                    fetchedAt: fetched, providerFetchedAt: [provider: fetched])
        let result = try #require(refresher(cached: cached, mode: .live).cachedResult())
        #expect(result.devices.map(\.serialNumber) == ["a", "b"])
        #expect(result.rateLimitRemaining == 42)
        #expect(result.providerFetchedAt[provider] == fetched)
    }

    /// Older snapshots carry no per-provider stamps; the snapshot's own time
    /// stands in, so the screen still says when the data was synced.
    @Test func aSnapshotWithoutProviderStampsUsesItsOwnTime() throws {
        let cached = CachedReadings(devices: [device("a")], rateLimitRemaining: nil, fetchedAt: fetched)
        let result = try #require(refresher(cached: cached, mode: .live).cachedResult())
        #expect(result.providerFetchedAt[provider] == fetched)
    }

    @Test func demoReadingsDoNotShowWhileLive() {
        let cached = CachedReadings(devices: [device("a")], rateLimitRemaining: nil, fetchedAt: fetched, isDemo: true)
        #expect(refresher(cached: cached, mode: .live).cachedResult() == nil)
    }

    @Test func liveReadingsDoNotShowInDemo() {
        let cached = CachedReadings(devices: [device("a")], rateLimitRemaining: nil, fetchedAt: fetched)
        #expect(refresher(cached: cached, mode: .demo).cachedResult() == nil)
    }

    @Test func nothingCachedShowsNothing() {
        #expect(refresher(cached: nil, mode: .live).cachedResult() == nil)
        let empty = CachedReadings(devices: [], rateLimitRemaining: nil, fetchedAt: fetched)
        #expect(refresher(cached: empty, mode: .live).cachedResult() == nil)
    }
}
}
