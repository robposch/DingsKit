import Testing
import Foundation
@testable import DingsKit
import DingsKitTestSupport

private let first = Provider("first-test")
private let second = Provider("second-test")
private let third = Provider("third-test")

/// A store whose reads always fail, standing in for a transiently unreadable
/// keychain item.
private struct UnreadableStore: ProviderCredentialStore {
    struct ReadFailure: Error {}
    func load() throws -> ProviderCredentials? { throw ReadFailure() }
    func save(_ credentials: ProviderCredentials) throws {}
    func clear() throws {}
}

private let credentials = ProviderCredentials(fields: ["token": "t"])

/// Uses the explicit `init(stores:order:)`, which never touches `Dings.config`,
/// so this suite stays outside `GlobalConfig`.
@Suite struct ConnectionsStoreTests {
    @Test func configuredProvidersFollowsOrderAndSkipsEmptyStores() throws {
        let stores: [Provider: any ProviderCredentialStore] = [
            first: InMemoryProviderCredentialStore(),
            second: InMemoryProviderCredentialStore(),
            third: InMemoryProviderCredentialStore(),
        ]
        let connections = ConnectionsStore(stores: stores, order: [third, first, second])
        #expect(connections.configuredProviders().isEmpty)

        try connections.saveCredentials(credentials, for: first)
        try connections.saveCredentials(credentials, for: third)

        #expect(connections.configuredProviders() == [third, first])
    }

    /// A read error counts as "not configured" rather than propagating, so one
    /// unreadable item cannot break refresh or routing for the others.
    @Test func unreadableStoreCountsAsNotConfigured() throws {
        let good = InMemoryProviderCredentialStore()
        try good.save(credentials)
        let connections = ConnectionsStore(
            stores: [first: UnreadableStore(), second: good], order: [first, second])

        #expect(connections.configuredProviders() == [second])
        #expect(throws: UnreadableStore.ReadFailure.self) {
            try connections.loadCredentials(first)
        }
    }

    /// `order` is the source of truth: a store not listed there is never reported.
    @Test func storeMissingFromOrderIsIgnored() throws {
        let store = InMemoryProviderCredentialStore()
        try store.save(credentials)
        let connections = ConnectionsStore(stores: [first: store], order: [])
        #expect(connections.configuredProviders().isEmpty)
    }

    @Test func loadSaveAndClearRoundTrip() throws {
        let connections = ConnectionsStore(
            stores: [first: InMemoryProviderCredentialStore()], order: [first])

        #expect(try connections.loadCredentials(first) == nil)
        try connections.saveCredentials(credentials, for: first)
        #expect(try connections.loadCredentials(first) == credentials)
        try connections.clear(first)
        #expect(try connections.loadCredentials(first) == nil)
        #expect(connections.configuredProviders().isEmpty)
    }

    @Test func unknownProviderLoadsNilAndClearsAsNoOp() throws {
        let connections = ConnectionsStore(stores: [:], order: [])
        #expect(try connections.loadCredentials(first) == nil)
        try connections.clear(first)
    }

    @Test func savingForUnknownProviderThrowsStorageError() {
        let connections = ConnectionsStore(stores: [:], order: [])
        #expect(throws: ProviderAPIError.storage(first, "No credential store configured.")) {
            try connections.saveCredentials(credentials, for: first)
        }
    }

    @Test func credentialsSubscriptReadsMissingKeysAsEmpty() {
        var bag = ProviderCredentials(fields: [:])
        #expect(bag["token"].isEmpty)
        bag["token"] = "abc"
        #expect(bag["token"] == "abc")
        #expect(bag.fields == ["token": "abc"])
    }
}
