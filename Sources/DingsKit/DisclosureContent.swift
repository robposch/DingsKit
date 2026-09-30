import Foundation

/// How loud a disclosure should read. `.warning` is for safety-relevant
/// dependencies (e.g. medical data via an unofficial interface); `.info` for
/// attribution/legal notes with no safety dimension.
public enum DisclaimerSeverity: Sendable, Equatable { case info, warning }

/// A titled external legal link. Failable so a malformed URL is dropped at
/// config-build time and never rendered.
///
/// Requires a scheme and a host, so `mailto:` links are rejected by design —
/// support email belongs in `DingsConfig.supportEmail`, not here.
public struct LegalLink: Identifiable, Equatable, Sendable {
    public let title: String
    public let url: URL
    public var id: String { url.absoluteString }

    public init?(title: String, urlString: String) {
        guard let url = URL(string: urlString), url.scheme != nil, url.host != nil else { return nil }
        self.title = title
        self.url = url
    }
}

/// The app's first-use and About disclosure, rendered by DingsKitUI's
/// `DisclaimerBox` and `AboutLegalSection`. One source for onboarding and
/// About so the two cannot drift.
public struct DisclosureContent: Sendable {
    public let disclaimer: String
    public let severity: DisclaimerSeverity
    public let legalLinks: [LegalLink]

    public init(disclaimer: String, severity: DisclaimerSeverity, legalLinks: [LegalLink] = []) {
        self.disclaimer = disclaimer
        self.severity = severity
        self.legalLinks = legalLinks
    }
}
