import Foundation
import Testing
import DingsKitTestSupport
@testable import DingsKit

/// A legacy provider error: defined outside DingsKit in real life, so
/// `ProviderConnectionModel` cannot catch it by concrete type. It carries its
/// own user copy through `LocalizedError`, as a consuming app's bespoke provider
/// error types do.
private enum FakeProviderError: Error, LocalizedError {
    case nobodySharing
    var errorDescription: String? { "No one is sharing with this account yet." }
}

/// An error with no user-facing copy at all — must still reach the user as
/// *something*, via the unchanged catch-all.
private struct OpaqueError: Error {}

private struct ThrowingValidator: ProviderCredentialValidating {
    let error: any Error
    func validate(provider: Provider, credentials: ProviderCredentials) async throws -> Int {
        throw error
    }
}

private struct UnusedClient: ProviderClient {
    func fetchAllReadings() async throws -> [DeviceReadings] { [] }
}

extension GlobalConfig {
    /// In `GlobalConfig` because error copy resolves provider names from `Dings.config`.
    @Suite("Provider connection error copy")
    @MainActor
    struct ProviderConnectionErrorTests {
        private static let provider = Provider("fake")

        /// `ProviderAPIError.userMessage` resolves `Provider.displayName` from the
        /// registered specs, so each test installs a config carrying `spec`.
        init() { TestDings.bootstrap(providers: [Self.spec]) }

        private static let spec = ProviderSpec(
            provider: provider,
            displayName: "Fake",
            detail: "test provider",
            isBeta: false,
            fields: [CredentialFieldSpec(id: "email", label: "Email", isSecure: false)],
            instructionSteps: [],
            instructionsURL: "https://example.com",
            instructionsLinkTitle: "About",
            makeClient: { _, _ in UnusedClient() }
        )

        private func makeModel(throwing error: any Error) -> ProviderConnectionModel {
            let spec = Self.spec
            let connections = ConnectionsStore(
                stores: [Self.provider: InMemoryProviderCredentialStore()], order: [Self.provider])
            return ProviderConnectionModel(
                spec: spec, connections: connections,
                validator: ThrowingValidator(error: error))
        }

        /// The regression: a provider error that already says what is wrong used to
        /// be swallowed by the catch-all and shown as
        /// "Unexpected error: The operation couldn't be completed. (… error 5.)".
        @Test func providerErrorWithCopyIsShownVerbatim() async {
            let model = makeModel(throwing: FakeProviderError.nobodySharing)
            model.values["email"] = "f@example.com"
            await model.validateAndSave {}
            #expect(model.state == .invalid("No one is sharing with this account yet."))
        }

        /// A `ProviderAPIError` keeps its own copy, including the provider-authored
        /// recovery hint, instead of being rewrapped by the catch-all. Asserts on
        /// the hint and the prefix rather than the full sentence, since the
        /// surrounding wording is localized.
        @Test func providerAPIErrorStillUsesItsOwnMessage() async {
            let model = makeModel(
                throwing: ProviderAPIError.invalidCredentials(Self.provider, hint: "make a new key"))
            model.values["email"] = "f@example.com"
            await model.validateAndSave {}
            guard case .invalid(let message) = model.state else {
                Issue.record("expected .invalid, got \(model.state)")
                return
            }
            #expect(message.contains("make a new key"))
            #expect(message.contains("Fake"))
            #expect(!message.hasPrefix("Unexpected error:"))
        }

        /// An error carrying no copy keeps the old catch-all wording — better a
        /// clumsy message than a silent failure.
        @Test func errorWithoutCopyFallsBackToUnexpected() async {
            let model = makeModel(throwing: OpaqueError())
            model.values["email"] = "f@example.com"
            await model.validateAndSave {}
            guard case .invalid(let message) = model.state else {
                Issue.record("expected .invalid, got \(model.state)")
                return
            }
            #expect(message.hasPrefix("Unexpected error:"))
        }
    }
}
