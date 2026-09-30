import Testing
import Foundation
@testable import DingsKit
import DingsKitTestSupport

extension GlobalConfig {
    /// In `GlobalConfig` because one test reads the bootstrapped config.
    @Suite("DisclosureContent")
    struct DisclosureContentTests {
        @Test func legalLinkRejectsMalformedURL() {
            #expect(LegalLink(title: "Bad", urlString: "") == nil)
            #expect(LegalLink(title: "Bad", urlString: "not a url") == nil)
        }
        @Test func legalLinkAcceptsValidURL() {
            let link = LegalLink(title: "Privacy", urlString: "https://example.com/privacy/")
            #expect(link?.title == "Privacy")
            #expect(link?.url.absoluteString == "https://example.com/privacy/")
        }
        @Test func disclosureHoldsFields() {
            let d = DisclosureContent(
                disclaimer: "Test warning.", severity: .warning,
                legalLinks: [LegalLink(title: "P", urlString: "https://example.com")].compactMap { $0 })
            #expect(d.severity == .warning)
            #expect(d.legalLinks.count == 1)
        }
        @Test func configDefaultsToEmptyInfoDisclosure() {
            TestDings.bootstrap()
            #expect(Dings.config.disclosure.disclaimer.isEmpty)
            #expect(Dings.config.disclosure.severity == .info)
        }
    }
}
