/// Which way the Switcher widget's arrows step through a device's sensors.
public enum CycleDirection: Sendable { case up, down }

/// Steps through an ordered sensor list, wrapping at both ends. Pure so the
/// Switcher widget's arrow logic is unit-tested without WidgetKit. The caller
/// supplies the ordered list of sensors the device actually reports.
public enum SensorCycle {
    /// The next sensor to show. `current` is what is on screen now; `nil` or a
    /// value absent from `available` steps from an end (up from the first, down
    /// from the last). Returns `nil` only for an empty list.
    public static func next(in available: [SensorType],
                            current: SensorType?,
                            direction: CycleDirection) -> SensorType? {
        guard !available.isEmpty else { return nil }
        guard let current, let index = available.firstIndex(of: current) else {
            return direction == .up ? available.first : available.last
        }
        let count = available.count
        let step = direction == .up ? index + 1 : index - 1 + count
        return available[step % count]
    }
}
