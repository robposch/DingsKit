import Foundation

/// Thrown by `withTimeout(seconds:operation:)` when the operation outlasts the
/// deadline. Distinct type so callers can tell a timeout from the operation's
/// own errors (the background-refresh task records it as "timeout").
public struct TimeoutError: Error, Sendable, Equatable {
    public init() {}
}

/// Runs `operation`, throwing `TimeoutError` if it doesn't finish within
/// `seconds`. Used to bound the background-refresh fetch well under iOS's ~30s
/// background budget: a hung network call that overruns the budget gets the task
/// killed by the system, which penalizes future scheduling — far worse than a
/// clean timeout that still re-arms the next opportunity.
///
/// The loser task is cancelled, so a cooperating `operation` (e.g. `URLSession`)
/// stops promptly rather than running to completion in the background.
///
/// A zero, negative or NaN `seconds` times out immediately without running
/// `operation`; an infinite one, or one beyond about 292 years (`Int64.max`
/// nanoseconds), never times out.
public func withTimeout<T: Sendable>(
    seconds: TimeInterval,
    operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    // Written as `> 0` so NaN is rejected too; `seconds <= 0` would let it through.
    guard seconds > 0 else { throw TimeoutError() }
    let nanoseconds = seconds * 1_000_000_000
    // Capped at `Int64.max`, not `UInt64.max`: older runtimes compute the
    // sleep deadline as a signed value, so a sleep past `Int64.max`
    // nanoseconds overflows and returns at once. `Double(Int64.max)` rounds up
    // to 2^63, so anything strictly below it converts without trapping.
    guard nanoseconds < Double(Int64.max) else { return try await operation() }
    return try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(nanoseconds))
            throw TimeoutError()
        }
        defer { group.cancelAll() }
        guard let result = try await group.next() else { throw TimeoutError() }
        return result
    }
}
