import Testing
import Foundation
@testable import DingsKit
import DingsKitTestSupport

private let alpha = Provider("alpha-test")
private let beta = Provider("beta-test")

private func device(_ serial: String, _ provider: Provider) -> DeviceReadings {
    DeviceReadings(
        serialNumber: serial, name: serial, model: "Model",
        readings: [SensorReading(type: SensorType("level"), value: 1, unit: "pct", quality: .good)],
        batteryPercentage: 80, recorded: Date(timeIntervalSince1970: 1_700_000_000), provider: provider)
}

private let snapshotStamp = Date(timeIntervalSince1970: 1_700_000_600)
private let alphaStamp = Date(timeIntervalSince1970: 1_700_000_100)
private let betaStamp = Date(timeIntervalSince1970: 1_700_000_200)

private let twoProviderSnapshot = CachedReadings(
    devices: [device("a1", alpha), device("b1", beta), device("a2", alpha)],
    rateLimitRemaining: 40,
    fetchedAt: snapshotStamp,
    providerFetchedAt: [alpha: alphaStamp, beta: betaStamp],
    isDemo: true)

/// Pure value tests: the snapshot carries explicit `provider` keys, so decoding
/// never consults `Dings.config` and this suite stays outside `GlobalConfig`.
@Suite struct CachedReadingsTests {
    @Test func decodesLegacyJSONWithoutIsDemoAsFalse() throws {
        let legacy = Data(#"{"devices":[],"rateLimitRemaining":117,"fetchedAt":0}"#.utf8)
        let decoded = try JSONDecoder().decode(CachedReadings.self, from: legacy)
        #expect(decoded.isDemo == false)
    }

    @Test func roundTripsIsDemoTrue() throws {
        let snapshot = CachedReadings(devices: [], rateLimitRemaining: nil, fetchedAt: Date(), isDemo: true)
        let data = try JSONEncoder().encode(snapshot)
        let back = try JSONDecoder().decode(CachedReadings.self, from: data)
        #expect(back.isDemo == true)
    }

    @Test func fullSnapshotRoundTripsIncludingProviderStamps() throws {
        let data = try JSONEncoder().encode(twoProviderSnapshot)
        let back = try JSONDecoder().decode(CachedReadings.self, from: data)
        #expect(back == twoProviderSnapshot)
        #expect(back.fetchedAt(for: alpha) == alphaStamp)
        #expect(back.fetchedAt(for: beta) == betaStamp)
    }

    /// Wire format: stamps are an object keyed by provider raw value, not the
    /// flat `[key, value, ...]` array a `[Provider: Date]` would encode to.
    @Test func providerStampsEncodeAsObjectKeyedByRawValue() throws {
        let data = try JSONEncoder().encode(twoProviderSnapshot)
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let stamps = try #require(json["providerFetchedAt"] as? [String: Double])
        #expect(Set(stamps.keys) == ["alpha-test", "beta-test"])
    }

    /// Snapshots from before per-provider stamps decode with none, and every
    /// provider falls back to the snapshot-level date.
    @Test func legacySnapshotWithoutStampsFallsBackToFetchedAt() throws {
        let legacy = Data(#"{"devices":[],"fetchedAt":1000}"#.utf8)
        let decoded = try JSONDecoder().decode(CachedReadings.self, from: legacy)
        #expect(decoded.providerFetchedAt.isEmpty)
        #expect(decoded.rateLimitRemaining == nil)
        #expect(decoded.fetchedAt(for: alpha) == decoded.fetchedAt)
    }

    /// A stamp for a provider this build does not know (written by a newer
    /// version) is kept, not dropped.
    @Test func unknownProviderStampIsKept() throws {
        let json = Data(#"{"devices":[],"fetchedAt":1000,"providerFetchedAt":{"from-the-future":2000}}"#.utf8)
        let decoded = try JSONDecoder().decode(CachedReadings.self, from: json)
        #expect(decoded.providerFetchedAt[Provider("from-the-future")] == Date(timeIntervalSinceReferenceDate: 2000))
    }

    @Test func removingDropsOnlyThatProvidersDevicesAndStamp() throws {
        let remaining = try #require(twoProviderSnapshot.removing(alpha))
        #expect(remaining.devices == [device("b1", beta)])
        #expect(remaining.providerFetchedAt == [beta: betaStamp])
        #expect(remaining.rateLimitRemaining == 40)
        #expect(remaining.fetchedAt == snapshotStamp)
        #expect(remaining.isDemo == true)
    }

    @Test func removingCanClearTheRateLimit() throws {
        let remaining = try #require(twoProviderSnapshot.removing(beta, clearsRateLimit: true))
        #expect(remaining.devices.map(\.serialNumber) == ["a1", "a2"])
        #expect(remaining.rateLimitRemaining == nil)
    }

    @Test func removingTheLastProviderReturnsNil() throws {
        let alphaOnly = try #require(twoProviderSnapshot.removing(beta))
        #expect(alphaOnly.removing(alpha) == nil)
    }

    @Test func removingAnAbsentProviderKeepsEverything() {
        #expect(twoProviderSnapshot.removing(Provider("not-cached")) == twoProviderSnapshot)
    }
}

extension GlobalConfig {
    /// In `GlobalConfig` because `AppGroupReadingsCache` logs, and `Log` reads
    /// `Dings.config`.
    @Suite struct AppGroupReadingsCacheTests {
        init() { TestDings.bootstrap() }

        @Test func savesLoadsAndClears() throws {
            let defaults = InMemoryUserDefaults()
            let cache = AppGroupReadingsCache(defaults: defaults)
            #expect(cache.load() == nil)

            try cache.save(twoProviderSnapshot)
            #expect(AppGroupReadingsCache(defaults: defaults).load() == twoProviderSnapshot)

            cache.clear()
            #expect(cache.load() == nil)
        }

        /// A corrupt payload reads as "no cache" rather than throwing or trapping.
        @Test func undecodablePayloadLoadsAsNil() throws {
            let defaults = InMemoryUserDefaults()
            defaults.set(Data("not json".utf8), forKey: "cachedReadings")
            #expect(AppGroupReadingsCache(defaults: defaults).load() == nil)
        }
    }
}
