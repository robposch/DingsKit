import Testing
import Foundation
@testable import DingsKit

@Suite struct AsyncTimeoutTests {
    @Test func returnsValueWhenOperationFinishesInTime() async throws {
        let value = try await withTimeout(seconds: 10) { 42 }
        #expect(value == 42)
    }

    @Test func throwsTimeoutWhenOperationIsTooSlow() async {
        await #expect(throws: TimeoutError.self) {
            try await withTimeout(seconds: 0.01) {
                try await Task.sleep(nanoseconds: 5_000_000_000)
                return 0
            }
        }
    }

    @Test func propagatesOperationError() async {
        struct Boom: Error {}
        await #expect(throws: Boom.self) {
            try await withTimeout(seconds: 10) { throw Boom() }
        }
    }
}
