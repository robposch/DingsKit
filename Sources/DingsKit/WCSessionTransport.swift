#if canImport(WatchConnectivity)
import Foundation
import WatchConnectivity

/// `WatchSyncTransport` over WatchConnectivity.
///
/// Payloads travel as a user-info transfer, not as application context:
/// application context is kept on disk by the system for as long as it is
/// current, outside the keychain, and this payload carries API secrets. A
/// user-info transfer is dropped once delivered. The watch can also pull with
/// a live message, which wakes the iPhone app in the background.
///
/// A session activates asynchronously and reports the counterpart reachable a
/// moment after that, so `request()` waits for both, up to
/// `requestReadinessTimeout`, rather than give up on a request made at launch.
public final class WCSessionTransport: NSObject, WatchSyncTransport, WCSessionDelegate, @unchecked Sendable {
    private static let requestKey = "dingsWatchSyncRequest"
    /// How long `request()` waits for the session to be activated and the
    /// counterpart reachable before it gives up.
    static let requestReadinessTimeout: Duration = .seconds(5)

    private let session: WCSession
    private let lock = NSLock()
    /// Requests waiting for the session; the delegate callbacks signal it.
    private let readiness = ReadinessGate()
    private var onActivated: (@Sendable () -> Void)?
    private var onReceive: (@Sendable (WatchSyncPayload) -> Void)?
    private var onRequest: (@Sendable () -> WatchSyncPayload?)?

    /// `nil` where WatchConnectivity is unsupported (an iPad, for example).
    public init?(session: WCSession = .default) {
        guard WCSession.isSupported() else { return nil }
        self.session = session
        super.init()
    }

    /// Call once, after `setHandlers` (i.e. after creating the sender or
    /// receiver), so no delivery arrives before a handler exists.
    public func activate() {
        session.delegate = self
        session.activate()
    }

    public var isCounterpartAvailable: Bool {
        guard session.activationState == .activated else { return false }
        #if os(iOS)
        return session.isPaired && session.isWatchAppInstalled
        #else
        return session.isCompanionAppInstalled
        #endif
    }

    public func send(_ payload: WatchSyncPayload) throws {
        let userInfo = try payload.userInfo()
        // Only the newest state matters: drop anything still queued.
        for transfer in session.outstandingUserInfoTransfers
        where transfer.userInfo[WatchSyncPayload.userInfoKey] != nil {
            transfer.cancel()
        }
        session.transferUserInfo(userInfo)
    }

    public func request() async -> WatchSyncPayload? {
        let ready = await readiness.wait(timeout: Self.requestReadinessTimeout) { [weak self] in
            self?.requestReadiness ?? .unavailable
        }
        guard ready else { return nil }
        // Exactly one of the two handlers is called, once.
        return await withCheckedContinuation { continuation in
            session.sendMessage(
                [Self.requestKey: true],
                replyHandler: { reply in
                    continuation.resume(returning: WatchSyncPayload(userInfo: reply))
                },
                errorHandler: { _ in
                    continuation.resume(returning: nil)
                })
        }
    }

    /// Whether a live message can go out now, might soon, or never will.
    private var requestReadiness: ReadinessGate.State {
        guard session.activationState == .activated else { return .waiting }
        #if os(iOS)
        guard session.isPaired, session.isWatchAppInstalled else { return .unavailable }
        #else
        guard session.isCompanionAppInstalled else { return .unavailable }
        #endif
        return session.isReachable ? .ready : .waiting
    }

    public func setHandlers(
        onActivated: @escaping @Sendable () -> Void,
        onReceive: @escaping @Sendable (WatchSyncPayload) -> Void,
        onRequest: @escaping @Sendable () -> WatchSyncPayload?
    ) {
        lock.withLock {
            self.onActivated = onActivated
            self.onReceive = onReceive
            self.onRequest = onRequest
        }
    }

    // MARK: WCSessionDelegate

    public func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: (any Error)?
    ) {
        if let error {
            Log.credentials.error("watch sync: activation failed: \(error)")
        }
        readiness.signal()
        guard activationState == .activated else { return }
        lock.withLock { onActivated }?()
    }

    public func sessionReachabilityDidChange(_ session: WCSession) {
        readiness.signal()
    }

    public func session(
        _ session: WCSession,
        didFinish userInfoTransfer: WCSessionUserInfoTransfer,
        error: (any Error)?
    ) {
        // Only the error: the transfer holds credentials.
        guard let error else { return }
        Log.credentials.error("watch sync: transfer failed: \(error)")
    }

    public func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        guard let payload = WatchSyncPayload(userInfo: userInfo) else { return }
        lock.withLock { onReceive }?(payload)
    }

    public func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        guard message[Self.requestKey] != nil,
              let payload = lock.withLock({ onRequest })?(),
              let reply = try? payload.userInfo()
        else {
            replyHandler([:])
            return
        }
        replyHandler(reply)
    }

    #if os(watchOS)
    public func sessionCompanionAppInstalledDidChange(_ session: WCSession) {
        readiness.signal()
    }
    #endif

    #if os(iOS)
    public func sessionDidBecomeInactive(_ session: WCSession) {}

    /// The user switched watches: reactivate for the new one.
    public func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }
    #endif
}
#endif
