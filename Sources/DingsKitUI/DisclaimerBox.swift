#if canImport(UIKit) && !os(watchOS) // iOS and visionOS: watchOS has UIKit but lacks APIs this group of views uses
import SwiftUI
import DingsKit

/// Where a `DisclaimerBox` appears: `prominent` for first use (boxed, tinted
/// by severity), `footer` for a compact Settings About footer.
public enum DisclaimerBoxStyle: Sendable { case prominent, footer }

/// Renders `Dings.config.disclosure` at first-use (`.prominent`, boxed and
/// tinted by severity) or in a Settings About footer (`.footer`, compact).
public struct DisclaimerBox: View {
    private let style: DisclaimerBoxStyle
    public init(style: DisclaimerBoxStyle) { self.style = style }

    private var disclosure: DisclosureContent { Dings.config.disclosure }

    public var body: some View {
        switch style {
        case .prominent: prominent
        case .footer:
            Text(disclosure.disclaimer)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var isWarning: Bool { disclosure.severity == .warning }

    private var prominent: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(isWarning ? coreLocalized("Before you connect") : coreLocalized("About this app"),
                  systemImage: isWarning ? "exclamationmark.triangle" : "info.circle")
                .font(.headline)
                .foregroundStyle(isWarning ? .orange : .secondary)
            Text(disclosure.disclaimer)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background((isWarning ? Color.orange : Color.secondary).opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }
}
#endif
