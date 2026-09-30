import SwiftUI
import DingsKit

/// Supplies the words and colors `ReadingsListView` renders for one app's
/// readings screen. DingsKitUI has no vocabulary of its own for what a
/// device or a reading *is* (a sensor, a person, a patient); every
/// user-facing word for a reading comes from a conformance to this.
///
/// Every per-reading method also takes the `DeviceReadings` the reading
/// belongs to. A reading on its own (`SensorReading`) carries no device or
/// patient id, but rendering it can still depend on which device, or which
/// person, it came from: ZuckerDings must rate a glucose value against that
/// specific person's own target range, not a shared or previously-seen one.
/// Passing the device explicitly, at the call site that already has it, is
/// what lets a conformance answer that per-reading without caching device
/// context as mutable state and relying on some assumed call order to keep
/// it correct. A stateful, order-dependent presenter is exactly the failure
/// mode this parameter exists to rule out.
public protocol ReadingsPresenting {
    /// Section header for one device. LuftDings uses its caption, ZuckerDings
    /// the person's full name.
    func caption(for device: DeviceReadings) -> String
    /// The value plus its unit, already formatted for display.
    func valueText(for reading: SensorReading, in device: DeviceReadings) -> String
    /// The rating word shown under the value, or "" when the reading carries
    /// none. Deliberately not `QualityRating.displayText`: a glucose app must
    /// say "Low", not "Fair", and "Fair" cannot tell a hypo from a hyper.
    func ratingText(for reading: SensorReading, in device: DeviceReadings) -> String
    /// Tint for the row's icon, and for the rating word when there is one.
    func tint(for reading: SensorReading, in device: DeviceReadings) -> Color
    /// SF Symbol name for the row's icon. Defaults to the reading's own
    /// sensor-type icon (see the extension below); override when a reading's
    /// icon depends on its *value*, not just its type, e.g. ZuckerDings'
    /// trend arrow, which points in a different direction per `TrendArrow`
    /// value rather than using one fixed glyph for every `.glucoseTrend`.
    func iconName(for reading: SensorReading, in device: DeviceReadings) -> String
    /// What VoiceOver reads for the whole row, in one pass.
    func accessibilityText(for reading: SensorReading, in device: DeviceReadings) -> String
    /// Copy shown in place of reading rows when a device has none right now
    /// (e.g. offline at the source). Both current screens say something here
    /// rather than rendering a bare card, since an empty card reads as a
    /// broken app.
    func noReadingsText(for device: DeviceReadings) -> String
}

public extension ReadingsPresenting {
    /// The reading's own sensor-type icon, right for every reading whose
    /// icon never varies within its type, which is every current reading
    /// except ZuckerDings' trend arrow.
    func iconName(for reading: SensorReading, in device: DeviceReadings) -> String {
        reading.type.symbolName
    }
}
