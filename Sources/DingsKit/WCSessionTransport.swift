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
public final class WCSessionTransport: NSObject, WatchSyncTransport, WCSessionDelegate, @unchecked Sendable {
    private static let requestKey = "dingsWatchSyncRequest"

    private let session: WCSession
    private let lock = NSLock()
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
        guard session.activationState == .activated, session.isReachable else { return nil }
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
        guard activationState == .activated else { return }
        lock.withLock { onActivated }?()
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

    #if os(iOS)
    public func sessionDidBecomeInactive(_ session: WCSession) {}

    /// The user switched watches: reactivate for the new one.
    public func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }
    #endif
}
#endif
