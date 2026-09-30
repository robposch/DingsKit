import Testing
import Foundation
@testable import DingsKit
import DingsKitTestSupport

extension GlobalConfig {
    /// In `GlobalConfig` because the guard logs when it wipes, and `Log` reads
    /// `Dings.config`.
    @Suite("FreshInstallGuard")
    struct FreshInstallGuardTests {
        private static let testProvider = Provider("fresh-install-guard-test")

        init() { TestDings.bootstrap() }

        private func makeConnections(store: InMemoryProviderCredentialStore) -> ConnectionsStore {
            ConnectionsStore(stores: [Self.testProvider: store], order: [Self.testProvider])
        }

        @Test func noMarkerWithCredentialsWipesAndSetsMarker() throws {
            let store = InMemoryProviderCredentialStore()
            try store.save(ProviderCredentials(fields: ["apiKey": "secret"]))
            let connections = makeConnections(store: store)
            let cache = InMemoryReadingsCache(seeded: CachedReadings(devices: [], rateLimitRemaining: nil, fetchedAt: Date()))

            let marker = InMemoryUserDefaults()
            let wiped = FreshInstallGuard.run(connections: connections, cache: cache, marker: marker)

            #expect(wiped == true)
            #expect(try store.load() == nil)
            #expect(cache.load() == nil)
            #expect(marker.bool(forKey: FreshInstallGuard.markerKey) == true)
        }

        @Test func markerPresentWithCredentialsLeavesThemUntouched() throws {
            let store = InMemoryProviderCredentialStore()
            try store.save(ProviderCredentials(fields: ["apiKey": "secret"]))
            let connections = makeConnections(store: store)
            let cache = InMemoryReadingsCache(seeded: CachedReadings(devices: [], rateLimitRemaining: nil, fetchedAt: Date()))

            let marker = InMemoryUserDefaults()
            marker.set(true, forKey: FreshInstallGuard.markerKey)

            let wiped = FreshInstallGuard.run(connections: connections, cache: cache, marker: marker)

            #expect(wiped == false)
            #expect(try store.load() != nil)
            #expect(cache.load() != nil)
        }

        @Test func noMarkerNoCredentialsSetsMarkerOnlyAndDoesNotTouchCache() throws {
            let store = InMemoryProviderCredentialStore()
            let connections = makeConnections(store: store)
            let cache = InMemoryReadingsCache(seeded: CachedReadings(devices: [], rateLimitRemaining: nil, fetchedAt: Date()))

            let marker = InMemoryUserDefaults()
            let wiped = FreshInstallGuard.run(connections: connections, cache: cache, marker: marker)

            #expect(wiped == false)
            #expect(try store.load() == nil)
            // Nothing configured, so the cache must be left alone even though it
            // happens to hold a (unrelated) snapshot.
            #expect(cache.load() != nil)
            #expect(marker.bool(forKey: FreshInstallGuard.markerKey) == true)
        }
    }
}
