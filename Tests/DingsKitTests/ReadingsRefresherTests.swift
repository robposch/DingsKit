import Testing
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import DingsKit
import DingsKitTestSupport

// MARK: - Made-up providers

private let alpha = Provider("alpha-test")
private let beta = Provider("beta-test")
/// Has no `ProviderSpec`: reachable only through `clientOverrides`.
private let bespoke = Provider("bespoke-test")

private let level = SensorType("level")

private struct DeviceDTO: Decodable {
    let serial: String
    let value: Double?
}

/// Registry client for an invented JSON API:
/// `GET https://<provider>.example.test/v1/devices` with a bearer token from
/// the `token` credential field. The body is `[{"serial": "...", "value": 1.0}]`
/// (a missing `value` is a device with no readings); the remaining request
/// budget arrives in `X-Budget-Remaining`.
private final class JSONDevicesClient: ProviderClient, RateLimitReporting, @unchecked Sendable {
    private let provider: Provider
    private let credentials: ProviderCredentials
    private let transport: Transport
    private let lock = NSLock()
    private var remaining: Int?

    init(provider: Provider, credentials: ProviderCredentials, transport: Transport) {
        self.provider = provider
        self.credentials = credentials
        self.transport = transport
    }

    var rateLimitRemaining: Int? { lock.withLock { remaining } }

    func fetchAllReadings() async throws -> [DeviceReadings] {
        var request = URLRequest(url: try makeURL("https://\(provider.rawValue).example.test/v1/devices"))
        request.setValue("Bearer \(credentials["token"])", forHTTPHeaderField: "Authorization")
        let (data, response) = try await transport.send(request)
        guard response.statusCode == 200 else {
            throw ProviderAPIError.http(provider, response.statusCode)
        }
        if let header = response.value(forHTTPHeaderField: "X-Budget-Remaining"), let budget = Int(header) {
            lock.withLock { remaining = budget }
        }
        guard let dtos = try? JSONDecoder().decode([DeviceDTO].self, from: data) else {
            throw ProviderAPIError.decoding(provider, "unexpected body")
        }
        return dtos.map { makeDevice($0.serial, provider, value: $0.value) }
    }
}

/// Client with a canned outcome, for `clientOverrides`.
private struct ScriptedClient: ProviderClient, RateLimitReporting {
    let outcome: Result<[DeviceReadings], any Error>
    var rateLimitRemaining: Int?

    func fetchAllReadings() async throws -> [DeviceReadings] { try outcome.get() }
}

private struct ScriptedFailure: Error, LocalizedError {
    var errorDescription: String? { "scripted failure" }
}

private func makeDevice(_ serial: String, _ provider: Provider, value: Double?, recorded: Date? = nil) -> DeviceReadings {
    DeviceReadings(
        serialNumber: serial, name: "Device \(serial)", model: "Model",
        readings: value.map { [SensorReading(type: level, value: $0, unit: "pct", quality: .good)] } ?? [],
        batteryPercentage: nil, recorded: recorded, provider: provider)
}

private func makeSpec(_ provider: Provider, _ displayName: String) -> ProviderSpec {
    ProviderSpec(
        provider: provider, displayName: displayName, detail: "test provider", isBeta: false,
        fields: [CredentialFieldSpec(id: "token", label: "Token")],
        instructionSteps: [], instructionsURL: "https://example.test", instructionsLinkTitle: "Docs",
        makeClient: { credentials, transport in
            JSONDevicesClient(provider: provider, credentials: credentials, transport: transport)
        })
}

private let specs = [makeSpec(alpha, "Alpha Cloud"), makeSpec(beta, "Beta Cloud")]

/// One canned HTTP answer for `stub(_:)`.
private struct Reply {
    let status: Int, body: String, headers: [String: String]
    static func devices(_ json: String, headers: [String: String] = [:]) -> Reply { Reply(status: 200, body: json, headers: headers) }
    static func failure(_ status: Int) -> Reply { Reply(status: status, body: "", headers: [:]) }
}

/// A `StubTransport` answering per provider host; any other host gets a 404.
private func stub(_ replies: [Provider: Reply]) -> StubTransport {
    StubTransport { request in
        let url = request.url ?? URL(fileURLWithPath: "/")
        let host = url.host ?? ""
        let reply = replies.first { host.hasPrefix("\($0.key.rawValue).") }?.value ?? Reply.failure(404)
        // `HTTPURLResponse.init` is failable; the empty fallback has status 0,
        // which the client rejects, so a construction failure fails the test
        // loudly instead of trapping.
        let response = HTTPURLResponse(url: url, statusCode: reply.status, httpVersion: nil, headerFields: reply.headers)
            ?? HTTPURLResponse()
        return (Data(reply.body.utf8), response)
    }
}

/// Credential stores for `order`; providers listed in `configured` get a token.
private func connections(order: [Provider], configured: Set<Provider>) throws -> ConnectionsStore {
    var stores: [Provider: any ProviderCredentialStore] = [:]
    for provider in order {
        let store = InMemoryProviderCredentialStore()
        if configured.contains(provider) {
            try store.save(ProviderCredentials(fields: ["token": "token-\(provider.rawValue)"]))
        }
        stores[provider] = store
    }
    return ConnectionsStore(stores: stores, order: order)
}

private let oldSnapshotStamp = Date(timeIntervalSince1970: 1_700_000_000)
private let oldAlphaStamp = Date(timeIntervalSince1970: 1_699_990_000)
private let oldBetaStamp = Date(timeIntervalSince1970: 1_699_995_000)
private let oldRecorded = Date(timeIntervalSince1970: 1_699_980_000)

private func seededCache(withStamps: Bool = true) -> InMemoryReadingsCache {
    InMemoryReadingsCache(seeded: CachedReadings(
        devices: [makeDevice("a1", alpha, value: 10, recorded: oldRecorded),
                  makeDevice("b1", beta, value: 20, recorded: oldRecorded)],
        rateLimitRemaining: 7,
        fetchedAt: oldSnapshotStamp,
        providerFetchedAt: withStamps ? [alpha: oldAlphaStamp, beta: oldBetaStamp] : [:]))
}

// MARK: - Live refresh

extension GlobalConfig {
    /// Live-mode merge semantics of `ReadingsRefresher.refresh()`.
    /// In `GlobalConfig` because the refresher resolves specs and logs through
    /// `Dings.config`.
    @Suite("ReadingsRefresher: live merge")
    struct ReadingsRefresherTests {
        init() { TestDings.bootstrap(providers: specs) }

        @Test func everyProviderSucceedsReplacesAllDevicesAndStampsBoth() async throws {
            let cache = seededCache()
            let transport = stub([
                alpha: .devices(#"[{"serial":"a2","value":11}]"#),
                beta: .devices(#"[{"serial":"b2","value":21},{"serial":"b3","value":22}]"#),
            ])
            let refresher = ReadingsRefresher(
                connections: try connections(order: [alpha, beta], configured: [alpha, beta]),
                cache: cache, transport: transport, dataModeStore: nil)
            let before = Date()

            let result = try await refresher.refresh()

            #expect(result.devices.map(\.serialNumber) == ["a2", "b2", "b3"])
            #expect(result.outcomes == [
                ProviderRefreshOutcome(provider: alpha, succeeded: true, message: nil),
                ProviderRefreshOutcome(provider: beta, succeeded: true, message: nil),
            ])
            #expect(try #require(result.providerFetchedAt[alpha]) >= before)
            #expect(try #require(result.providerFetchedAt[beta]) >= before)
            #expect(result.outcomeSummary == "Alpha Cloud ✓ · Beta Cloud ✓")

            let saved = try #require(cache.saved)
            #expect(saved.devices == result.devices)
            #expect(saved.providerFetchedAt == result.providerFetchedAt)
            #expect(saved.fetchedAt >= before)
            #expect(saved.isDemo == false)

            // The registry spec built each client from that provider's stored credentials.
            #expect(transport.requestedURLs == [
                "https://alpha-test.example.test/v1/devices",
                "https://beta-test.example.test/v1/devices",
            ])
            #expect(transport.authHeaders == ["Bearer token-alpha-test", "Bearer token-beta-test"])
        }

        @Test func devicesFollowConfigurationOrderNotSpecOrder() async throws {
            let refresher = ReadingsRefresher(
                connections: try connections(order: [beta, alpha], configured: [alpha, beta]),
                cache: nil,
                transport: stub([
                    alpha: .devices(#"[{"serial":"a1","value":1}]"#),
                    beta: .devices(#"[{"serial":"b1","value":2}]"#),
                ]),
                dataModeStore: nil)

            let result = try await refresher.refresh()

            #expect(result.devices.map(\.serialNumber) == ["b1", "a1"])
            #expect(result.outcomes.map(\.provider) == [beta, alpha])
        }

        @Test func oneProviderFailingKeepsItsDevicesAndStampWhileTheOtherIsReplaced() async throws {
            let cache = seededCache()
            let refresher = ReadingsRefresher(
                connections: try connections(order: [alpha, beta], configured: [alpha, beta]),
                cache: cache,
                transport: stub([alpha: .failure(500), beta: .devices(#"[{"serial":"b2","value":30}]"#)]),
                dataModeStore: nil)
            let before = Date()

            let result = try await refresher.refresh()

            // Alpha's previous device survives unchanged; beta's b1 is replaced by b2.
            #expect(result.devices == [
                makeDevice("a1", alpha, value: 10, recorded: oldRecorded),
                makeDevice("b2", beta, value: 30),
            ])
            #expect(result.providerFetchedAt[alpha] == oldAlphaStamp)
            #expect(try #require(result.providerFetchedAt[beta]) >= before)

            try #require(result.outcomes.count == 2)
            #expect(result.outcomes[0].provider == alpha)
            #expect(result.outcomes[0].succeeded == false)
            #expect(result.outcomes[0].message?.contains("500") == true)
            #expect(result.outcomes[1] == ProviderRefreshOutcome(provider: beta, succeeded: true, message: nil))
            #expect(result.outcomeSummary?.contains("Alpha Cloud ✗") == true)

            // Beta sent no budget header, so the previous budget carries forward.
            #expect(result.rateLimitRemaining == 7)

            let saved = try #require(cache.saved)
            #expect(saved.devices == result.devices)
            #expect(saved.fetchedAt >= before)
            #expect(saved.fetchedAt(for: alpha) == oldAlphaStamp)
            #expect(saved.fetchedAt(for: beta) >= before)
        }

        /// A snapshot written before per-provider stamps existed: the failing
        /// provider inherits the snapshot-level `fetchedAt`, never "now".
        @Test func failingProviderFallsBackToSnapshotStampForLegacyCache() async throws {
            let refresher = ReadingsRefresher(
                connections: try connections(order: [alpha, beta], configured: [alpha, beta]),
                cache: seededCache(withStamps: false),
                transport: stub([alpha: .failure(503), beta: .devices("[]")]),
                dataModeStore: nil)

            let result = try await refresher.refresh()

            #expect(result.providerFetchedAt[alpha] == oldSnapshotStamp)
        }

        /// A provider that has never fetched successfully gets no stamp when
        /// it fails, even though another provider's stamps exist. Inheriting
        /// the snapshot-level `fetchedAt` would claim a sync that never
        /// happened, and keep claiming it on every failed run.
        @Test func neverSucceededProviderGetsNoStampWhenItFails() async throws {
            let cache = InMemoryReadingsCache(seeded: CachedReadings(
                devices: [makeDevice("a1", alpha, value: 10)], rateLimitRemaining: nil,
                fetchedAt: oldSnapshotStamp, providerFetchedAt: [alpha: oldAlphaStamp]))
            let refresher = ReadingsRefresher(
                connections: try connections(order: [alpha, beta], configured: [alpha, beta]),
                cache: cache,
                transport: stub([alpha: .devices(#"[{"serial":"a1","value":11}]"#), beta: .failure(401)]),
                dataModeStore: nil)

            let result = try await refresher.refresh()

            #expect(result.devices.map(\.serialNumber) == ["a1"])
            #expect(result.providerFetchedAt[beta] == nil)
        }

        /// With `cache: nil` there is no previous snapshot to keep: the failing
        /// provider contributes no devices and no stamp, and the merged result
        /// is still returned without anything to persist.
        @Test func failingProviderWithoutCacheContributesNothing() async throws {
            let refresher = ReadingsRefresher(
                connections: try connections(order: [alpha, beta], configured: [alpha, beta]),
                cache: nil,
                transport: stub([alpha: .failure(500), beta: .devices(#"[{"serial":"b1","value":1}]"#)]),
                dataModeStore: nil)

            let result = try await refresher.refresh()

            #expect(result.devices.map(\.serialNumber) == ["b1"])
            #expect(result.providerFetchedAt[alpha] == nil)
            #expect(result.providerFetchedAt[beta] != nil)
        }

        @Test func allProvidersFailingThrowsFirstErrorInConfigurationOrderAndLeavesCache() async throws {
            let seeded = seededCache()
            let original = seeded.saved
            let transport = stub([alpha: .failure(500), beta: .failure(503)])

            let alphaFirst = ReadingsRefresher(
                connections: try connections(order: [alpha, beta], configured: [alpha, beta]),
                cache: seeded, transport: transport, dataModeStore: nil)
            await #expect(throws: ProviderAPIError.http(alpha, 500)) {
                try await alphaFirst.refresh()
            }
            #expect(seeded.saved == original)

            let betaFirst = ReadingsRefresher(
                connections: try connections(order: [beta, alpha], configured: [alpha, beta]),
                cache: seeded, transport: transport, dataModeStore: nil)
            await #expect(throws: ProviderAPIError.http(beta, 503)) {
                try await betaFirst.refresh()
            }
            #expect(seeded.saved == original)
        }

        @Test func noProviderConfiguredThrowsMissingCredentials() async throws {
            let cache = seededCache()
            let original = cache.saved
            let transport = stub([:])
            let refresher = ReadingsRefresher(
                connections: try connections(order: [alpha, beta], configured: []),
                cache: cache, transport: transport, dataModeStore: nil)

            let error = await #expect(throws: DingsError.self) {
                try await refresher.refresh()
            }
            guard case .missingCredentials = error else {
                Issue.record("expected .missingCredentials, got \(String(describing: error))")
                return
            }
            #expect(transport.requestedURLs.isEmpty)
            #expect(cache.saved == original)
        }

        /// A provider can succeed yet report a device with no readings (e.g. a
        /// station offline at the source). The previous readings for that same
        /// provider and serial are carried forward instead of blanking the device.
        @Test func emptyReadingsCarryPreviousReadingsForwardPerDevice() async throws {
            let cache = InMemoryReadingsCache(seeded: CachedReadings(
                devices: [makeDevice("a1", alpha, value: 10, recorded: oldRecorded),
                          // Same serial as a fresh alpha device, but another provider's:
                          // must not leak into alpha.
                          makeDevice("x9", beta, value: 99, recorded: oldRecorded)],
                rateLimitRemaining: nil, fetchedAt: oldSnapshotStamp))
            let refresher = ReadingsRefresher(
                connections: try connections(order: [alpha], configured: [alpha]),
                cache: cache,
                transport: stub([alpha: .devices(#"[{"serial":"a1"},{"serial":"x9"},{"serial":"a3","value":5}]"#)]),
                dataModeStore: nil)

            let result = try await refresher.refresh()

            #expect(result.devices == [
                makeDevice("a1", alpha, value: 10, recorded: oldRecorded),
                makeDevice("x9", alpha, value: nil),
                makeDevice("a3", alpha, value: 5),
            ])
            #expect(result.outcomes.map(\.succeeded) == [true])
        }

        @Test func clientOverrideTakesPrecedenceOverRegisteredSpec() async throws {
            let transport = stub([bespoke: .devices(#"[{"serial":"z1","value":3}]"#)])
            let refresher = ReadingsRefresher(
                connections: try connections(order: [alpha, bespoke], configured: [alpha, bespoke]),
                cache: nil,
                transport: transport,
                dataModeStore: nil,
                clientOverrides: [
                    // Alpha has a spec, but the override wins: no alpha request is made.
                    alpha: { _ in ScriptedClient(outcome: .success([makeDevice("o1", alpha, value: 1)])) },
                    // Bespoke has no spec at all; the override receives the refresher's transport.
                    bespoke: { transport in
                        JSONDevicesClient(
                            provider: bespoke,
                            credentials: ProviderCredentials(fields: ["token": "override"]),
                            transport: transport)
                    },
                ])

            let result = try await refresher.refresh()

            #expect(result.devices.map(\.serialNumber) == ["o1", "z1"])
            #expect(transport.requestedURLs == ["https://bespoke-test.example.test/v1/devices"])
            #expect(transport.authHeaders == ["Bearer override"])
        }

        @Test func overrideFactoryThrowingCountsAsThatProviderFailing() async throws {
            let refresher = ReadingsRefresher(
                connections: try connections(order: [alpha, beta], configured: [alpha, beta]),
                cache: nil,
                transport: stub([beta: .devices(#"[{"serial":"b1","value":1}]"#)]),
                dataModeStore: nil,
                clientOverrides: [alpha: { _ in throw ScriptedFailure() }])

            let result = try await refresher.refresh()

            #expect(result.devices.map(\.serialNumber) == ["b1"])
            #expect(result.outcomes.first == ProviderRefreshOutcome(
                provider: alpha, succeeded: false, message: "scripted failure"))
        }

        /// A configured provider with neither a spec nor an override fails as
        /// `missingCredentials` for that provider only.
        @Test func configuredProviderWithoutSpecOrOverrideFailsSoft() async throws {
            let refresher = ReadingsRefresher(
                connections: try connections(order: [bespoke, alpha], configured: [bespoke, alpha]),
                cache: nil,
                transport: stub([alpha: .devices(#"[{"serial":"a1","value":1}]"#)]),
                dataModeStore: nil)

            let result = try await refresher.refresh()

            #expect(result.devices.map(\.serialNumber) == ["a1"])
            #expect(result.outcomes.map(\.succeeded) == [false, true])

            let onlyBespoke = ReadingsRefresher(
                connections: try connections(order: [bespoke], configured: [bespoke]),
                cache: nil, transport: stub([:]), dataModeStore: nil)
            await #expect(throws: ProviderAPIError.missingCredentials(bespoke)) {
                try await onlyBespoke.refresh()
            }
        }

        @Test func rateLimitReportingIsPickedUpAndLastReporterWins() async throws {
            let cache = seededCache()
            let refresher = ReadingsRefresher(
                connections: try connections(order: [alpha, beta], configured: [alpha, beta]),
                cache: cache,
                transport: stub([
                    alpha: .devices("[]", headers: ["X-Budget-Remaining": "42"]),
                    beta: .devices("[]", headers: ["X-Budget-Remaining": "17"]),
                ]),
                dataModeStore: nil)

            let result = try await refresher.refresh()

            #expect(result.rateLimitRemaining == 17)
            #expect(cache.saved?.rateLimitRemaining == 17)

            let alphaOnly = ReadingsRefresher(
                connections: try connections(order: [alpha], configured: [alpha]),
                cache: nil,
                transport: stub([alpha: .devices("[]", headers: ["X-Budget-Remaining": "42"])]),
                dataModeStore: nil)
            #expect(try await alphaOnly.refresh().rateLimitRemaining == 42)
        }
    }
}
