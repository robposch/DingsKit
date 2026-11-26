import Foundation
import Testing
import DingsKitTestSupport
@testable import DingsKit

/// A provider whose client rewrites part of its own credentials, the way an
/// OAuth client with single-use refresh tokens does: validating the setup form
/// runs a refresh, the vendor retires the entered refresh token, and the client
/// saves the bag with the new one. `validateAndSave` must not put the retired
/// token back, and must never keep a bag that belongs to another connection.
extension GlobalConfig {
    @Suite("Rotating credentials survive validate-and-save")
    @MainActor
    struct RotatingCredentialsTests {
        private static let provider = Provider("rotating")
        private static let rotation = CredentialRotation(
            fieldID: "refreshToken", previousValueKey: "previousRefreshToken")

        // MARK: - The bug

        /// The reproduction: the client rotates RT-1 to RT-2 during validation
        /// and saves it. The stored bag must end up with RT-2 and everything
        /// the client added (access token, expiry, the replaced token), not the
        /// form's RT-1.
        @Test func credentialsTheClientRotatedDuringValidationAreKept() async throws {
            let store = RecordingStore()
            let model = Self.model(store: store, rotations: [Self.rotation]) { entered, store in
                store.write(Self.rotated(entered, to: "RT-2"))
            }
            Self.fillForm(model, refreshToken: "RT-1")

            var connected = false
            await model.validateAndSave { connected = true }

            #expect(connected)
            let stored = try #require(store.current)
            #expect(stored["refreshToken"] == "RT-2")
            #expect(stored["previousRefreshToken"] == "RT-1")
            #expect(stored["accessToken"] == "AT-RT-2")
            #expect(stored["accessTokenExpiry"] == "4102444800")
            #expect(stored["clientId"] == "client-1234")
            #expect(stored["clientSecret"] == "secret")
        }

        /// The same validation for a provider that declares no rotating fields:
        /// the form's credentials are saved over whatever the client wrote,
        /// exactly as before rotations existed.
        @Test func withoutDeclaredRotationsTheFormCredentialsAreSavedAsBefore() async throws {
            let store = RecordingStore()
            let model = Self.model(store: store, rotations: []) { entered, store in
                store.write(Self.rotated(entered, to: "RT-2"))
            }
            Self.fillForm(model, refreshToken: "RT-1")

            await model.validateAndSave {}

            #expect(store.current == Self.form(refreshToken: "RT-1"))
            #expect(store.saves.last == Self.form(refreshToken: "RT-1"))
            #expect(model.state == .connected(maskedID: "••••1234"))
        }

        // MARK: - Another connection in the store

        /// The user replaces an older connection of the same vendor app (same
        /// client ID and secret, a newly generated refresh token). A background
        /// refresh of the old connection rotates its own token while the form
        /// validates. Its bag matches the form on every non-rotating field, but
        /// it is not the form's token line, so it must not be kept.
        @Test func aBagAnotherConnectionWroteDuringValidationIsNotKept() async throws {
            let old = Self.rotated(Self.form(refreshToken: "OLD-3"), to: "OLD-4")
            let store = RecordingStore(old)
            let model = Self.model(store: store, rotations: [Self.rotation]) { _, store in
                store.write(Self.rotated(old, to: "OLD-5"))
            }
            Self.fillForm(model, refreshToken: "NEW-1")

            await model.validateAndSave {}

            #expect(store.current == Self.form(refreshToken: "NEW-1"))
        }

        /// The old connection was stored with different app credentials and is
        /// still there unchanged after a validation that wrote nothing: the
        /// form replaces it.
        @Test func anOlderStoredConnectionIsReplacedByTheForm() async throws {
            var old = Self.rotated(Self.form(refreshToken: "OLD-1"), to: "OLD-2")
            old["clientId"] = "other-9999"
            let store = RecordingStore(old)
            let model = Self.model(store: store, rotations: [Self.rotation]) { _, _ in }
            Self.fillForm(model, refreshToken: "NEW-1")

            await model.validateAndSave {}

            #expect(store.current == Self.form(refreshToken: "NEW-1"))
        }

        /// The stored bag continues the form's refresh token but a non-rotating
        /// field differs (the user corrected the client secret): the form wins.
        @Test func aDifferentNonRotatingFieldMeansTheFormIsSaved() async throws {
            let store = RecordingStore()
            let model = Self.model(store: store, rotations: [Self.rotation]) { entered, store in
                var bag = Self.rotated(entered, to: "RT-2")
                bag["clientSecret"] = "old-secret"
                store.write(bag)
            }
            Self.fillForm(model, refreshToken: "RT-1")

            await model.validateAndSave {}

            #expect(store.current == Self.form(refreshToken: "RT-1"))
        }

        /// A blank rotating field in the form never matches a bag that simply
        /// lacks the previous-value key.
        @Test func aBlankRotatingFieldDoesNotAdoptABagWithoutAPreviousValue() async throws {
            let store = RecordingStore(Self.form(refreshToken: "OTHER"))
            let model = Self.model(store: store, rotations: [Self.rotation]) { _, _ in }
            Self.fillForm(model, refreshToken: "")

            await model.validateAndSave {}

            #expect(store.current == Self.form(refreshToken: ""))
        }

        // MARK: - No refresh during validation

        /// Nothing stored and nothing written (the client had no reason to
        /// refresh): the form's credentials are saved.
        @Test func aValidationWithoutARefreshSavesTheForm() async throws {
            let store = RecordingStore()
            let model = Self.model(store: store, rotations: [Self.rotation]) { _, _ in }
            Self.fillForm(model, refreshToken: "RT-1")

            await model.validateAndSave {}

            #expect(store.current == Self.form(refreshToken: "RT-1"))
            #expect(model.state == .connected(maskedID: "••••1234"))
        }

        /// The user re-enters the refresh token they generated at the vendor,
        /// which this app already rotated once (the stored bag records it as
        /// the previous value). The client validates with the stored access
        /// token and writes nothing. Saving the form would bring back the
        /// retired token; the stored bag continues it and is kept.
        @Test func reEnteringAnAlreadyRotatedTokenKeepsTheStoredContinuation() async throws {
            let stored = Self.rotated(Self.form(refreshToken: "RT-1"), to: "RT-2")
            let store = RecordingStore(stored)
            let model = Self.model(store: store, rotations: [Self.rotation]) { _, _ in }
            Self.fillForm(model, refreshToken: "RT-1")

            await model.validateAndSave {}

            #expect(store.current == stored)
        }

        /// The user re-enters exactly what is stored; the stored bag also holds
        /// an access token from the same token line. Keeping it is equivalent
        /// to saving the form, minus a needless refresh next time.
        @Test func reEnteringTheStoredConnectionKeepsItsAccessToken() async throws {
            var stored = Self.form(refreshToken: "RT-1")
            stored["accessToken"] = "AT-1"
            let store = RecordingStore(stored)
            let model = Self.model(store: store, rotations: [Self.rotation]) { _, _ in }
            Self.fillForm(model, refreshToken: "RT-1")

            await model.validateAndSave {}

            #expect(store.current == stored)
        }

        // MARK: - Store failures

        /// The store cannot be read after validation: nothing tells the model
        /// what the client wrote, so it falls back to saving the form, as before.
        @Test func anUnreadableStoreFallsBackToSavingTheForm() async throws {
            let store = RecordingStore()
            store.failsLoads = true
            let model = Self.model(store: store, rotations: [Self.rotation]) { entered, store in
                store.write(Self.rotated(entered, to: "RT-2"))
            }
            Self.fillForm(model, refreshToken: "RT-1")

            await model.validateAndSave {}

            #expect(store.saves.last == Self.form(refreshToken: "RT-1"))
            #expect(model.state == .connected(maskedID: "••••1234"))
        }

        /// A store that cannot be written still reports the failure, also on
        /// the path that keeps the client's bag.
        @Test func anUnwritableStoreStillReportsTheFailure() async throws {
            let store = RecordingStore()
            let model = Self.model(store: store, rotations: [Self.rotation]) { entered, store in
                store.write(Self.rotated(entered, to: "RT-2"))
                store.failsSaves = true
            }
            Self.fillForm(model, refreshToken: "RT-1")

            var connected = false
            await model.validateAndSave { connected = true }

            #expect(!connected)
            guard case .invalid = model.state else {
                Issue.record("expected .invalid, got \(model.state)")
                return
            }
        }

        // MARK: - What the app sees afterwards

        /// The card shows the masked first field (the client ID), the same
        /// value `load()` shows on the next launch.
        @Test func theMaskedIDComesFromTheKeptBagAndMatchesLoad() async throws {
            let store = RecordingStore()
            let model = Self.model(store: store, rotations: [Self.rotation]) { entered, store in
                store.write(Self.rotated(entered, to: "RT-2"))
            }
            Self.fillForm(model, refreshToken: "RT-1")

            await model.validateAndSave {}
            let afterConnect = model.state
            model.load()

            #expect(afterConnect == .connected(maskedID: "••••1234"))
            #expect(model.state == afterConnect)
        }

        /// The kept bag still goes through `saveCredentials`, so a store that
        /// reacts to saves sees the final credentials, and the payload the
        /// watch sync builds from the store carries the rotated token.
        @Test func theFinalSaveAndTheWatchPayloadCarryTheRotatedCredentials() async throws {
            let store = RecordingStore()
            let model = Self.model(store: store, rotations: [Self.rotation]) { entered, store in
                store.write(Self.rotated(entered, to: "RT-2"))
            }
            Self.fillForm(model, refreshToken: "RT-1")

            await model.validateAndSave {}

            #expect(store.saves.last?["refreshToken"] == "RT-2")
            let payload = try WatchSyncPayload.snapshot(
                connections: Self.connections(store), units: nil, dataMode: nil)
            #expect(payload.credentials[Self.provider.rawValue]?["refreshToken"] == "RT-2")
        }

        // MARK: - Helpers

        private static func spec(
            rotations: [CredentialRotation],
            store: RecordingStore,
            duringValidation: @escaping @Sendable (ProviderCredentials, RecordingStore) -> Void
        ) -> ProviderSpec {
            ProviderSpec(
                provider: provider,
                displayName: "Rotating",
                detail: "test provider",
                isBeta: false,
                fields: [
                    CredentialFieldSpec(id: "clientId", label: "Client ID", isSecure: false),
                    CredentialFieldSpec(id: "clientSecret", label: "Client Secret"),
                    CredentialFieldSpec(id: "refreshToken", label: "Refresh Token"),
                ],
                instructionSteps: [],
                instructionsURL: "https://example.com",
                instructionsLinkTitle: "About",
                makeClient: { credentials, _ in
                    ClosureClient { duringValidation(credentials, store) }
                },
                rotatingCredentials: rotations
            )
        }

        /// The model with the live validator, so the client is built from the
        /// registered spec exactly as in the app. The transport is never used.
        private static func model(
            store: RecordingStore,
            rotations: [CredentialRotation],
            duringValidation: @escaping @Sendable (ProviderCredentials, RecordingStore) -> Void
        ) -> ProviderConnectionModel {
            let spec = spec(rotations: rotations, store: store, duringValidation: duringValidation)
            TestDings.bootstrap(providers: [spec])
            let transport = StubTransport { request in
                Issue.record("unexpected request \(request.url?.absoluteString ?? "")")
                return (Data(), HTTPURLResponse())
            }
            return ProviderConnectionModel(
                spec: spec, connections: connections(store),
                validator: LiveProviderCredentialValidator(transport: transport))
        }

        private static func connections(_ store: RecordingStore) -> ConnectionsStore {
            ConnectionsStore(stores: [provider: store], order: [provider])
        }

        private static func fillForm(_ model: ProviderConnectionModel, refreshToken: String) {
            model.values = ["clientId": "client-1234", "clientSecret": "secret", "refreshToken": refreshToken]
        }

        private nonisolated static func form(refreshToken: String) -> ProviderCredentials {
            ProviderCredentials(fields: [
                "clientId": "client-1234", "clientSecret": "secret", "refreshToken": refreshToken,
            ])
        }

        /// What a rotating client saves after a refresh.
        private nonisolated static func rotated(_ bag: ProviderCredentials, to next: String) -> ProviderCredentials {
            var updated = bag
            updated["previousRefreshToken"] = bag["refreshToken"]
            updated["refreshToken"] = next
            updated["accessToken"] = "AT-\(next)"
            updated["accessTokenExpiry"] = "4102444800"
            return updated
        }
    }
}

private struct ClosureClient: ProviderClient {
    let fetch: @Sendable () -> Void
    func fetchAllReadings() async throws -> [DeviceReadings] {
        fetch()
        return []
    }
}

/// The provider's credential store, shared by the model and the client, with
/// a record of every save the model made through it.
private final class RecordingStore: ProviderCredentialStore, @unchecked Sendable {
    private let lock = NSLock()
    private var bag: ProviderCredentials?
    private var recorded: [ProviderCredentials] = []
    private var loadFailure = false
    private var saveFailure = false

    init(_ bag: ProviderCredentials? = nil) { self.bag = bag }

    var current: ProviderCredentials? { lock.withLock { bag } }
    var saves: [ProviderCredentials] { lock.withLock { recorded } }
    var failsLoads: Bool {
        get { lock.withLock { loadFailure } }
        set { lock.withLock { loadFailure = newValue } }
    }
    var failsSaves: Bool {
        get { lock.withLock { saveFailure } }
        set { lock.withLock { saveFailure = newValue } }
    }

    /// A write by the provider's client (or another process), not by the model.
    func write(_ new: ProviderCredentials) { lock.withLock { bag = new } }

    func load() throws -> ProviderCredentials? {
        try lock.withLock {
            if loadFailure { throw ProviderAPIError.storage(Provider("rotating"), "locked") }
            return bag
        }
    }

    func save(_ credentials: ProviderCredentials) throws {
        try lock.withLock {
            if saveFailure { throw ProviderAPIError.storage(Provider("rotating"), "read-only") }
            bag = credentials
            recorded.append(credentials)
        }
    }

    func clear() throws { lock.withLock { bag = nil } }
}
