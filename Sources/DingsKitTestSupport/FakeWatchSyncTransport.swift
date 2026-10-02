import Foundation
import DingsKit

/// In-memory `WatchSyncTransport`: records what was sent and lets a test play
/// the other device. Thread-safe, so concurrency tests can drive it from many
/// tasks at once. Handlers run outside the lock.
public final class FakeWatchSyncTransport: WatchSyncTransport, @unchecked Sendable {
    private struct Handlers {
        var onActivated: (@Sendable () -> Void)?
        var onReceive: (@Sendable (WatchSyncPayload) -> Void)?
        var onRequest: (@Sendable () -> WatchSyncPayload?)?
    }

    private let lock = NSLock()
    private var _isCounterpartAvailable = true
    private var _sendError: (any Error)?
    private var _requestReply: WatchSyncPayload?
    private var _sent: [WatchSyncPayload] = []
    private var handlers = Handlers()

    public init() {}

    public var isCounterpartAvailable: Bool {
        get { lock.withLock { _isCounterpartAvailable } }
        set { lock.withLock { _isCounterpartAvailable = newValue } }
    }
    /// When set, `send` throws it instead of recording.
    public var sendError: (any Error)? {
        get { lock.withLock { _sendError } }
        set { lock.withLock { _sendError = newValue } }
    }
    /// What `request()` returns.
    public var requestReply: WatchSyncPayload? {
        get { lock.withLock { _requestReply } }
        set { lock.withLock { _requestReply = newValue } }
    }
    public var sent: [WatchSyncPayload] { lock.withLock { _sent } }

    public func send(_ payload: WatchSyncPayload) throws {
        try lock.withLock {
            if let _sendError { throw _sendError }
            _sent.append(payload)
        }
    }

    public func request() async -> WatchSyncPayload? { requestReply }

    public func setHandlers(
        onActivated: @escaping @Sendable () -> Void,
        onReceive: @escaping @Sendable (WatchSyncPayload) -> Void,
        onRequest: @escaping @Sendable () -> WatchSyncPayload?
    ) {
        lock.withLock {
            handlers = Handlers(onActivated: onActivated, onReceive: onReceive, onRequest: onRequest)
        }
    }

    /// The session finished activating.
    public func simulateActivation() { lock.withLock { handlers.onActivated }?() }
    /// The other device delivered a payload.
    public func simulateReceive(_ payload: WatchSyncPayload) { lock.withLock { handlers.onReceive }?(payload) }
    /// The other device asked for the current payload.
    public func simulateRequest() -> WatchSyncPayload? { lock.withLock { handlers.onRequest }?() }
}
