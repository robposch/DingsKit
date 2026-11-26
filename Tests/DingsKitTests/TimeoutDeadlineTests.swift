import Testing
import Foundation
@testable import DingsKit

/// `withTimeout` makes its deadline visible to the operation, so work that
/// must not be cut off halfway (a token exchange whose response carries a
/// single-use token) can decide not to start, or bound itself, instead of
/// running past the caller's budget.
@Suite struct TimeoutDeadlineTests {
    @Test func outsideATimeoutThereIsNoDeadline() {
        #expect(TimeoutDeadline.current == nil)
        #expect(TimeoutDeadline.remaining == nil)
    }

    @Test func theOperationSeesItsDeadline() async throws {
        let before = Date()
        let deadline = try await withTimeout(seconds: 5) { TimeoutDeadline.current }
        let seen = try #require(deadline)
        #expect(seen.timeIntervalSince(before) > 4.9 && seen.timeIntervalSince(before) <= 5.1)
    }

    /// A nested, shorter timeout wins; a nested, longer one cannot extend
    /// the outer deadline.
    @Test func theEarliestDeadlineWins() async throws {
        let inner = try await withTimeout(seconds: 5) {
            try await withTimeout(seconds: 1) { TimeoutDeadline.remaining }
        }
        let outer = try await withTimeout(seconds: 1) {
            try await withTimeout(seconds: 30) { TimeoutDeadline.remaining }
        }
        #expect(try #require(inner) <= 1)
        #expect(try #require(outer) <= 1)
    }

    /// Unstructured tasks started inside the operation inherit it.
    @Test func anUnstructuredTaskInsideSeesTheDeadline() async throws {
        let seen = try await withTimeout(seconds: 5) {
            await Task { TimeoutDeadline.current }.value
        }
        #expect(seen != nil)
    }
}
