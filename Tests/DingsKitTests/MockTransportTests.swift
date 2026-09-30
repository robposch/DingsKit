import Testing
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import DingsKit

/// Counts how often a route body is produced.
private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    func next() -> Int { lock.withLock { value += 1; return value } }
}

private func request(_ string: String) throws -> URLRequest {
    URLRequest(url: try makeURL(string))
}

private func text(_ data: Data) -> String? { String(bytes: data, encoding: .utf8) }

/// `MockTransport` never touches `Dings.config`, so this suite runs in parallel.
@Suite struct MockTransportTests {
    /// Two hosts share the `/devices` suffix; the host picks the table first.
    private let transport = MockTransport(routes: [
        MockTransport.HostRoutes(host: "one.example.test", routes: [
            MockTransport.Route(match: .suffix("/devices"), body: { "one-devices" },
                                headers: ["X-Budget-Remaining": "12"]),
            MockTransport.Route(match: .contains("air-data"), body: { "one-air" }),
            // Also matches `/v1/devices`, but the earlier row wins.
            MockTransport.Route(match: .contains("devices"), body: { "one-shadowed" }),
        ]),
        MockTransport.HostRoutes(host: "two.example.test", routes: [
            MockTransport.Route(match: .suffix("/devices"), body: { "two-devices" }),
        ]),
    ])

    @Test func routesByHostBeforePath() async throws {
        let (oneData, oneResponse) = try await transport.send(request("https://api.one.example.test/v1/devices"))
        let (twoData, twoResponse) = try await transport.send(request("https://two.example.test/devices"))
        #expect(text(oneData) == "one-devices")
        #expect(oneResponse.statusCode == 200)
        #expect(text(twoData) == "two-devices")
        #expect(twoResponse.statusCode == 200)
    }

    @Test func suffixAndContainsMatchDifferently() async throws {
        let (containsData, _) = try await transport.send(
            request("https://one.example.test/v2/air-data/latest"))
        #expect(text(containsData) == "one-air")

        // `/devices/42` does not end in `/devices`, so the suffix row misses and
        // the later `contains` row answers.
        let (fallthroughData, _) = try await transport.send(request("https://one.example.test/v1/devices/42"))
        #expect(text(fallthroughData) == "one-shadowed")
    }

    @Test func routeHeadersArePassedThrough() async throws {
        let (_, response) = try await transport.send(request("https://one.example.test/devices"))
        #expect(response.value(forHTTPHeaderField: "X-Budget-Remaining") == "12")
    }

    @Test func unroutedPathOrHostIs404WithEmptyBody() async throws {
        for url in ["https://one.example.test/token", "https://unknown.example.test/devices"] {
            let (data, response) = try await transport.send(request(url))
            #expect(response.statusCode == 404)
            #expect(data.isEmpty)
            #expect(response.url?.absoluteString == url)
        }
    }

    @Test func emptyTableAnswers404ForEverything() async throws {
        let (data, response) = try await MockTransport().send(request("https://one.example.test/devices"))
        #expect(response.statusCode == 404)
        #expect(data.isEmpty)
    }

    /// Bodies are produced per call so time-relative fixtures stay fresh.
    @Test func bodyIsEvaluatedOnEveryRequest() async throws {
        let counter = Counter()
        let transport = MockTransport(routes: [
            MockTransport.HostRoutes(host: "example.test", routes: [
                MockTransport.Route(match: .suffix("/n"), body: { "\(counter.next())" }),
            ]),
        ])
        let (firstData, _) = try await transport.send(request("https://example.test/n"))
        let (secondData, _) = try await transport.send(request("https://example.test/n"))
        #expect(text(firstData) == "1")
        #expect(text(secondData) == "2")
    }

    /// A malformed request surfaces as an error instead of trapping.
    @Test func requestWithoutURLThrowsBadURL() async throws {
        var bare = try request("https://example.test/")
        bare.url = nil
        await #expect(throws: URLError(.badURL)) {
            try await transport.send(bare)
        }
    }
}
