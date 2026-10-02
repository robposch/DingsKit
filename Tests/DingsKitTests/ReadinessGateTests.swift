import Testing
import Foundation
@testable import DingsKit

/// A state the `@Sendable` check closures can share.
private final class StateBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: ReadinessGate.State
    private var reads = 0
    init(_ state: ReadinessGate.State) { stored = state }
    var state: ReadinessGate.State {
        get { lock.withLock { reads += 1; return stored } }
        set { lock.withLock { stored = newValue } }
    }
    var readCount: Int { lock.withLock { reads } }
}

@Suite struct ReadinessGateTests {
    @Test func returnsTrueAtOnceWhenAlreadyReady() async {
        let gate = ReadinessGate()
        let clock = ContinuousClock()
        let start = clock.now
        #expect(await gate.wait(timeout: .seconds(30)) { .ready } == true)
        #expect(clock.now - start < .seconds(5))
        #expect(gate.waiterCount == 0)
    }

    @Test func returnsFalseAtOnceWhenUnavailable() async {
        let gate = ReadinessGate()
        let clock = ContinuousClock()
        let start = clock.now
        #expect(await gate.wait(timeout: .seconds(30)) { .unavailable } == false)
        #expect(clock.now - start < .seconds(5))
        #expect(gate.waiterCount == 0)
    }

    @Test func resumesWhenASignalFindsItReady() async {
        let gate = ReadinessGate()
        let box = StateBox(.waiting)
        async let result = gate.wait(timeout: .seconds(30)) { box.state }
        while gate.waiterCount == 0 { await Task.yield() }

        // A signal that changes nothing keeps it waiting.
        gate.signal()
        #expect(gate.waiterCount == 1)

        box.state = .ready
        gate.signal()
        #expect(await result == true)
        #expect(gate.waiterCount == 0)
    }

    @Test func resumesFalseWhenASignalFindsItUnavailable() async {
        let gate = ReadinessGate()
        let box = StateBox(.waiting)
        async let result = gate.wait(timeout: .seconds(30)) { box.state }
        while gate.waiterCount == 0 { await Task.yield() }

        box.state = .unavailable
        gate.signal()
        #expect(await result == false)
    }

    @Test func timesOutWhenNeverReady() async {
        let gate = ReadinessGate()
        #expect(await gate.wait(timeout: .milliseconds(50)) { .waiting } == false)
        #expect(gate.waiterCount == 0)
    }

    @Test func aSignalWithNoWaiterIsHarmless() {
        let gate = ReadinessGate()
        gate.signal()
        #expect(gate.waiterCount == 0)
    }

    /// Each waiter's continuation is checked: a second resume would trap.
    @Test func resumesEveryWaiterExactlyOnceUnderConcurrentSignals() async {
        for _ in 0..<50 {
            let gate = ReadinessGate()
            let box = StateBox(.waiting)
            let results = await withTaskGroup(of: Bool.self, returning: [Bool].self) { group in
                for _ in 0..<8 {
                    group.addTask { await gate.wait(timeout: .seconds(30)) { box.state } }
                }
                while gate.waiterCount < 8 { await Task.yield() }
                box.state = .ready
                for _ in 0..<16 {
                    group.addTask { gate.signal(); return true }
                }
                var collected: [Bool] = []
                for await value in group { collected.append(value) }
                return collected
            }
            #expect(results.count == 24)
            #expect(results.allSatisfy { $0 })
            #expect(gate.waiterCount == 0)
        }
    }

    /// The deadline and a signal racing each other still resume once.
    @Test func resumesExactlyOnceWhenSignalRacesTheTimeout() async {
        for _ in 0..<100 {
            let gate = ReadinessGate()
            let box = StateBox(.waiting)
            async let result = gate.wait(timeout: .milliseconds(2)) { box.state }
            try? await Task.sleep(for: .milliseconds(2))
            box.state = .ready
            gate.signal()
            _ = await result
            #expect(gate.waiterCount == 0)
        }
    }
}
