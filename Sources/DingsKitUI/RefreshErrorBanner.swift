import SwiftUI
import DingsKit

/// The "we kept your old data" banner: shown in place of an error screen when a
/// refresh fails but readings are already on screen.
///
/// Its own file, and its own type, so it can be rendered and measured in isolation
/// — the layout below is easy to get subtly wrong and hard to spot by eye.
public struct RefreshErrorBanner: View {
    let message: String

    public init(message: String) {
        self.message = message
    }

    public var body: some View {
        // Not `VStack { Label; Text }`: a Label's leading edge is its *icon*, so the
        // detail line aligned to the icon (9pt) while the headline aligned past it
        // (38pt), and the banner read as two ragged columns. Owning the icon here
        // puts both lines in one text column, with the icon on the first line's
        // baseline rather than centered against a two-line block.
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            // Decorative: the combined element below already reads both lines, and
            // the headline says what the glyph says.
            Image(systemName: "wifi.exclamationmark")
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(coreLocalized("Couldn’t refresh. Showing older data"))
                    .font(.callout).foregroundStyle(.orange)
                Text(message)
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
