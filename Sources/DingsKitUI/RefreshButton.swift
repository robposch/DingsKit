import SwiftUI
import AppIntents
import DingsKit

/// Interactive tap-to-refresh (iOS 17) for a Home Screen / StandBy widget's
/// header row. The tap runs the shared `RefreshReadingsIntent` in the
/// background and reloads the widget: an on-demand refresh that does not wait
/// on WidgetKit's background reload budget. Both apps place this in the same
/// header position, ahead of the hero reading.
@available(visionOS 26, *) // runs `RefreshReadingsIntent`
public struct RefreshButton: View {
    public init() {}

    public var body: some View {
        Button(intent: RefreshReadingsIntent()) {
            Image(systemName: "arrow.clockwise")
                // The bare glyph is a ~15 pt target; pad the tappable area
                // without growing the visible icon.
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .buttonStyle(.plain)
        .accessibilityLabel(coreLocalized("Refresh readings"))
    }
}
