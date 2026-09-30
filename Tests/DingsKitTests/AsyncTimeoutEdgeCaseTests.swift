import Testing
import Foundation
@testable import DingsKit

/// `withTimeout` converts `seconds` to nanoseconds; inputs that `UInt64(_:)`
/// cannot represent used to trap. Non-positive and NaN deadlines time out at
/// once; infinite or huge ones never do.
@Suite struct AsyncTimeoutEdgeCaseTests {
    @Test(arguments: [0, -1, -.infinity, .nan, -.greatestFiniteMagnitude] as [TimeInterval])
    func nonPositiveOrNaNTimesOutImmediately(seconds: TimeInterval) async {
        let ran = PrivateFlag()
        await #expect(throws: TimeoutError.self) {
            try await withTimeout(seconds: seconds) {
                ran.set()
                return 1
            }
        }
        #expect(ran.value == false)
    }

    @Test(arguments: [.infinity, .greatestFiniteMagnitude, 1e300, 1e10] as [TimeInterval])
    func infiniteOrHugeNeverTimesOut(seconds: TimeInterval) async throws {
        let value = try await withTimeout(seconds: seconds) {
            try await Task.sleep(nanoseconds: 10_000_000)
            return 7
        }
        #expect(value == 7)
    }

    @Test func tinyPositiveStillTimesOutASlowOperation() async {
        await #expect(throws: TimeoutError.self) {
            try await withTimeout(seconds: 1e-9) {
                try await Task.sleep(nanoseconds: 2_000_000_000)
                return 1
            }
        }
    }
}

private final class PrivateFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var stored = false
    var value: Bool { lock.withLock { stored } }
    func set() { lock.withLock { stored = true } }
}
