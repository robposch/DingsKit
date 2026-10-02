import Testing
import Foundation
@testable import DingsKit
import DingsKitTestSupport

private let alpha = Provider("alpha-sync-test")
private let beta = Provider("beta-sync-test")

private struct UnreadableStore: ProviderCredentialStore {
    struct ReadFailure: Error {}
    func load() throws -> ProviderCredentials? { throw ReadFailure() }
    func save(_ credentials: ProviderCredentials) throws {}
    func clear() throws {}
}

/// Counts writes so a test can tell "no second write" from "wrote the same
/// value again". Single-threaded test use, like `InMemoryProviderCredentialStore`.
private final class CountingStore: ProviderCredentialStore, @unchecked Sendable {
    private var stored: ProviderCredentials?
    private(set) var saves = 0
    private(set) var clears = 0
    func load() throws -> ProviderCredentials? { stored }
    func save(_ credentials: ProviderCredentials) throws {
        saves += 1
        stored = credentials
    }
    func clear() throws {
        clears += 1
        stored = nil
    }
}

private func makeConnections() -> ConnectionsStore {
    ConnectionsStore(
        stores: [alpha: InMemoryProviderCredentialStore(), beta: InMemoryProviderCredentialStore()],
        order: [alpha, beta])
}

private let alphaCreds = ProviderCredentials(fields: ["clientID": "id", "clientSecret": "secret"])
private let betaCreds = ProviderCredentials(fields: ["token": "t"])

// Inside GlobalConfig: the unit and data-mode stores log on save, and logging
// reads `Dings.config`.
extension GlobalConfig {
    @Suite struct WatchSyncPayloadTests {
        init() { TestDings.bootstrap() }

        @Test func roundTripsThroughUserInfo() throws {
            let payload = WatchSyncPayload(
                credentials: [alpha.rawValue: alphaCreds], unitSystem: .imperial, dataMode: .demo)
            let decoded = WatchSyncPayload(userInfo: try payload.userInfo())
            #expect(decoded == payload)
        }

        @Test func userInfoWithoutAPayloadDecodesToNil() {
            #expect(WatchSyncPayload(userInfo: [:]) == nil)
            #expect(WatchSyncPayload(userInfo: [WatchSyncPayload.userInfoKey: Data("nope".utf8)]) == nil)
            #expect(WatchSyncPayload(userInfo: [WatchSyncPayload.userInfoKey: "a string"]) == nil)
        }

        @Test func snapshotCollectsConfiguredProvidersAndPreferences() throws {
            let connections = makeConnections()
            try connections.saveCredentials(alphaCreds, for: alpha)
            let units = UnitPreferenceStore(defaults: InMemoryUserDefaults())
            units.save(.imperial)
            let mode = DataModeStore(defaults: InMemoryUserDefaults())
            mode.save(.demo)

            let payload = try WatchSyncPayload.snapshot(connections: connections, units: units, dataMode: mode)

            #expect(payload.version == WatchSyncPayload.currentVersion)
            #expect(payload.credentials == [alpha.rawValue: alphaCreds])
            #expect(payload.unitSystem == .imperial)
            #expect(payload.dataMode == .demo)
        }

        /// An unreadable keychain must not look like "nothing
        /// connected", or the watch would be wiped.
        @Test func snapshotThrowsWhenAStoreIsUnreadable() {
            let connections = ConnectionsStore(stores: [alpha: UnreadableStore()], order: [alpha])
            #expect(throws: UnreadableStore.ReadFailure.self) {
                _ = try WatchSyncPayload.snapshot(connections: connections, units: nil, dataMode: nil)
            }
        }

        @Test func applyWritesCredentialsAndPreferences() throws {
            let connections = makeConnections()
            let units = UnitPreferenceStore(defaults: InMemoryUserDefaults())
            let mode = DataModeStore(defaults: InMemoryUserDefaults())
            let payload = WatchSyncPayload(
                credentials: [alpha.rawValue: alphaCreds, beta.rawValue: betaCreds],
                unitSystem: .imperial, dataMode: .demo)

            let applied = try payload.apply(to: connections, units: units, dataMode: mode)

            #expect(applied == WatchSyncPayload.Applied(changed: true, removed: []))
            #expect(try connections.loadCredentials(alpha) == alphaCreds)
            #expect(try connections.loadCredentials(beta) == betaCreds)
            #expect(units.load() == .imperial)
            #expect(mode.load() == .demo)
        }

        /// A provider missing from the payload was disconnected on the phone.
        @Test func applyClearsProvidersAbsentFromPayloadAndReportsThem() throws {
            let connections = makeConnections()
            try connections.saveCredentials(alphaCreds, for: alpha)
            try connections.saveCredentials(betaCreds, for: beta)
            let payload = WatchSyncPayload(
                credentials: [alpha.rawValue: alphaCreds], unitSystem: .metric, dataMode: .live)

            let applied = try payload.apply(to: connections, units: nil, dataMode: nil)

            #expect(applied == WatchSyncPayload.Applied(changed: true, removed: [beta]))
            #expect(try connections.loadCredentials(alpha) == alphaCreds)
            #expect(try connections.loadCredentials(beta) == nil)
        }

        /// A payload from a newer build can name providers this build lacks.
        @Test func applyIgnoresProvidersTheStoreDoesNotKnow() throws {
            let connections = makeConnections()
            let payload = WatchSyncPayload(
                credentials: ["from-a-newer-build": betaCreds], unitSystem: .metric, dataMode: .live)

            let applied = try payload.apply(to: connections, units: nil, dataMode: nil)

            #expect(applied == WatchSyncPayload.Applied(changed: false, removed: []))
            #expect(connections.configuredProviders().isEmpty)
        }

        /// A different wire format is rejected before anything is written.
        @Test func applyRejectsUnknownVersionWithoutTouchingStores() throws {
            let connections = makeConnections()
            try connections.saveCredentials(alphaCreds, for: alpha)
            let payload = WatchSyncPayload(
                version: WatchSyncPayload.currentVersion + 1,
                credentials: [:], unitSystem: .metric, dataMode: .live)

            #expect(throws: WatchSyncError.unsupportedVersion(WatchSyncPayload.currentVersion + 1)) {
                _ = try payload.apply(to: connections, units: nil, dataMode: nil)
            }
            #expect(try connections.loadCredentials(alpha) == alphaCreds)
        }

        /// A duplicate delivery must not write to the keychain again.
        @Test func applyingTheSamePayloadTwiceReportsNoChange() throws {
            let alphaStore = CountingStore()
            let betaStore = CountingStore()
            let connections = ConnectionsStore(
                stores: [alpha: alphaStore, beta: betaStore], order: [alpha, beta])
            let units = UnitPreferenceStore(defaults: InMemoryUserDefaults())
            let mode = DataModeStore(defaults: InMemoryUserDefaults())
            let payload = WatchSyncPayload(
                credentials: [alpha.rawValue: alphaCreds], unitSystem: .imperial, dataMode: .live)

            _ = try payload.apply(to: connections, units: units, dataMode: mode)
            let second = try payload.apply(to: connections, units: units, dataMode: mode)

            #expect(second == WatchSyncPayload.Applied(changed: false, removed: []))
            #expect(alphaStore.saves == 1)
            #expect(alphaStore.clears == 0)
            #expect(betaStore.saves == 0)
            #expect(betaStore.clears == 0)
        }
    }
}
