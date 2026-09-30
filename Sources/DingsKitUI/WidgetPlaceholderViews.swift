import SwiftUI

/// A widget that cannot show a reading, explaining why. Used for every
/// non-ready `WidgetContentState`.
///
/// Takes its copy as parameters rather than switching on the state itself:
/// "Choose a person" and "Choose a device" are app vocabulary, and DingsKitUI
/// is not allowed to know which app it is rendering for.
public struct WidgetPlaceholderView: View {
    private let symbolName: String
    private let title: String
    private let hint: String?

    public init(symbolName: String, title: String, hint: String? = nil) {
        self.symbolName = symbolName
        self.title = title
        self.hint = hint
    }

    public var body: some View {
        VStack(spacing: 6) {
            Image(systemName: symbolName)
                .font(.title2)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)   // the text below says it
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if let hint {
                Text(hint)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// The Lock Screen variant. Accessory families are too small for a hint line and
/// too narrow for a sentence, so this is a glyph over at most a couple of words.
public struct AccessoryPlaceholderView: View {
    private let symbolName: String
    private let title: String

    public init(symbolName: String, title: String) {
        self.symbolName = symbolName
        self.title = title
    }

    public var body: some View {
        VStack(spacing: 1) {
            Image(systemName: symbolName)
                .accessibilityHidden(true)
            Text(title)
                .font(.caption2)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
