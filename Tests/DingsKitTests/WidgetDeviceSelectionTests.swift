import Testing
import Foundation
@testable import DingsKit

@Suite("Widget device selection")
struct WidgetDeviceSelectionTests {
    private func device(_ id: String, name: String) -> DeviceReadings {
        DeviceReadings(
            serialNumber: id, name: name, model: "Test Model",
            readings: [SensorReading(type: SensorType("value"), value: 1, unit: "u", quality: .good)],
            batteryPercentage: nil, recorded: nil, provider: Provider("test"))
    }

    private var two: [DeviceReadings] { [device("d1", name: "One"), device("d2", name: "Two")] }

    @Test func configuredMatchResolvesToThatDevice() {
        let resolution = WidgetDeviceSelection.resolve(configuredID: "d2", among: two)
        #expect(resolution.device?.serialNumber == "d2")
        #expect(resolution.state == .ready)
    }

    /// The safety rule: sharing revoked, or a replaced account, must never
    /// retarget a widget at a different device.
    @Test func configuredButMissingIsUnavailable() {
        let resolution = WidgetDeviceSelection.resolve(configuredID: "gone", among: two)
        #expect(resolution.state == .unavailable)
        #expect(resolution.device == nil)
    }

    @Test func unconfiguredWithExactlyOneResolvesToIt() {
        let resolution = WidgetDeviceSelection.resolve(configuredID: nil, among: [device("d1", name: "One")])
        #expect(resolution.device?.serialNumber == "d1")
        #expect(resolution.state == .ready)
    }

    /// Several devices and no configuration is a question for the user, not a
    /// guess: picking by position would make the widget switch devices
    /// whenever the provider reorders its response.
    @Test func unconfiguredWithSeveralNeedsChoice() {
        let resolution = WidgetDeviceSelection.resolve(configuredID: nil, among: two)
        #expect(resolution.state == .needsChoice)
        #expect(resolution.device == nil)
    }

    @Test func emptyCacheIsEmptyRegardlessOfConfiguration() {
        #expect(WidgetDeviceSelection.resolve(configuredID: nil, among: []).state == .empty)
        #expect(WidgetDeviceSelection.resolve(configuredID: "d1", among: []).state == .empty)
    }
}
