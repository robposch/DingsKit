import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// In-process `Transport` that returns canned responses for demo mode, for every
/// provider. Routes by host first (several APIs share path suffixes like `/devices`
/// and `/token`), then by path within the provider.
///
/// The routing is a table, not a control-flow chain: as nested `if/else if` it
/// grows a branch for every provider; as data it is flat, and adding a provider
/// is one row.
///
/// The route table is injected (`init(routes:)`) so the fixtures — which are
/// provider-specific — stay with the consuming app; DingsKit only owns the
/// matching mechanism. The zero-arg `init()` yields an empty table (every path
/// 404s), useful as a neutral stub.
public struct MockTransport: Transport {
    /// How a path is matched. One provider's `/sensors` and another's `air-data/latest`
    /// need different matching, so the distinction is explicit rather than implied.
    public enum Match: Sendable {
        case suffix(String)
        case contains(String)

        func matches(_ path: String) -> Bool {
            switch self {
            case .suffix(let s): return path.hasSuffix(s)
            case .contains(let s): return path.contains(s)
            }
        }
    }

    /// One canned response: the path it answers, its body, and any headers.
    public struct Route: Sendable {
        public let match: Match
        /// Deferred, and `@Sendable`: several fixtures are generated per-call so their
        /// timestamps stay relative to "now", and a table may be a `static let` shared
        /// across tasks.
        public let body: @Sendable () -> String
        public var headers: [String: String]

        public init(match: Match, body: @escaping @Sendable () -> String, headers: [String: String] = [:]) {
            self.match = match
            self.body = body
            self.headers = headers
        }
    }

    /// One provider's routes, selected by a fragment of the request host.
    public struct HostRoutes: Sendable {
        public let host: String
        public let routes: [Route]

        public init(host: String, routes: [Route]) {
            self.host = host
            self.routes = routes
        }
    }

    /// Host fragment → its routes, in match order.
    private let routes: [HostRoutes]

    public init(routes: [HostRoutes] = []) {
        self.routes = routes
    }

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        // No force-unwraps: `send` already throws, and demo mode runs on a user's
        // device, so a malformed request must surface as an error rather than trap.
        guard let url = request.url else { throw URLError(.badURL) }

        let host = url.host ?? ""
        let path = url.path

        let route = routes
            .first { host.contains($0.host) }?
            .routes.first { $0.match.matches(path) }

        // An unrouted path is a 404, exactly as before: a provider asking for
        // something demo mode has no fixture for should see "not found", not a crash.
        let status = route == nil ? 404 : 200
        guard let response = HTTPURLResponse(url: url, statusCode: status,
                                             httpVersion: nil,
                                             headerFields: route?.headers) else {
            throw URLError(.badServerResponse)
        }
        let data = route.map { Data($0.body().utf8) } ?? Data()
        return (data, response)
    }
}
