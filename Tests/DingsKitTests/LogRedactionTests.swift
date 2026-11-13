import Testing
@testable import DingsKit

/// Logs are public and end up in sysdiagnoses: request paths must keep their
/// route but not the account, station or device identifiers inside them.
@Suite struct LogRedactionTests {
    @Test func identifiersInPathsAreMasked() {
        #expect(Log.redactedPath("consumer-api.airthings.com/v1/accounts/1234567890/sensors")
                == "consumer-api.airthings.com/v1/accounts/…7890/sensors")
        #expect(Log.redactedPath("/swd/rest/observations/station/123456")
                == "/swd/rest/observations/station/…456")
        #expect(Log.redactedPath("/v1/users/self/devices/awair-element/4567")
                == "/v1/users/self/devices/awair-element/…67")
        #expect(Log.redactedPath("/v1.1/devices/C1A2B3D4E5F6/status") == "/v1.1/devices/…E5F6/status")
    }

    @Test func routeWordsAndVersionsAreKept() {
        #expect(Log.redactedPath("/v1/devices") == "/v1/devices")
        #expect(Log.redactedPath("/api/getstationsdata") == "/api/getstationsdata")
    }

    @Test func queryIsDropped() {
        #expect(Log.redactedPath("/devices?api_key=secret&mac=AA:BB") == "/devices")
    }
}
