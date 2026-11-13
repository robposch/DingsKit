import Testing
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import DingsKit

@Suite struct URLSessionTransportTests {
    /// Several providers put the API key in the query string, and a stored
    /// response is keyed by its full URL: nothing may be written to disk.
    @Test func defaultSessionStoresNothing() {
        let config = URLSessionTransport.defaultSession.configuration
        #expect(config.urlCache == nil)
        #expect(config.httpCookieStorage == nil)
        #expect(config.urlCredentialStorage == nil)
    }

    /// The widget extension has a few seconds per timeline; one hung provider
    /// must not use up the 60-second default per request.
    @Test func defaultSessionTimesOutQuickly() {
        #expect(URLSessionTransport.defaultSession.configuration.timeoutIntervalForRequest <= 20)
    }
}
