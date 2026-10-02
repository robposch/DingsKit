import Foundation

/// The device-to-device channel between an iPhone app and its Watch app.
/// `WCSessionTransport` is the real one; tests use `FakeWatchSyncTransport`.
public protocol WatchSyncTransport: AnyObject, Sendable {
    /// Whether a payload can be queued for the other device right now.
    var isCounterpartAvailable: Bool { get }
    /// Queue a payload for delivery. Delivery may happen later.
    func send(_ payload: WatchSyncPayload) throws
    /// Ask the other device for its current payload. `nil` when it cannot be
    /// reached or has nothing to send.
    func request() async -> WatchSyncPayload?
    /// Install the callbacks. Called once, before activation.
    func setHandlers(
        onActivated: @escaping @Sendable () -> Void,
        onReceive: @escaping @Sendable (WatchSyncPayload) -> Void,
        onRequest: @escaping @Sendable () -> WatchSyncPayload?)
}

/// iPhone side. Sends the current payload whenever it differs from the last
/// one sent, and answers the watch when it asks.
public final class WatchSyncSender: @unchecked Sendable {
    private let transport: any WatchSyncTransport
    private let makePayload: @Sendable () throws -> WatchSyncPayload
    private let lock = NSLock()
    private var lastSent: WatchSyncPayload?

    public init(
        transport: any WatchSyncTransport,
        makePayload: @escaping @Sendable () throws -> WatchSyncPayload
    ) {
        self.transport = transport
        self.makePayload = makePayload
        transport.setHandlers(
            onActivated: { [weak self] in self?.pushIfChanged() },
            onReceive: { _ in },
            onRequest: { [weak self] in self?.currentPayload() })
    }

    /// Cheap to call often: a no-op unless the payload changed since the last
    /// successful send. Returns whether a payload was queued.
    @discardableResult
    public func pushIfChanged() -> Bool {
        guard transport.isCounterpartAvailable, let payload = currentPayload() else { return false }
        guard lock.withLock({ lastSent != payload }) else { return false }
        do {
            try transport.send(payload)
        } catch {
            return false
        }
        lock.withLock { lastSent = payload }
        return true
    }

    /// `nil` when the payload cannot be built (e.g. the keychain is locked):
    /// sending nothing is safe, sending an empty payload would wipe the watch.
    private func currentPayload() -> WatchSyncPayload? {
        try? makePayload()
    }
}

/// Watch side. Applies whatever the phone sends and reports real changes.
public final class WatchSyncReceiver: @unchecked Sendable {
    private let transport: any WatchSyncTransport
    private let apply: @Sendable (WatchSyncPayload) throws -> WatchSyncPayload.Applied
    private let onApplied: @Sendable (WatchSyncPayload.Applied) -> Void

    public init(
        transport: any WatchSyncTransport,
        apply: @escaping @Sendable (WatchSyncPayload) throws -> WatchSyncPayload.Applied,
        onApplied: @escaping @Sendable (WatchSyncPayload.Applied) -> Void
    ) {
        self.transport = transport
        self.apply = apply
        self.onApplied = onApplied
        transport.setHandlers(
            onActivated: {},
            onReceive: { [weak self] in self?.handle($0) },
            onRequest: { nil })
    }

    /// Apply a payload. `onApplied` fires only when something changed, so a
    /// duplicate delivery triggers no refresh. A failed apply is dropped; the
    /// next delivery or request retries it.
    public func handle(_ payload: WatchSyncPayload) {
        guard let applied = try? apply(payload), applied.changed else { return }
        onApplied(applied)
    }

    /// Ask the phone for its payload and apply it. `false` when the phone
    /// could not be reached or had none.
    @discardableResult
    public func requestFromPhone() async -> Bool {
        guard let payload = await transport.request() else { return false }
        handle(payload)
        return true
    }
}
