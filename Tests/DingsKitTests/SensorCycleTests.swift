import Testing
@testable import DingsKit

/// Exercises the generic `SensorCycle` mechanism over opaque `SensorType`
/// values. Uses raw literals rather than LuftDings' named constants (those live
/// in the consuming app), since the cycle only cares about identity and order.
@Suite struct SensorCycleTests {
    let radon = SensorType("radonShortTermAvg")
    let co2 = SensorType("co2")
    let voc = SensorType("voc")
    let temp = SensorType("temp")
    let pm25 = SensorType("pm25")

    var list: [SensorType] { [radon, co2, voc, temp] }

    @Test func upAdvancesToTheNext() {
        #expect(SensorCycle.next(in: list, current: co2, direction: .up) == voc)
    }

    @Test func downGoesToThePrevious() {
        #expect(SensorCycle.next(in: list, current: co2, direction: .down) == radon)
    }

    @Test func upWrapsPastTheEndToTheStart() {
        #expect(SensorCycle.next(in: list, current: temp, direction: .up) == radon)
    }

    @Test func downWrapsPastTheStartToTheEnd() {
        #expect(SensorCycle.next(in: list, current: radon, direction: .down) == temp)
    }

    @Test func singleElementListStaysPut() {
        #expect(SensorCycle.next(in: [co2], current: co2, direction: .up) == co2)
    }

    @Test func emptyListReturnsNil() {
        #expect(SensorCycle.next(in: [], current: co2, direction: .up) == nil)
    }

    @Test func missingCurrentStartsAtAnEnd() {
        // current not in the list: up starts at first, down at last.
        #expect(SensorCycle.next(in: list, current: nil, direction: .up) == radon)
        #expect(SensorCycle.next(in: list, current: pm25, direction: .down) == temp)
    }
}
