#if canImport(UIKit) && !os(watchOS) // iOS and visionOS: watchOS has UIKit but lacks APIs this group of views uses
import SwiftUI
import DingsKit

/// The Settings About section: legal links, a report-a-problem mail link,
/// the disclaimer (footer style), and a version row. `extraFooter` carries
/// app-specific fine print (e.g. beta/credits) below the disclaimer.
///
/// Vendor/legal/external links belong in `DisclosureContent.legalLinks`,
/// rendered as body rows above; `extraFooter` is for non-link fine print only.
public struct AboutLegalSection<ExtraFooter: View>: View {
    private let extraFooter: ExtraFooter
    public init(@ViewBuilder extraFooter: () -> ExtraFooter = { EmptyView() }) {
        self.extraFooter = extraFooter()
    }

    private var disclosure: DisclosureContent { Dings.config.disclosure }

    private var supportMailURL: URL? {
        Dings.config.supportEmail.flatMap { URL(string: "mailto:\($0)") }
    }

    private static var versionString: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(v) (\(b))"
    }

    public var body: some View {
        Section {
            if let mail = supportMailURL {
                Link(destination: mail) { Label(coreLocalized("Report a problem"), systemImage: "envelope") }
            }
            LabeledContent(coreLocalized("Version"), value: Self.versionString)
            ForEach(disclosure.legalLinks) { link in
                Link(destination: link.url) {
                    HStack {
                        Text(link.title).foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: "arrow.up.right").font(.footnote).foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                    }
                }
            }
        } header: {
            Text(coreLocalized("About"))
        } footer: {
            VStack(alignment: .leading, spacing: 8) {
                DisclaimerBox(style: .footer)
                extraFooter
            }
        }
    }
}
#endif
