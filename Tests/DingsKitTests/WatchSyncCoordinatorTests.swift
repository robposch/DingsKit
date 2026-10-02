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
}

// Neither type touches `Dings.config`, so this suite stays outside GlobalConfig.
@Suite struct WatchSyncSenderTests {
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

    /// Review Focus 1.
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
}

@Suite struct WatchSyncReceiverTests {
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

    /// Review Focus 4.
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
}
