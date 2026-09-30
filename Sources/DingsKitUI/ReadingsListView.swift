import SwiftUI
import DingsKit

/// Per-device sections, reading rows, freshness rows and a last-refresh
/// footer for a loaded readings screen, parameterized by a
/// `ReadingsPresenting` conformance for wording and tinting.
///
/// This is not itself a `List`: `Section` only means something inside a
/// `List` (or `Form`), so a caller places this directly inside its own
/// `List { ... }`, alongside whatever it needs above the device sections
/// (a demo banner, a stale-refresh banner). That keeps this view a drop-in
/// replacement for just the device-sections-plus-footer portion of a
/// screen, without this type having to also carry banner content it has no
/// vocabulary for.
public struct ReadingsListView<ExtraRows: View>: View {
    private let devices: [DeviceReadings]
    private let providerFetchedAt: [Provider: Date]
    private let lastRefreshed: Date?
    private let presenter: ReadingsPresenting
    private let extraRows: (DeviceReadings) -> ExtraRows

    /// - Parameter extraRows: Extra rows appended after a device's readings
    ///   and before its Measured/Synced rows (e.g. LuftDings' battery row).
    ///   Defaults to nothing; an `EmptyView` contributes no row and no extra
    ///   spacing or divider, so a caller with nothing to add (ZuckerDings)
    ///   need not pass anything.
    public init(
        devices: [DeviceReadings],
        providerFetchedAt: [Provider: Date],
        lastRefreshed: Date?,
        presenter: ReadingsPresenting,
        @ViewBuilder extraRows: @escaping (DeviceReadings) -> ExtraRows = { _ in EmptyView() }
    ) {
        self.devices = devices
        self.providerFetchedAt = providerFetchedAt
        self.lastRefreshed = lastRefreshed
        self.presenter = presenter
        self.extraRows = extraRows
    }

    public var body: some View {
        // Serial numbers are only unique within one provider.
        ForEach(devices, id: \.listID) { device in
            Section(presenter.caption(for: device)) {
                if device.readings.isEmpty {
                    noReadingsRow(device)
                }
                ForEach(IdentifiedReading.rows(for: device.readings)) { row in
                    readingRow(row.reading, in: device)
                }
                extraRows(device)
                if let recorded = device.recorded {
                    freshnessRow(label: Freshness.Kind.measured.label, date: recorded)
                }
                // Per-provider sync stamp: on a fail-soft refresh this
                // device's provider may be older than the run, so this shows
                // the honest per-service time rather than the overall
                // `lastRefreshed` moment.
                if let synced = providerFetchedAt[device.provider] {
                    freshnessRow(label: Freshness.Kind.synced.label, date: synced)
                }
            }
        }
        Section {
            if let lastRefreshed {
                HStack {
                    Text(coreLocalized("Last refresh"))
                    Spacer()
                    RelativeTimeText(lastRefreshed)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    @ViewBuilder
    private func readingRow(_ reading: SensorReading, in device: DeviceReadings) -> some View {
        let rating = presenter.ratingText(for: reading, in: device)
        HStack {
            Label {
                Text(reading.type.label)
            } icon: {
                Image(systemName: presenter.iconName(for: reading, in: device))
                    .foregroundStyle(presenter.tint(for: reading, in: device))
            }
            Spacer()
            // The rating also appears as a word, not just an icon tint: hue
            // alone is invisible to color-blind users.
            if rating.isEmpty {
                Text(presenter.valueText(for: reading, in: device)).foregroundStyle(.secondary)
            } else {
                VStack(alignment: .trailing, spacing: 1) {
                    Text(presenter.valueText(for: reading, in: device)).foregroundStyle(.secondary)
                    Text(rating)
                        .font(.caption2)
                        .foregroundStyle(presenter.tint(for: reading, in: device))
                }
            }
        }
        // One VoiceOver element per row, not a stop per label and a stop per
        // value. The presenter owns both the visible text above and this
        // spoken text, so the two can't drift the way a hand-rolled label
        // reconstructed independently of what's on screen could.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(presenter.accessibilityText(for: reading, in: device))
    }

    /// A listed device with no current reading (e.g. offline at the source)
    /// must say so: a bare, row-less card reads as "app broken". `Label`
    /// already merges its icon and text into one VoiceOver element, so no
    /// extra accessibility modifier is needed here.
    private func noReadingsRow(_ device: DeviceReadings) -> some View {
        Label {
            Text(presenter.noReadingsText(for: device))
                .font(.callout)
                .foregroundStyle(.secondary)
        } icon: {
            Image(systemName: "antenna.radiowaves.left.and.right.slash")
                .foregroundStyle(.orange)
        }
        .accessibilityIdentifier("readings.noData.\(device.serialNumber)")
    }

    /// A Measured or Synced row: a label on the left, a relative time on the
    /// right, tinted orange once it falls behind `RefreshPolicy.deviceStaleCueAfter`.
    /// Both the string and the staleness tint are recomputed together inside
    /// `PeriodicRelativeView`, so a row that has been sitting on screen long
    /// enough to cross the staleness threshold picks up the orange tint at
    /// the same moment its text keeps counting up, rather than only on the
    /// next state-driven re-render.
    private func freshnessRow(label: String, date: Date) -> some View {
        HStack {
            Text(label)
            Spacer()
            PeriodicRelativeView {
                let stale = Date().timeIntervalSince(date) > RefreshPolicy.deviceStaleCueAfter
                Text(date, format: .relative(presentation: .named))
                    .foregroundStyle(stale ? Color.orange : Color.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct DeviceListID: Hashable {
    let provider: Provider
    let serialNumber: String
}

private extension DeviceReadings {
    var listID: DeviceListID { DeviceListID(provider: provider, serialNumber: serialNumber) }
}

/// A reading row's identity. `type` alone repeats when a device reports two
/// readings of one type; the occurrence number keeps ids unique while staying
/// stable when readings of other types come and go.
private struct IdentifiedReading: Identifiable {
    struct RowID: Hashable {
        let type: SensorType
        let occurrence: Int
    }
    let id: RowID
    let reading: SensorReading

    static func rows(for readings: [SensorReading]) -> [IdentifiedReading] {
        var seen: [SensorType: Int] = [:]
        return readings.map { reading in
            let occurrence = seen[reading.type, default: 0]
            seen[reading.type] = occurrence + 1
            return IdentifiedReading(id: RowID(type: reading.type, occurrence: occurrence), reading: reading)
        }
    }
}
