import Foundation

/// What a widget timeline entry is actually carrying. `ready` means the entry's
/// own payload is populated; the other cases mean it is not, and say why, so the
/// view can explain itself instead of rendering an empty box.
public enum WidgetContentState: String, Equatable, Sendable, Codable {
    case ready, needsChoice, unavailable, empty
}

/// Which cached device a widget instance should render.
///
/// Lives in DingsKit rather than a widget target so the rules below are
/// unit-testable: widget extensions are not reachable from `swift test`.
public enum WidgetDeviceSelection {
    /// The outcome of `resolve(configuredID:among:)`: the device to render, or
    /// the reason there is none.
    public enum Resolution: Equatable, Sendable {
        case device(DeviceReadings)
        /// Several devices are cached and this instance was never configured.
        /// Picking for the user would mean the rendered device changes whenever
        /// the provider reorders its response, so we ask instead.
        case needsChoice
        /// A device was configured and is no longer in the cache. Never falls
        /// back to another device: showing one device's readings under another's
        /// name is the failure this whole rule exists to prevent.
        case unavailable
        /// Nothing has ever been cached, so the app has not connected yet.
        case empty

        public var state: WidgetContentState {
            switch self {
            case .device: return .ready
            case .needsChoice: return .needsChoice
            case .unavailable: return .unavailable
            case .empty: return .empty
            }
        }

        public var device: DeviceReadings? {
            if case .device(let device) = self { return device }
            return nil
        }
    }

    public static func resolve(
        configuredID: String?, among devices: [DeviceReadings]
    ) -> Resolution {
        guard !devices.isEmpty else { return .empty }
        guard let configuredID else {
            // One device needs no decision, so an unconfigured widget just works.
            guard devices.count == 1 else { return .needsChoice }
            return .device(devices[0])
        }
        guard let match = devices.first(where: { $0.serialNumber == configuredID }) else {
            return .unavailable
        }
        return .device(match)
    }
}
