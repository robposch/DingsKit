import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Seam over the network so the client is testable without live requests.
public protocol Transport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

/// The live `Transport`: `URLSession` with the HTTP cache bypassed, request
/// logging, and transport failures mapped to short `DingsError.network` copy.
public struct URLSessionTransport: Transport {
    private let session: URLSession

    public init(session: URLSession = URLSessionTransport.defaultSession) {
        self.session = session
    }

    /// Ephemeral, with no URL cache, cookies or credential storage.
    /// `URLSession.shared` writes every response to `Cache.db` on disk, keyed
    /// by the full URL, and several providers put the user's API key in the
    /// query string. A short request timeout keeps one hung provider from
    /// using up a widget extension's few seconds.
    public static let defaultSession: URLSession = {
        // Builds before this change stored responses through
        // `URLSession.shared`; drop what they left behind.
        URLCache.shared.removeAllCachedResponses()
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        config.httpCookieStorage = nil
        config.urlCredentialStorage = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 15
        return URLSession(configuration: config)
    }()

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        // "Current values" must come from the API, not an HTTP cache, which would
        // serve a stale 200 in ~0 ms and never decrement the rate limit. Also set
        // per request for sessions passed in by a caller. Our deliberate caching
        // is the App-Group snapshot, not the HTTP layer.
        var request = request
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let method = request.httpMethod ?? "GET"
        let path = request.url.map { Log.redactedPath("\($0.host ?? "")\($0.path)") } ?? "?"
        let start = Date()
        Log.net.debug("→ \(method) \(path)")
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                Log.net.error("✗ \(method) \(path): non-HTTP response")
                throw DingsError.network(coreLocalized("Non-HTTP response"))
            }
            let ms = Int(Date().timeIntervalSince(start) * 1000)
            Log.net.debug("← \(http.statusCode) \(path) (\(data.count) B, \(ms) ms)")
            return (data, http)
        } catch let error as DingsError {
            throw error
        } catch {
            // Log the framework's own wording — the diagnostics want the specific
            // failure — but hand the user the short version.
            Log.net.error("✗ \(method) \(path): \(error.localizedDescription)")
            throw DingsError.network(transportMessage(error))
        }
    }
}

/// Short, plain copy for the transport failures users actually hit.
///
/// Foundation's own strings are written as full sentences and are too long once
/// `userMessage` has prefixed them: "Network error: The Internet connection appears
/// to be offline." measures 344pt against the app banner's 328pt row, so it wraps
/// onto a ragged second line — and it says "offline" twice over, once in the prefix
/// and once in the sentence. Anything unrecognized keeps Foundation's text, which
/// is still better than inventing vague copy.
func transportMessage(_ error: Error) -> String {
    guard let urlError = error as? URLError else { return error.localizedDescription }
    switch urlError.code {
    case .notConnectedToInternet:
        return coreLocalized("No internet connection.")
    case .networkConnectionLost:
        return coreLocalized("The connection was lost.")
    case .timedOut:
        return coreLocalized("The request timed out.")
    case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
        return coreLocalized("Couldn’t reach the server.")
    default:
        return urlError.localizedDescription
    }
}

/// Builds a URL from a constant/interpolated string, throwing instead of force-unwrapping.
public func makeURL(_ string: String) throws -> URL {
    guard let url = URL(string: string) else {
        // The message reaches the UI and the run log. Drop the query: a
        // provider that passes an API key as a query parameter would leak it.
        let redacted = string.firstIndex(of: "?").map { String(string[..<$0]) } ?? string
        throw DingsError.network(coreLocalized("Invalid URL: \(redacted)"))
    }
    return url
}
