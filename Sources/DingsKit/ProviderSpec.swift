import Foundation

/// One credential input field on a provider's setup form (label, placeholder,
/// secure-entry flag). IDs are the keys under which values land in
/// `ProviderCredentials.fields`, so they must stay stable across releases.
public struct CredentialFieldSpec: Sendable, Equatable, Identifiable {
    public let id: String
    public let label: String
    public let placeholder: String
    public let isSecure: Bool

    public init(id: String, label: String, placeholder: String = "", isSecure: Bool = true) {
        self.id = id
        self.label = label
        self.placeholder = placeholder
        self.isSecure = isSecure
    }
}

/// Everything the app needs to offer a registry-driven provider: row copy for
/// the chooser, credential fields for the generic setup form, key-creation
/// steps, and a client factory for the refresh pipeline. Adding a provider =
/// adding one spec here plus its client/DTOs/mapper — no new switches in the
/// store, refresher, or views.
public struct ProviderSpec: Sendable, Identifiable {
    public let provider: Provider
    /// Human-facing service name (e.g. a vendor's brand name). Resolved first by
    /// `Provider.displayName`.
    public let displayName: String
    /// Row subtitle in the provider chooser ("CO₂, VOC, PM — indoor air quality").
    public let detail: String
    /// Beta = we could not verify against real hardware yet. Surfaced as a
    /// badge in the chooser and a "help us verify" note on the setup form.
    public let isBeta: Bool
    public let fields: [CredentialFieldSpec]
    /// Short numbered steps to create the credentials, shown on the setup form.
    public let instructionSteps: [String]
    /// The vendor page where those credentials are created.
    public let instructionsURL: String
    /// Label for the button that opens `instructionsURL`.
    public let instructionsLinkTitle: String
    /// Factory for the refresh pipeline and the live credential validator.
    public let makeClient: @Sendable (ProviderCredentials, Transport) -> any ProviderClient
    /// Credentials handed to `makeClient` in demo mode (with `MockTransport`).
    /// Empty works for most providers; override when the client would
    /// otherwise hit a side-effecting path (e.g. a provider's token refresh
    /// persists to the keychain, so its demo bag carries a pre-cached token).
    public let demoCredentials: ProviderCredentials

    /// Continuation of the sentence "`{appName}` ..." on the setup form,
    /// naming what is read and what kind of credential this is (e.g. "reads
    /// your devices using your own free Acme API credentials. You
    /// create them once in your Acme account."). Supplied per provider
    /// rather than assumed by the shared setup view: the shared view has no
    /// vocabulary of its own for what is being read (a device? a person who
    /// shares data with you?) or how the credential is obtained (an API key
    /// you create, or a login you already have). Defaults to the original
    /// API-key/device wording so providers that fit that model need no
    /// change.
    public let setupIntro: String
    /// Header above the credential entry fields. Defaults to "Paste your
    /// credentials"; override for a credential that is not normally
    /// copy-pasted, like a remembered login.
    public let credentialsHeader: String
    /// Footer below the credential entry fields. Defaults to "First time?
    /// Follow the steps below to create them."; override to match
    /// `credentialsHeader` when it no longer talks about "credentials" you
    /// paste.
    public let credentialsFooter: String
    /// Header above the link to where the credential comes from. Defaults to
    /// "Get your credentials"; override for a provider where nothing is
    /// freshly issued and the user is instead setting up or recalling an
    /// existing account.
    public let credentialsSourceHeader: String
    /// Footer below that link. Defaults to "Opens in Safari so you can
    /// switch back here to paste."; override to match `credentialsSourceHeader`.
    public let credentialsSourceFooter: String

    public init(
        provider: Provider,
        displayName: String,
        detail: String,
        isBeta: Bool,
        fields: [CredentialFieldSpec],
        instructionSteps: [String],
        instructionsURL: String,
        instructionsLinkTitle: String,
        makeClient: @escaping @Sendable (ProviderCredentials, Transport) -> any ProviderClient,
        demoCredentials: ProviderCredentials = ProviderCredentials(fields: [:]),
        setupIntro: String? = nil,
        credentialsHeader: String = coreLocalized("Paste your credentials"),
        credentialsFooter: String = coreLocalized("First time? Follow the steps below to create them."),
        credentialsSourceHeader: String = coreLocalized("Get your credentials"),
        credentialsSourceFooter: String = coreLocalized("Opens in Safari so you can switch back here to paste.")
    ) {
        self.provider = provider
        self.displayName = displayName
        self.detail = detail
        self.isBeta = isBeta
        self.fields = fields
        self.instructionSteps = instructionSteps
        self.instructionsURL = instructionsURL
        self.instructionsLinkTitle = instructionsLinkTitle
        self.makeClient = makeClient
        self.demoCredentials = demoCredentials
        self.setupIntro = setupIntro
            ?? coreLocalized("reads your devices using your own free \(displayName) API credentials. You create them once in your \(displayName) account.")
        self.credentialsHeader = credentialsHeader
        self.credentialsFooter = credentialsFooter
        self.credentialsSourceHeader = credentialsSourceHeader
        self.credentialsSourceFooter = credentialsSourceFooter
    }

    public var id: Provider { provider }

    /// All registry-driven providers, in chooser/refresh display order.
    /// A provider an app wires up without a spec (through
    /// `ReadingsRefresher`'s `clientOverrides` and its own setup view) is
    /// absent by design. Sourced from `Dings.config`, so a
    /// `Dings.bootstrap(_:)` call must precede any access.
    public static var all: [ProviderSpec] {
        Dings.config.providers
    }

    /// Hardware-verified registry providers, the ones an app lists in its
    /// main chooser.
    ///
    /// **Promoting a provider is one line:** set `isBeta: false` in its spec
    /// once someone has confirmed the readings against real hardware. It then
    /// leaves the beta screen, joins the supported list, and loses its badge. No
    /// view holds a hand-maintained list, so nothing else has to change.
    public static var verified: [ProviderSpec] {
        all.filter { !$0.isBeta }
    }

    /// Built from the vendor's API docs but never run against the real device.
    /// Shown on their own screen, which asks owners of that hardware to check the
    /// numbers. Fully usable: this is a statement about what we have confirmed,
    /// not a restriction on what the user can do.
    public static var beta: [ProviderSpec] {
        all.filter { $0.isBeta }
    }

    public static func spec(for provider: Provider) -> ProviderSpec? {
        all.first { $0.provider == provider }
    }
}
