import Foundation

/// Per-app identity and policy for everything in the shared core: which App
/// Group and keychain items to use, how to log, how often to refresh, and
/// which providers/sensors exist. Consuming apps build one of these and call
/// `Dings.bootstrap(_:)` once at process start (app, widget extension, CLI).
public struct DingsConfig: Sendable {
    public var appGroupSuite: String
    public var keychainService: String
    public var keychainAccessGroup: String?
    public var logSubsystem: String
    public var backgroundTaskID: String
    public var refresh: RefreshPolicyValues
    public var providers: [ProviderSpec]
    public var sensors: [SensorDescriptor]
    /// Human-facing app name shown in shared UI (e.g. the provider setup form).
    public var appName: String
    /// Support address for beta-integration feedback. `nil` hides the note.
    public var supportEmail: String?
    /// Provider assigned to a cached `DeviceReadings` snapshot written before the
    /// `provider` key existed. `nil` means such a payload is undecodable (the
    /// generic default); an app with legacy snapshots names its original provider.
    public var legacyDecodeProvider: Provider?
    /// The app's first-use and About disclosure (disclaimer text, severity,
    /// legal links). Shared by DingsKitUI's `DisclaimerBox` and
    /// `AboutLegalSection` so onboarding and About cannot drift.
    public var disclosure: DisclosureContent
    /// Builds the `ReadingsRefresher` the shared tap-to-refresh widget intent
    /// (`RefreshReadingsIntent`) runs. `nil` falls back to a generic refresher
    /// over a plain `ConnectionsStore()` and `demoTransport()` below, which is
    /// correct once every provider is registry-driven. An app with its own
    /// `ConnectionsStore` variant or bespoke, non-registry client wiring
    /// (legacy providers with no `ProviderSpec`) supplies this so the shared
    /// intent's on-demand refresh matches its primary refresh pipeline
    /// exactly, not just the registry subset of it.
    public var makeRefresher: (@Sendable ((any ReadingsCache)?) -> ReadingsRefresher)?
    /// Demo-mode transport for the shared intent's generic fallback (consulted
    /// only when `makeRefresher` is `nil`), so a registry provider's own demo
    /// fixtures reach the widget's tap-to-refresh button in demo mode. `nil`
    /// yields `MockTransport()`, which 404s every route.
    public var demoTransport: (@Sendable () -> (any Transport)?)?

    public init(
        appGroupSuite: String,
        keychainService: String,
        keychainAccessGroup: String?,
        logSubsystem: String,
        backgroundTaskID: String,
        refresh: RefreshPolicyValues = RefreshPolicyValues(),
        providers: [ProviderSpec] = [],
        sensors: [SensorDescriptor] = [],
        appName: String = "App",
        supportEmail: String? = nil,
        legacyDecodeProvider: Provider? = nil,
        disclosure: DisclosureContent = DisclosureContent(disclaimer: "", severity: .info),
        makeRefresher: (@Sendable ((any ReadingsCache)?) -> ReadingsRefresher)? = nil,
        demoTransport: (@Sendable () -> (any Transport)?)? = nil
    ) {
        self.appGroupSuite = appGroupSuite
        self.keychainService = keychainService
        self.keychainAccessGroup = keychainAccessGroup
        self.logSubsystem = logSubsystem
        self.backgroundTaskID = backgroundTaskID
        self.refresh = refresh
        self.providers = providers
        self.sensors = sensors
        self.appName = appName
        self.supportEmail = supportEmail
        self.legacyDecodeProvider = legacyDecodeProvider
        self.disclosure = disclosure
        self.makeRefresher = makeRefresher
        self.demoTransport = demoTransport
    }
}

/// Process-wide access point. `bootstrap` is set-once: the first call wins,
/// later calls are ignored (so app + widget code paths can both call it
/// defensively). Reading `config` before any bootstrap traps with a clear
/// message: a silently wrong App Group would break widgets invisibly.
public enum Dings {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var stored: DingsConfig?

    public static func bootstrap(_ config: DingsConfig) {
        lock.lock(); defer { lock.unlock() }
        if stored == nil { stored = config }
    }

    public static var config: DingsConfig {
        lock.lock(); defer { lock.unlock() }
        guard let stored else {
            fatalError("Dings.bootstrap(_:) was never called in this process")
        }
        return stored
    }

    /// Test-only: replace the config regardless of prior bootstrap. Public
    /// (rather than internal) because `DingsKitTestSupport` and consuming
    /// apps' test targets call it; never call it from app code. Prefer
    /// `TestDings.bootstrap` in tests.
    public static func _resetForTesting(_ config: DingsConfig) {
        lock.lock(); defer { lock.unlock() }
        stored = config
    }
}

/// The timing values behind `RefreshPolicy`, overridable per app through
/// `DingsConfig.refresh`. `RefreshPolicy` documents what each one governs.
public struct RefreshPolicyValues: Sendable {
    public var interval: TimeInterval = 10 * 60
    public var widgetReloadInterval: TimeInterval = 15 * 60
    public var foregroundDedupe: TimeInterval = 30
    public var staleCueAfter: TimeInterval = 60 * 60
    public var deviceStaleCueAfter: TimeInterval = 3 * 60 * 60
    public init() {}
}

/// Display metadata for one sensor type: its label, an optional short label
/// for tight widget slots, and an SF Symbol. Registered in
/// `DingsConfig.sensors`; `SensorType` resolves its display properties here.
public struct SensorDescriptor: Sendable {
    public let type: SensorType
    public let label: String
    public let shortLabel: String?
    public let symbolName: String
    public init(type: SensorType, label: String, shortLabel: String? = nil, symbolName: String) {
        self.type = type
        self.label = label
        self.shortLabel = shortLabel
        self.symbolName = symbolName
    }
}
