import Testing
import Foundation
@testable import DingsKit
import DingsKitTestSupport

/// `DingsError` copy is built from the package's string catalog only, never
/// `Dings.config`, so this suite runs in parallel. Assertions check the
/// caller-supplied detail and loose English keywords, since the wording is
/// localized.
@Suite struct DingsErrorCopyTests {
    @Test(arguments: [
        DingsError.storage("disk full"),
        .cache("bad snapshot"),
        .missingCredentials("no key"),
        .network("offline"),
    ])
    func messageCarriesTheDetail(error: DingsError) {
        let detail: String
        switch error {
        case .storage(let d), .cache(let d), .missingCredentials(let d), .network(let d): detail = d
        case .timeout: detail = ""
        }
        #expect(error.userMessage.contains(detail))
        #expect(error.userMessage.count > detail.count)
    }

    @Test func timeoutHasItsOwnSentence() {
        #expect(DingsError.timeout.userMessage.contains("timed out"))
    }

    /// `errorDescription` routes the same copy through `localizedDescription`,
    /// so logs never show Foundation's generic "operation couldn't be completed".
    @Test(arguments: [DingsError.storage("s"), .cache("c"), .timeout, .missingCredentials("m"), .network("n")])
    func localizedDescriptionIsTheUserMessage(error: DingsError) {
        #expect(error.errorDescription == error.userMessage)
        #expect((error as any Error).localizedDescription == error.userMessage)
    }
}

private let named = Provider("named-copy-test")
/// Deliberately has no spec, so its name falls back to the raw value.
private let unnamed = Provider("unregistered-copy-test")

private func spec(_ provider: Provider, _ displayName: String) -> ProviderSpec {
    ProviderSpec(
        provider: provider, displayName: displayName, detail: "", isBeta: true, fields: [],
        instructionSteps: [], instructionsURL: "https://example.test", instructionsLinkTitle: "Docs",
        makeClient: { _, _ in NoClient() })
}

private struct NoClient: ProviderClient {
    func fetchAllReadings() async throws -> [DeviceReadings] { [] }
}

extension GlobalConfig {
    /// In `GlobalConfig` because the copy names the provider via
    /// `Provider.displayName`, which resolves against registered specs.
    @Suite struct ProviderAPIErrorCopyTests {
        init() { TestDings.bootstrap(providers: [spec(named, "Named Cloud")]) }

        @Test func everyCaseNamesTheProviderAndCarriesItsDetail() {
            let cases: [(ProviderAPIError, String?)] = [
                (.missingCredentials(named), nil),
                (.invalidCredentials(named, hint: "create a new key"), "create a new key"),
                (.network(named, "offline"), "offline"),
                (.decoding(named, "unexpected field"), "unexpected field"),
                (.http(named, 429), "429"),
                (.storage(named, "locked"), "locked"),
            ]
            for (error, detail) in cases {
                #expect(error.userMessage.contains("Named Cloud"), "\(error)")
                if let detail { #expect(error.userMessage.contains(detail), "\(error)") }
                #expect(error.errorDescription == error.userMessage)
                #expect((error as any Error).localizedDescription == error.userMessage)
            }
        }

        @Test func unregisteredProviderFallsBackToRawValue() {
            #expect(unnamed.displayName == "unregistered-copy-test")
            #expect(ProviderAPIError.http(unnamed, 500).userMessage.contains("unregistered-copy-test"))
        }

        @Test func specLookupsFollowTheRegistry() {
            #expect(named.displayName == "Named Cloud")
            #expect(ProviderSpec.spec(for: named)?.displayName == "Named Cloud")
            #expect(ProviderSpec.spec(for: unnamed) == nil)
            #expect(ProviderSpec.beta.map(\.provider) == [named])
            #expect(ProviderSpec.verified.isEmpty)
        }
    }
}
