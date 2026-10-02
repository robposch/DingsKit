import Foundation
import DingsKit

/// In-memory `WatchSyncTransport`: records what was sent and lets a test play
/// the other device.
public final class FakeWatchSyncTransport: WatchSyncTransport, @unchecked Sendable {
    public var isCounterpartAvailable = true
    /// When set, `send` throws it instead of recording.
    public var sendError: (any Error)?
    /// What `request()` returns.
    public var requestReply: WatchSyncPayload?
    public private(set) var sent: [WatchSyncPayload] = []

    private var onActivated: (@Sendable () -> Void)?
    private var onReceive: (@Sendable (WatchSyncPayload) -> Void)?
    private var onRequest: (@Sendable () -> WatchSyncPayload?)?

    public init() {}

    public func send(_ payload: WatchSyncPayload) throws {
        if let sendError { throw sendError }
        sent.append(payload)
    }

    public func request() async -> WatchSyncPayload? { requestReply }

    public func setHandlers(
        onActivated: @escaping @Sendable () -> Void,
        onReceive: @escaping @Sendable (WatchSyncPayload) -> Void,
        onRequest: @escaping @Sendable () -> WatchSyncPayload?
    ) {
        self.onActivated = onActivated
        self.onReceive = onReceive
        self.onRequest = onRequest
    }

    /// The session finished activating.
    public func simulateActivation() { onActivated?() }
    /// The other device delivered a payload.
    public func simulateReceive(_ payload: WatchSyncPayload) { onReceive?(payload) }
    /// The other device asked for the current payload.
    public func simulateRequest() -> WatchSyncPayload? { onRequest?() }
}
