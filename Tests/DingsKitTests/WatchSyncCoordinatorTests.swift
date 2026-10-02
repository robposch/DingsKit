import Testing
import Foundation
@testable import DingsKit
import DingsKitTestSupport

private func payload(_ token: String) -> WatchSyncPayload {
    WatchSyncPayload(
        credentials: ["p": ProviderCredentials(fields: ["token": token])],
        unitSystem: .metric, dataMode: .live)
}

private struct Boom: Error {}

/// A mutable box the `@Sendable` closures can share.
private final class Box<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Value
    init(_ value: Value) { stored = value }
    var value: Value {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }
    /// Read-modify-write as one step, for counters shared across tasks.
    func mutate(_ body: (inout Value) -> Void) {
        lock.withLock { body(&stored) }
    }
}

/// Wraps the fake and pauses briefly after each send, so a concurrent push can
/// slip in between a send and the sender recording it.
private final class SlowSendTransport: WatchSyncTransport, @unchecked Sendable {
    let inner = FakeWatchSyncTransport()
    var isCounterpartAvailable: Bool { inner.isCounterpartAvailable }
    func send(_ payload: WatchSyncPayload) throws {
        try inner.send(payload)
        Thread.sleep(forTimeInterval: Double.random(in: 0...0.0005))
    }
    func request() async -> WatchSyncPayload? { await inner.request() }
    func setHandlers(
        onActivated: @escaping @Sendable () -> Void,
        onReceive: @escaping @Sendable (WatchSyncPayload) -> Void,
        onRequest: @escaping @Sendable () -> WatchSyncPayload?
    ) {
        inner.setHandlers(onActivated: onActivated, onReceive: onReceive, onRequest: onRequest)
    }
}

// Both types log their error paths, and `Log` reads `Dings.config`, so these
// suites live inside GlobalConfig.
extension GlobalConfig {
    @Suite struct WatchSyncSenderTests {
        init() { TestDings.bootstrap() }

        @Test func pushesOnceAndSkipsAnUnchangedPayload() {
            let transport = FakeWatchSyncTransport()
            let sender = WatchSyncSender(transport: transport, makePayload: { payload("a") })

            #expect(sender.pushIfChanged() == true)
            #expect(sender.pushIfChanged() == false)
            #expect(transport.sent == [payload("a")])
        }

        @Test func pushesAgainAfterThePayloadChanges() {
            let transport = FakeWatchSyncTransport()
            let token = Box("a")
            let sender = WatchSyncSender(transport: transport, makePayload: { payload(token.value) })

            sender.pushIfChanged()
            token.value = "b"
            sender.pushIfChanged()

            #expect(transport.sent == [payload("a"), payload("b")])
        }

        @Test func doesNotSendWithoutACounterpart() {
            let transport = FakeWatchSyncTransport()
            transport.isCounterpartAvailable = false
            let sender = WatchSyncSender(transport: transport, makePayload: { payload("a") })

            #expect(sender.pushIfChanged() == false)
            #expect(transport.sent.isEmpty)
        }

        /// With no payload to build (keychain unreadable), nothing is sent.
        @Test func senderSkipsWhenPayloadCannotBeBuilt() {
            let transport = FakeWatchSyncTransport()
            let sender = WatchSyncSender(transport: transport, makePayload: { throw Boom() })

            #expect(sender.pushIfChanged() == false)
            #expect(transport.sent.isEmpty)
            #expect(transport.simulateRequest() == nil)
        }

        @Test func retriesAfterAFailedSend() {
            let transport = FakeWatchSyncTransport()
            transport.sendError = Boom()
            let sender = WatchSyncSender(transport: transport, makePayload: { payload("a") })

            #expect(sender.pushIfChanged() == false)
            transport.sendError = nil
            #expect(sender.pushIfChanged() == true)
            #expect(transport.sent == [payload("a")])
        }

        @Test func pushesWhenTheSessionActivates() {
            let transport = FakeWatchSyncTransport()
            let sender = WatchSyncSender(transport: transport, makePayload: { payload("a") })

            transport.simulateActivation()

            #expect(transport.sent == [payload("a")])
            withExtendedLifetime(sender) {}
        }

        @Test func answersARequestWithTheCurrentPayload() {
            let transport = FakeWatchSyncTransport()
            let sender = WatchSyncSender(transport: transport, makePayload: { payload("a") })

            #expect(transport.simulateRequest() == payload("a"))
            withExtendedLifetime(sender) {}
        }

        /// Interleaved pushes (main actor plus the session's activation
        /// callback) must never leave a stale payload as the last one sent.
        @Test func concurrentPushesEndOnTheLatestPayload() async {
            let transport = SlowSendTransport()
            let token = Box(0)
            let sender = WatchSyncSender(transport: transport, makePayload: {
                let built = payload("\(token.value)")
                // Let a newer build overtake this one before it is sent.
                Thread.sleep(forTimeInterval: Double.random(in: 0...0.0005))
                return built
            })

            var next = 0
            for _ in 1...50 {
                await withTaskGroup(of: Void.self) { group in
                    for _ in 1...8 {
                        next += 1
                        let value = next
                        group.addTask {
                            token.value = value
                            sender.pushIfChanged()
                        }
                    }
                }
                sender.pushIfChanged()

                #expect(transport.inner.sent.last == payload("\(token.value)"))
            }
        }
    }

    @Suite struct WatchSyncReceiverTests {
        init() { TestDings.bootstrap() }

        @Test func appliesAnIncomingPayloadAndNotifies() {
            let transport = FakeWatchSyncTransport()
            let applied = Box<[WatchSyncPayload]>([])
            let notified = Box<[WatchSyncPayload.Applied]>([])
            let receiver = WatchSyncReceiver(
                transport: transport,
                apply: { incoming in
                    applied.value.append(incoming)
                    return WatchSyncPayload.Applied(changed: true, removed: [Provider("gone")])
                },
                onApplied: { notified.value.append($0) })

            transport.simulateReceive(payload("a"))

            #expect(applied.value == [payload("a")])
            #expect(notified.value == [WatchSyncPayload.Applied(changed: true, removed: [Provider("gone")])])
            withExtendedLifetime(receiver) {}
        }

        /// A delivery that changes nothing must not trigger a refresh.
        @Test func receiverStaysQuietWhenNothingChanged() {
            let transport = FakeWatchSyncTransport()
            let notified = Box(0)
            let receiver = WatchSyncReceiver(
                transport: transport,
                apply: { _ in WatchSyncPayload.Applied(changed: false, removed: []) },
                onApplied: { _ in notified.value += 1 })

            transport.simulateReceive(payload("a"))

            #expect(notified.value == 0)
            withExtendedLifetime(receiver) {}
        }

        @Test func swallowsAnApplyFailure() {
            let transport = FakeWatchSyncTransport()
            let notified = Box(0)
            let receiver = WatchSyncReceiver(
                transport: transport,
                apply: { _ in throw Boom() },
                onApplied: { _ in notified.value += 1 })

            transport.simulateReceive(payload("a"))

            #expect(notified.value == 0)
            withExtendedLifetime(receiver) {}
        }

        @Test func requestAppliesTheReply() async {
            let transport = FakeWatchSyncTransport()
            transport.requestReply = payload("a")
            let applied = Box<[WatchSyncPayload]>([])
            let receiver = WatchSyncReceiver(
                transport: transport,
                apply: { incoming in
                    applied.value.append(incoming)
                    return WatchSyncPayload.Applied(changed: true, removed: [])
                },
                onApplied: { _ in })

            #expect(await receiver.requestFromPhone() == true)
            #expect(applied.value == [payload("a")])
        }

        @Test func requestReportsFalseWhenThePhoneIsUnreachable() async {
            let transport = FakeWatchSyncTransport()
            transport.requestReply = nil
            let receiver = WatchSyncReceiver(
                transport: transport,
                apply: { _ in WatchSyncPayload.Applied(changed: true, removed: []) },
                onApplied: { _ in })

            #expect(await receiver.requestFromPhone() == false)
        }

        /// Under concurrency: the same payload delivered from
        /// the session queue and a request at once refreshes only once.
        @Test func concurrentDuplicateDeliveriesNotifyOnce() async {
            let transport = FakeWatchSyncTransport()
            // Like `WatchSyncPayload.apply`: an unlocked load, compare, save.
            let stored = Box<WatchSyncPayload?>(nil)
            let notified = Box(0)
            let receiver = WatchSyncReceiver(
                transport: transport,
                apply: { incoming in
                    let changed = stored.value != incoming
                    Thread.sleep(forTimeInterval: 0.0001) // widen the load-to-save window
                    if changed { stored.value = incoming }
                    return WatchSyncPayload.Applied(changed: changed, removed: [])
                },
                onApplied: { _ in notified.mutate { $0 += 1 } })

            await withTaskGroup(of: Void.self) { group in
                for _ in 1...100 {
                    group.addTask { transport.simulateReceive(payload("a")) }
                }
            }

            #expect(notified.value == 1)
            withExtendedLifetime(receiver) {}
        }
    }
}
