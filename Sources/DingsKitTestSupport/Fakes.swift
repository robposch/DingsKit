import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import DingsKit

/// Deterministic clock: hand a `now` closure to code under test and advance
/// `current` to simulate the passage of time.
public final class FakeClock: @unchecked Sendable {
    public var current: Date
    public init(_ start: Date = Date(timeIntervalSince1970: 1_000_000)) { current = start }
    public var now: @Sendable () -> Date { { [self] in current } }
}

/// Routes requests by URL substring to a caller-supplied response, recording the
/// URLs and Authorization headers it saw.
public final class StubTransport: Transport, @unchecked Sendable {
    public typealias Handler = (URLRequest) -> (Data, HTTPURLResponse)
    private let handler: Handler
    public private(set) var requestedURLs: [String] = []
    public private(set) var authHeaders: [String?] = []

    public init(handler: @escaping Handler) { self.handler = handler }

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requestedURLs.append(request.url?.absoluteString ?? "")
        authHeaders.append(request.value(forHTTPHeaderField: "Authorization"))
        return handler(request)
    }
}

/// In-memory `ReadingsCache`, optionally pre-seeded with a snapshot.
public final class InMemoryReadingsCache: ReadingsCache, @unchecked Sendable {
    public private(set) var saved: CachedReadings?
    public init(seeded: CachedReadings? = nil) { saved = seeded }
    public func load() -> CachedReadings? { saved }
    public func save(_ readings: CachedReadings) throws { saved = readings }
    public func clear() { saved = nil }
}

/// In-memory generic-provider credential store.
public final class InMemoryProviderCredentialStore: ProviderCredentialStore, @unchecked Sendable {
    private var stored: ProviderCredentials?
    public init() {}
    public func load() throws -> ProviderCredentials? { stored }
    public func save(_ credentials: ProviderCredentials) throws { stored = credentials }
    public func clear() throws { stored = nil }
}
