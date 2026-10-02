import Foundation

/// A bounded wait for a condition that somebody else reports changes to.
///
/// `WCSessionTransport` uses it to hold a request until the session is
/// activated and reachable: the delegate callbacks call `signal()`, each
/// waiter re-reads the condition, and a deadline ends the wait if it never
/// comes true. No polling.
///
/// Every waiter is resumed exactly once: whoever removes it from the table
/// (the first check, a signal, or the deadline) is the one that resumes it.
/// The condition is read and the continuation resumed outside the lock.
final class ReadinessGate: @unchecked Sendable {
    enum State: Sendable {
        /// Go ahead.
        case ready
        /// Not yet; a later signal may change that.
        case waiting
        /// It will not become ready: stop waiting now.
        case unavailable
    }

    private struct Waiter {
        let check: @Sendable () -> State
        let continuation: CheckedContinuation<Bool, Never>
        let deadline: Task<Void, Never>
    }

    private let lock = NSLock()
    private var waiters: [UUID: Waiter] = [:]

    /// Waits until `check` reports `.ready` (true), `.unavailable` (false),
    /// or `timeout` has passed (false). `check` runs once at the start and
    /// again on every `signal()`; it must be cheap and must not call back
    /// into this gate.
    func wait(timeout: Duration, check: @escaping @Sendable () -> State) async -> Bool {
        let id = UUID()
        return await withCheckedContinuation { continuation in
            lock.withLock {
                // Started under the lock, so even an immediate deadline finds
                // the waiter registered.
                let deadline = Task { [weak self] in
                    try? await Task.sleep(for: timeout)
                    self?.finish(id, ready: false)
                }
                waiters[id] = Waiter(check: check, continuation: continuation, deadline: deadline)
            }
            // Registered first, checked second: a signal in between is not lost.
            evaluate(id, check: check)
        }
    }

    /// The condition may have changed: let every waiter look again.
    func signal() {
        let pending = lock.withLock { waiters.mapValues(\.check) }
        for (id, check) in pending { evaluate(id, check: check) }
    }

    /// How many waits are in flight. For tests.
    var waiterCount: Int { lock.withLock { waiters.count } }

    private func evaluate(_ id: UUID, check: @Sendable () -> State) {
        switch check() {
        case .ready: finish(id, ready: true)
        case .unavailable: finish(id, ready: false)
        case .waiting: break
        }
    }

    private func finish(_ id: UUID, ready: Bool) {
        guard let waiter = lock.withLock({ waiters.removeValue(forKey: id) }) else { return }
        waiter.deadline.cancel()
        waiter.continuation.resume(returning: ready)
    }
}
