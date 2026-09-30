import Testing
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import DingsKit
import DingsKitTestSupport

// Made-up providers. alpha and beta are registry specs; gamma, delta and
// epsilon exist only as bespoke `demoClients`.
private let alpha = Provider("alpha-test")
private let beta = Provider("beta-test")
private let gamma = Provider("gamma-test")
private let delta = Provider("delta-test")
private let epsilon = Provider("epsilon-test")

private struct DeviceDTO: Decodable {
    let serial: String
    let value: Double
}

/// Registry client for an invented API: `GET https://<provider>.example.test/v1/devices`,
/// body `[{"serial": "...", "value": 1.0}]`.
private struct FixtureClient: ProviderClient {
    let provider: Provider
    let transport: Transport

    func fetchAllReadings() async throws -> [DeviceReadings] {
        let request = URLRequest(url: try makeURL("https://\(provider.rawValue).example.test/v1/devices"))
        let (data, response) = try await transport.send(request)
        guard response.statusCode == 200 else { throw ProviderAPIError.http(provider, response.statusCode) }
        return try JSONDecoder().decode([DeviceDTO].self, from: data).map { makeDevice($0.serial, provider, value: $0.value) }
    }
}

/// Client with a canned outcome, for `demoClients`.
private struct ScriptedClient: ProviderClient, RateLimitReporting {
    let outcome: Result<[DeviceReadings], any Error>
    var rateLimitRemaining: Int?

    func fetchAllReadings() async throws -> [DeviceReadings] { try outcome.get() }
}

private struct ScriptedFailure: Error {}

private func makeDevice(_ serial: String, _ provider: Provider, value: Double) -> DeviceReadings {
    DeviceReadings(
        serialNumber: serial, name: "Device \(serial)", model: "Model",
        readings: [SensorReading(type: SensorType("level"), value: value, unit: "pct", quality: .good)],
        batteryPercentage: nil, recorded: nil, provider: provider)
}

private func makeSpec(_ provider: Provider) -> ProviderSpec {
    ProviderSpec(
        provider: provider, displayName: provider.rawValue, detail: "", isBeta: false, fields: [],
        instructionSteps: [], instructionsURL: "https://example.test", instructionsLinkTitle: "Docs",
        makeClient: { _, transport in FixtureClient(provider: provider, transport: transport) })
}

/// The live transport: demo mode must never reach it.
private func recordingTransport() -> StubTransport {
    StubTransport { _ in (Data(), HTTPURLResponse()) }
}

/// No credentials for anyone: demo mode needs none.
private let noConnections = ConnectionsStore(
    stores: [alpha: InMemoryProviderCredentialStore(), beta: InMemoryProviderCredentialStore()],
    order: [alpha, beta])

/// Demo fixtures for alpha only; beta has no route, so its real client gets a
/// 404 from `MockTransport`.
private let demoTransport = MockTransport(routes: [
    MockTransport.HostRoutes(host: "alpha-test.example.test", routes: [
        MockTransport.Route(match: .suffix("/v1/devices"), body: { #"[{"serial":"demo-a","value":1}]"# }),
    ]),
])

private let demoClients: [(Provider, @Sendable () throws -> any ProviderClient)] = [
    (gamma, { ScriptedClient(outcome: .success([makeDevice("demo-g", gamma, value: 2)]), rateLimitRemaining: 5) }),
    (delta, { ScriptedClient(outcome: .failure(ScriptedFailure())) }),
    (epsilon, { throw ScriptedFailure() }),
]

extension GlobalConfig {
    /// Data-mode handling of `ReadingsRefresher.refresh()`. In `GlobalConfig`
    /// because the demo pipeline walks the registered specs in `Dings.config`.
    @Suite("ReadingsRefresher: demo mode")
    struct ReadingsRefresherDemoTests {
        init() { TestDings.bootstrap(providers: [makeSpec(alpha), makeSpec(beta)]) }

        @Test func servesDemoClientsThenRegistryAgainstDemoTransportFailSoft() async throws {
            let defaults = InMemoryUserDefaults()
            let modeStore = DataModeStore(defaults: defaults)
            modeStore.save(.demo)
            let cache = InMemoryReadingsCache(seeded: CachedReadings(
                devices: [makeDevice("live-a", alpha, value: 9)], rateLimitRemaining: 100,
                fetchedAt: Date(timeIntervalSince1970: 1_700_000_000)))
            let liveTransport = recordingTransport()
            let refresher = ReadingsRefresher(
                connections: noConnections, cache: cache, transport: liveTransport,
                dataModeStore: modeStore, demoClients: demoClients, demoTransport: demoTransport)
            let before = Date()

            let result = try await refresher.refresh()

            // Bespoke demo clients first, then registry specs in spec order.
            // delta and epsilon fail and beta 404s; none of that aborts the run.
            #expect(result.devices == [makeDevice("demo-g", gamma, value: 2), makeDevice("demo-a", alpha, value: 1)])
            #expect(Set(result.providerFetchedAt.keys) == [gamma, alpha])
            #expect(try #require(result.providerFetchedAt[alpha]) >= before)
            #expect(result.rateLimitRemaining == 5)
            #expect(result.outcomes.isEmpty)
            #expect(liveTransport.requestedURLs.isEmpty)

            let saved = try #require(cache.saved)
            #expect(saved.isDemo == true)
            #expect(saved.devices == result.devices)
            #expect(saved.providerFetchedAt == result.providerFetchedAt)
        }

        @Test func demoWithNilCacheReturnsResult() async throws {
            let defaults = InMemoryUserDefaults()
            let modeStore = DataModeStore(defaults: defaults)
            modeStore.save(.demo)
            let refresher = ReadingsRefresher(
                connections: noConnections, cache: nil, transport: recordingTransport(),
                dataModeStore: modeStore, demoClients: demoClients, demoTransport: demoTransport)

            let result = try await refresher.refresh()

            #expect(result.devices.map(\.serialNumber) == ["demo-g", "demo-a"])
        }

        /// An explicit `.live` mode takes the live path: demo clients are
        /// ignored, so with nothing configured the refresh throws.
        @Test func liveDataModeIgnoresDemoClients() async throws {
            let defaults = InMemoryUserDefaults()
            let modeStore = DataModeStore(defaults: defaults)
            modeStore.save(.live)
            let liveTransport = recordingTransport()
            let refresher = ReadingsRefresher(
                connections: noConnections, cache: nil, transport: liveTransport,
                dataModeStore: modeStore, demoClients: demoClients, demoTransport: demoTransport)

            await #expect(throws: DingsError.self) {
                try await refresher.refresh()
            }
            #expect(liveTransport.requestedURLs.isEmpty)
        }
    }
}
