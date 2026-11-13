import Testing
import Foundation
@testable import DingsKit
import DingsKitTestSupport

private let alpha = Provider("lost-alpha")
private let beta = Provider("lost-beta")

private struct UnreadableStore: ProviderCredentialStore {
    struct ReadError: Error {}
    func load() throws -> ProviderCredentials? { throw ReadError() }
    func save(_ credentials: ProviderCredentials) throws {}
    func clear() throws {}
}

private func snapshot(isDemo: Bool = false, devices: Int = 1) -> CachedReadings {
    CachedReadings(
        devices: (0..<devices).map { i in
            DeviceReadings(
                serialNumber: "s\(i)", name: "d\(i)", model: "M",
                readings: [SensorReading(type: SensorType("level"), value: 1, unit: "pct", quality: .good)],
                batteryPercentage: nil, recorded: Date(), provider: alpha)
        },
        rateLimitRemaining: nil, fetchedAt: Date(), isDemo: isDemo)
}

private func connections(_ stores: [Provider: any ProviderCredentialStore]) -> ConnectionsStore {
    ConnectionsStore(stores: stores, order: [alpha, beta])
}

/// Live readings in the cache with no key anywhere: the key was lost (a
/// restore that brought back the app's data but not its keychain item).
@Suite("Lost credentials")
struct LostCredentialsTests {
    @Test func liveReadingsWithoutAnyKeyAreLost() {
        let store = connections([alpha: InMemoryProviderCredentialStore(), beta: InMemoryProviderCredentialStore()])
        #expect(store.credentialsLost(given: snapshot()))
    }

    @Test func oneRemainingKeyIsNotLost() throws {
        let kept = InMemoryProviderCredentialStore()
        try kept.save(ProviderCredentials(fields: ["apiKey": "k"]))
        let store = connections([alpha: InMemoryProviderCredentialStore(), beta: kept])
        #expect(!store.credentialsLost(given: snapshot()))
    }

    /// Before the first unlock after a reboot the keychain is unreadable;
    /// that must not read as "the key is gone".
    @Test func unreadableKeychainIsNotLost() {
        let store = connections([alpha: InMemoryProviderCredentialStore(), beta: UnreadableStore()])
        #expect(!store.credentialsLost(given: snapshot()))
    }

    @Test func demoOrEmptyOrMissingCacheIsNotLost() {
        let store = connections([alpha: InMemoryProviderCredentialStore(), beta: InMemoryProviderCredentialStore()])
        #expect(!store.credentialsLost(given: snapshot(isDemo: true)))
        #expect(!store.credentialsLost(given: snapshot(devices: 0)))
        #expect(!store.credentialsLost(given: nil))
    }
}
