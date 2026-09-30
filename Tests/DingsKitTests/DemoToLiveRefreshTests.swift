import Testing
import Foundation
@testable import DingsKit
import DingsKitTestSupport

extension GlobalConfig {
    /// After the user switches from demo to live, the cache still holds the demo
    /// snapshot until the first live refresh overwrites it. The live refresh must
    /// not treat that snapshot as "previous" data: demo devices, demo rate limits
    /// and demo fetch stamps would otherwise be carried into a snapshot stamped
    /// `isDemo: false`.
    @Suite struct DemoToLiveRefreshTests {
        private let working = Provider("demo-to-live.working")
        private let failing = Provider("demo-to-live.failing")
        private let demoStamp = Date(timeIntervalSince1970: 1_700_000_000)

        init() {
            // The refresher logs, and `Log.subsystem` reads the config.
            TestDings.bootstrap()
        }

        private func device(_ serial: String, _ provider: Provider, readings: [SensorReading]) -> DeviceReadings {
            DeviceReadings(serialNumber: serial, name: serial, model: "M", readings: readings,
                           batteryPercentage: nil, recorded: nil, provider: provider)
        }

        private var reading: SensorReading {
            SensorReading(type: SensorType("co2"), value: 400, unit: "ppm", quality: .good)
        }

        /// Snapshot as demo mode left it: one device per provider, a rate limit,
        /// and per-provider stamps.
        private func demoSnapshot(isDemo: Bool = true) -> CachedReadings {
            CachedReadings(
                devices: [
                    device("shared-serial", working, readings: [reading]),
                    device("demo-only", failing, readings: [reading]),
                ],
                rateLimitRemaining: 42,
                fetchedAt: demoStamp,
                providerFetchedAt: [working: demoStamp, failing: demoStamp],
                isDemo: isDemo)
        }

        private func refresher(cache: PrivateCache) -> ReadingsRefresher {
            let working = self.working
            let freshDevice = device("shared-serial", working, readings: [])
            return ReadingsRefresher(
                connections: ConnectionsStore(
                    stores: [working: PrivateCredentialStore(), failing: PrivateCredentialStore()],
                    order: [working, failing]),
                cache: cache,
                dataModeStore: nil,
                clientOverrides: [
                    // Succeeds, but the device arrives without readings: the case
                    // that triggers the carry-forward of previous readings.
                    working: { _ in PrivateClient(result: .success([freshDevice])) },
                    failing: { _ in PrivateClient(result: .failure(PrivateError())) },
                ])
        }

        @Test func liveRefreshDoesNotCarryDemoDataForward() async throws {
            let cache = PrivateCache(seeded: demoSnapshot())
            try await refresher(cache: cache).refresh()

            let saved = try #require(cache.load())
            #expect(saved.isDemo == false)
            // The failing provider's demo device must not survive keep-on-failure.
            #expect(!saved.devices.contains { $0.serialNumber == "demo-only" })
            // The empty live device must not be backfilled with demo readings.
            let shared = try #require(saved.devices.first { $0.serialNumber == "shared-serial" })
            #expect(shared.readings.isEmpty)
            // Neither the demo rate limit nor the demo fetch stamp carries over.
            #expect(saved.rateLimitRemaining == nil)
            #expect(saved.providerFetchedAt[failing] == nil)
        }

        /// Control: the same refresh over a *live* previous snapshot still keeps
        /// the failing provider's devices and backfills the empty device, so the
        /// fix is scoped to demo snapshots only.
        @Test func liveRefreshStillCarriesLiveDataForward() async throws {
            let cache = PrivateCache(seeded: demoSnapshot(isDemo: false))
            try await refresher(cache: cache).refresh()

            let saved = try #require(cache.load())
            #expect(saved.isDemo == false)
            #expect(saved.devices.contains { $0.serialNumber == "demo-only" })
            let shared = try #require(saved.devices.first { $0.serialNumber == "shared-serial" })
            #expect(shared.readings.count == 1)
            #expect(saved.rateLimitRemaining == 42)
            #expect(saved.providerFetchedAt[failing] == demoStamp)
        }
    }
}

private struct PrivateError: Error {}

private struct PrivateClient: ProviderClient {
    let result: Result<[DeviceReadings], PrivateError>
    func fetchAllReadings() async throws -> [DeviceReadings] { try result.get() }
}

private final class PrivateCache: ReadingsCache, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: CachedReadings?
    init(seeded: CachedReadings?) { stored = seeded }
    func load() -> CachedReadings? { lock.withLock { stored } }
    func save(_ readings: CachedReadings) throws { lock.withLock { stored = readings } }
    func clear() { lock.withLock { stored = nil } }
}

private struct PrivateCredentialStore: ProviderCredentialStore {
    func load() throws -> ProviderCredentials? { ProviderCredentials(fields: ["key": "value"]) }
    func save(_ credentials: ProviderCredentials) throws {}
    func clear() throws {}
}
