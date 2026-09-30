# AGENTS.md: building on DingsKit

This is the manual for AI coding agents building a widget app on DingsKit, or
adding a provider to one. Read it fully before writing code. Use the real type
names below; do not invent API. When in doubt, read the source in
`Sources/DingsKit` and `Sources/DingsKitUI`; every public type carries a doc
comment explaining why it exists.

DingsKit is infrastructure for client-side, bring-your-own-credentials iOS
widget apps. A user enters their own API credentials for a sensor cloud; the app
fetches readings directly from that cloud and shows them in home-screen and
lock-screen widgets. First consumer: LuftDings (air quality). Next: ZuckerDings
(glucose). Doc comments in the sources mention both by name as worked examples
of the two vocabularies the shared code has to stay neutral between.

## Prerequisites

Pure Swift package, no Xcode project of its own. You need **Xcode installed**
(for the Swift 6 toolchain and `xcstringstool`, which compiles the string
catalog): `swift build` / `swift test` work directly, no xcodegen, no signing,
no fastlane. The Command Line Tools alone are not enough. CI runs `swift test`,
an iOS build, and SwiftLint on macOS (`.github/workflows/ci.yml`).

Two ways to consume it:

- **As a dependency (the normal case).** Add the package by URL and tag, as in
  `README.md`. Nothing else is required; the repo does not need to be cloned.
- **As a sibling checkout (the author's own apps).** LuftDings and ZuckerDings
  reference DingsKit through a local SPM path (`../DingsKit`) so kit changes
  can be developed against a real consumer without tagging. If you are working
  in one of those repos, DingsKit must be cloned next to it; if you are
  working on DingsKit alone, or on any other app, the URL dependency is all
  you need.

## Architecture map

**Config bootstrap.** `DingsConfig` carries the per-app identity and policy: App
Group suite, keychain service and access group, log subsystem, background task
ID, `RefreshPolicyValues`, the registered `[ProviderSpec]` and
`[SensorDescriptor]`, plus `appName`, optional `supportEmail`,
`legacyDecodeProvider`, the app's `disclosure` (`DisclosureContent`), and two
optional hooks for the shared widget intent: `makeRefresher` (build the app's
own `ReadingsRefresher`; `nil` means a generic one over `ConnectionsStore()`)
and `demoTransport` (the app's demo fixtures; `nil` means an empty
`MockTransport()`). Each process (app, widget extension, CLI) calls
`Dings.bootstrap(_:)` exactly once at start; it is set-once (first call wins).
`Dings.config` traps if read before bootstrap, so a silently wrong App Group
cannot break widgets invisibly.

**Provider seam.** `Provider` is a string-backed, open struct; apps declare
constants via `extension Provider { static let x = Provider("x") }`. A
`ProviderSpec` is the whole registration for one provider: `provider`,
`displayName`, `detail`, `isBeta`, credential `fields` (`[CredentialFieldSpec]`:
`id`, `label`, `placeholder`, `isSecure`), `instructionSteps`,
`instructionsURL`, `instructionsLinkTitle`, and a `makeClient` factory
`(ProviderCredentials, Transport) -> any ProviderClient`. Optional extras:
`demoCredentials` (the bag handed to `makeClient` in demo mode) and five copy
overrides for the setup form (`setupIntro`, `credentialsHeader`,
`credentialsFooter`, `credentialsSourceHeader`, `credentialsSourceFooter`) for
providers whose credential is a login rather than a pasted key. Registered
specs live in `DingsConfig.providers`; read them via `ProviderSpec.all`,
`.verified`, `.beta`, `.spec(for:)`. A `ProviderClient` has one method,
`fetchAllReadings() async throws -> [DeviceReadings]`; conform to
`RateLimitReporting` as well if the API sends rate headers. Adding a provider is
adding a spec plus a client; no switch statements change.

**Credential validation and the setup model.** `ProviderCredentialValidating`
is the seam (`validate(provider:credentials:) async throws -> Int`, returning
the device count); `LiveProviderCredentialValidator` builds the client from the
registry and fetches once. `ProviderConnectionModel` (`@Observable`,
main-actor) drives one provider's setup form: `spec`, `values`, `state`
(`.empty`, `.validating`, `.invalid(String)`, `.connected(maskedID:)`),
`load()`, `validateAndSave(_:)`, `disconnect(_:)`, `incomplete`.

**Credentials.** `ProviderCredentials` is a `[String: String]` bag keyed by the
`CredentialFieldSpec.id`s, with a subscript that reads missing keys as `""`.
`ProviderCredentialStore` is the persistence seam;
`KeychainProviderCredentialStore` is the shipping implementation (account
`"<provider>-credentials"`, protection class from `KeychainSupport`).
`ConnectionsStore` is the facade over every provider's store:
`configuredProviders()`, `loadCredentials(_:)`, `saveCredentials(_:for:)`,
`clear(_:)`. Its no-arg init builds one keychain store per registered spec.
`FreshInstallGuard.run(connections:cache:marker:)` runs once at app start
(not from extensions) and wipes credentials that survived an uninstall, since
keychain items outlive the app and `UserDefaults` does not.

**Cache and App-Group stores.** `CachedReadings` is the non-secret snapshot the
app writes and the widget reads: `devices`, `rateLimitRemaining`, `fetchedAt`,
per-provider `providerFetchedAt`, `isDemo`; `fetchedAt(for:)` and
`removing(_:clearsRateLimit:)` are the helpers. It lives in the App Group
container, never the keychain. `ReadingsCache` is the seam;
`AppGroupReadingsCache` is `UserDefaults(suiteName:)`-backed and returns `nil`
init if the entitlement is missing. Four more small stores share the same
suite and the same `init?(suiteName:)` / `init(defaults:)` shape:
`DataModeStore` (`DataMode`: `.live` or `.demo`), `UnitPreferenceStore`
(`UnitSystem`; the per-sensor conversion table stays in the app),
`StepperSensorStore` (the sensor a "Switcher" widget currently shows), and
`BackgroundRunLog` (a 20-entry ring buffer of `RefreshRun`s, each stamped with
its `RefreshSource`: `.backgroundTask`, `.widgetTimeline`, or `.appForeground`).
`CacheFreshness.isStale(fetchedAt:now:maxAge:)` is the one staleness rule every
caller shares.

**Refresher.** `ReadingsRefresher.refresh()` fetches every configured provider
independently and is fail-soft: success replaces that provider's devices,
failure keeps its previous cached devices, `fetchedAt` advances when at least one
provider succeeds, and it throws only when all providers fail. A demo snapshot
never counts as previous data for a live refresh, and a provider that has never
fetched successfully gets no fetch stamp. It merges and
writes the snapshot when a cache is passed and returns a `ReadingsResult`
(`devices`, `rateLimitRemaining`, per-provider `outcomes` as
`[ProviderRefreshOutcome]`, `providerFetchedAt`, and an `outcomeSummary` line
for the run log). Init parameters: `connections`, `cache`, `transport`,
`dataModeStore` (when it reads `.demo`, no network is touched),
`clientOverrides` (bespoke clients that bypass the registry), `demoClients`,
and `demoTransport`. The refresher never imports WidgetKit; the caller invokes
`WidgetCenter.shared.reloadAllTimelines()` afterward. `RefreshReadingsIntent`
is the shared iOS 17 tap-to-refresh `AppIntent` for widgets: it runs the same
refresh, writes the cache, and reloads timelines; configure it through
`DingsConfig.makeRefresher` / `demoTransport`.

**Refresh policy.** `RefreshPolicy` exposes the timing floors from
`Dings.config.refresh` (`RefreshPolicyValues`): `interval` (unattended poll
floor), `widgetReloadInterval`, `foregroundDedupe` (user-initiated gap),
`staleCueAfter`, `deviceStaleCueAfter`. `RefreshPolicy.shouldRefresh(since:
now:minInterval:)` answers whether a fetch is due.

**Models.** `DeviceReadings` (`serialNumber`, `name`, `model`, `readings`,
`batteryPercentage`, `recorded`, `provider`) holds `SensorReading`s (`type`,
`value`, `unit`, `quality`; `displayUnit` normalizes the wire unit).
`SensorType` is string-backed like `Provider`; `init(apiValue:)` takes the
API's own name, and `label`, `shortLabel`, `symbolName` resolve through the
registered `SensorDescriptor`s (`type`, `label`, `shortLabel`, `symbolName`).
`QualityRating` (`.good`, `.fair`, `.poor`, `.unrated`) is the provider-neutral scale with `text` and
`displayText`.

**Networking.** `Transport` is the seam (`send(_:) async throws -> (Data,
HTTPURLResponse)`); `URLSessionTransport` is live. `MockTransport(routes:)` is
the demo-mode transport: a table of `HostRoutes` → `Route` (`Match`, deferred
`body`, `headers`), injected by the app because fixtures are provider-specific.
Build URLs with `makeURL(_:)`, which throws instead of force-unwrapping.
`withTimeout(seconds:operation:)` throws `TimeoutError` so a hung fetch never
overruns the background budget.

**Errors.** `DingsError` (`.storage`, `.cache`, `.timeout`,
`.missingCredentials`, `.network`) is thrown by the shared infrastructure.
`ProviderAPIError` (`.missingCredentials`, `.invalidCredentials(_:hint:)`,
`.network`, `.decoding`, `.http`, `.storage`, each tagged with the `Provider`)
is the one error type for registry-driven providers. Both conform to
`LocalizedError` with a `userMessage`, so `localizedDescription` is real copy.
Any bespoke provider error must do the same.

**Freshness.** `Freshness.parts(recorded:fetchedAt:)` decides which
timestamps a reading shows (`Kind.measured`, `Kind.synced`, each with a
localized `label` and a `symbolName`); `Freshness.shortAge(_:now:)` gives the
"3m" / "2h" form for accessory widgets.

**Widget rules.** `WidgetDeviceSelection.resolve(configuredID:among:)` picks
which cached device a widget instance renders and never substitutes another
device; its `Resolution` maps to a `WidgetContentState` (`.ready`,
`.needsChoice`, `.unavailable`, `.empty`) the view explains.
`SensorCycle.next(in:current:direction:)` (`CycleDirection.up` / `.down`) steps
a Switcher widget through a device's sensors, wrapping at both ends. Both are
pure so they are testable without WidgetKit.

**Disclosure.** `DisclosureContent` (`disclaimer`, `severity`
(`DisclaimerSeverity.info` / `.warning`), `legalLinks: [LegalLink]`) is the one
source for the first-use and About disclosure. `LegalLink(title:urlString:)` is
failable and rejects `mailto:`; support email belongs in
`DingsConfig.supportEmail`.

**Logging and localization.** `Log` exposes one `LogCategory` per area
(`app`, `credentials`, `client`, `token`, `net`, `cache`, `readings`,
`widget`) under `Dings.config.logSubsystem`; messages are public, so never log
a secret. `coreLocalized(_:comment:)` resolves a string against DingsKit's own
catalog; shared UI copy must go through it or it renders in English everywhere.

**UI product.** `DingsKitUI` carries no app vocabulary: what a "device" or a
"reading" is, and how the app names its widgets, arrive as parameters. The
views, by screen:

- *Setup.* `ProviderSetupView(model:onConnected:dismissesOnConnect:)` is the
  spec-driven credential form (pass `dismissesOnConnect: false` when
  `onConnected` keeps navigating on the same `NavigationPath`). `AutoFill`
  maps field position to `UITextContentType` so password managers work.
- *Onboarding.* `OnboardingPageView(title:subtitle:bullets:actionTitle:action:
  footnote:actionAccessibilityIdentifier:)` is the shared page chrome over
  `[OnboardingBullet]`. `HowDataWorksView(serviceName:actionTitle:action:)`
  explains the client-side-only consequences (no push, iOS sets the cadence,
  Measured and Synced can differ). `ConnectedSummaryView(title:subtitle:items:
  widgetHint:actionTitle:action:)` lists what was just connected as
  `[ConnectedSummaryItem]`. `DisclaimerBox(style:)` (`DisclaimerBoxStyle.prominent` or `.footer`) renders the
  disclosure on first use.
- *Readings screen.* `ReadingsListView(devices:providerFetchedAt:lastRefreshed:
  presenter:extraRows:)` renders per-device sections inside the caller's own
  `List`; all wording and tinting comes from the app's `ReadingsPresenting`
  conformance (`caption(for:)`, `valueText`, `ratingText`, `tint`, `iconName`,
  `accessibilityText`, `noReadingsText`). `ReadingsStateView(state:retry:)`
  covers `ReadingsScreenState.loading`, `.empty(title:systemImage:
  description:)`, and `.failed(message:)`. `RefreshErrorBanner(message:)` is
  the "we kept your old data" banner.
- *Time and freshness.* `FreshnessLine(recorded:fetchedAt:density:layout:
  ticking:)` renders `Freshness.parts` at `FreshnessDensity.full`, `.compact`,
  or `.minimal`, `FreshnessLayout.inline` or `.stacked`; app screens must pass
  `ticking: false`. `RelativeTimeText(_:)` and `PeriodicRelativeView` keep
  relative times honest on app screens on a ten-second cadence instead of
  SwiftUI's per-second self-ticking style, which caused a real hang.
- *Widgets.* `WidgetPlaceholderView(symbolName:title:hint:)` and
  `AccessoryPlaceholderView(symbolName:title:)` explain a non-ready
  `WidgetContentState`. `RefreshButton()` is the tap-to-refresh control that
  runs `RefreshReadingsIntent`.
- *Settings and About.* `AboutLegalSection(extraFooter:)` renders legal links,
  a report-a-problem mail link, the footer disclaimer, and the version row.
  `RefreshActivityView(runs:)` shows the `BackgroundRunLog`.
  `BackgroundDiagnostics.gather()` reports the OS conditions that silently
  block `BGAppRefreshTask` (background refresh status, Low Power Mode, pending
  request).

Widget timeline providers and widget views themselves are the consuming app's
job; keep them in the widget target.

**Test support.** `DingsKitTestSupport` provides `TestDings.bootstrap(
providers:sensors:appGroupSuite:legacyDecodeProvider:)` (installs a minimal
config so defaulted initializers work), `StubTransport` (answers every request
from one handler closure you supply, and records the URLs and auth headers it
saw), `FakeClock`, `InMemoryReadingsCache`,
`InMemoryProviderCredentialStore`, and `InMemoryUserDefaults` (hand it to any
`init(defaults:)` store; a real `UserDefaults(suiteName:)` leaves a plist in
`~/Library/Preferences` on every test run). Call `TestDings.bootstrap` at the
top of any test that touches `Dings.config`. The config is one value per
process, so suites that replace it must not run in parallel: in this package
they are nested in the serialized `GlobalConfig` suite
(`Tests/DingsKitTests/GlobalConfigSuite.swift`); do the same in an app's tests.

## Hard constraints

- **Client-side only. No backend, ever.** Credentials and API traffic never
  touch a server you control. This is architectural and legal, not a preference.
- **No force-unwraps in parsing or networking paths.** Surface errors to a
  visible state. Use `makeURL(_:)`, not `URL(string:)!`. SwiftLint's
  `force_unwrapping` is opt-in here for that reason.
- **Swift Testing**, not XCTest, for new tests (`import Testing`, `@Test`,
  `#expect`). See `Tests/DingsKitTests`.
- **Raw values are wire format.** `Provider.rawValue` and `SensorType.rawValue`
  are persisted in the keychain, the App Group cache, and widget configs. Once
  shipped, never change a raw value; add a new constant instead.
- **DingsKitUI has no app vocabulary.** Every user-facing noun ("device",
  "person", the widget names) is a parameter or comes from a `ReadingsPresenting`
  conformance. `HowDataWorksView` is the one deliberate exception, and even it
  only takes `serviceName`. If a shared view needs a word for what it shows,
  that word goes in the app.
- **Shared UI copy goes through `coreLocalized`.** A bare string literal in a
  DingsKitUI `Text` resolves against the host app's bundle, not the kit's
  catalog, so it renders in English unless every app re-translates it. The
  same goes for user-facing error messages thrown by the core.
  `LocalizationCatalogTests` fails if a `coreLocalized` key is missing from
  `Localizable.xcstrings` or lacks a German translation.
- **The cloud-API dependency must be disclosed** in onboarding and the store
  listing (EU/German consumer law). Do not bury it. `DisclosureContent` and
  `HowDataWorksView` exist for this.

## Provider recipe

To add a provider to an app, in the app target (not this package):

1. **Constant**: `extension Provider { static let foo = Provider("foo") }`.
2. **Spec**: a `ProviderSpec` with `fields`, `instructionSteps`,
   `instructionsURL`, and `makeClient`. Register it in the app's `DingsConfig`.
   If the credential is a login rather than a pasted key, set `setupIntro` and
   the `credentials*` copy overrides so the form does not say "paste".
3. **Client**: a type conforming to `ProviderClient`; build requests with the
   injected `Transport`, add `RateLimitReporting` if the API sends rate headers.
   Throw `ProviderAPIError`, with a recovery `hint` on `.invalidCredentials`.
4. **DTOs**: `Codable` structs matching the API response exactly. No
   force-unwraps; `decodeIfPresent` for optional fields.
5. **Mapper**: DTO to `[DeviceReadings]`; build `SensorReading`s with
   `SensorType(apiValue:)` and the API's own unit string (`displayUnit`
   normalizes it). Register any new `SensorType`s as `SensorDescriptor`s.
6. **Fixtures**: canned JSON responses for demo mode and tests, wired into the
   app's `MockTransport(routes:)` table and passed as `demoTransport`.
7. **Tests**: Swift Testing over the mapper and client using `StubTransport`
   and a fixture. Bootstrap with `TestDings.bootstrap(providers:sensors:)`.

Set `isBeta: false` only once someone has verified the readings against real
hardware; that one line promotes the provider out of the beta screen.

## Pitfalls

- **Keychain access group needs the team-ID prefix.** `keychainAccessGroup`
  must be `"<TEAMID>.<group>"` (e.g. `"ABCDE12345.io.example.app"`). Without the
  prefix `SecItem` calls fail with `-34018` (errSecMissingEntitlement).
- **Use `kSecAttrAccessibleAfterFirstUnlock`** for stored credentials. Widgets
  and background tasks read while the device is locked; the stricter
  `WhenUnlocked` class makes those reads fail. `KeychainSupport.accessibility`
  already encodes this; keep it.
- **App Group suite must match the entitlement.** `DingsConfig.appGroupSuite`
  has to equal the `com.apple.security.application-groups` value in *both* the
  app and the widget entitlements, or `AppGroupReadingsCache.init?` returns
  `nil` and the widget silently shows nothing.
- **BGTask ID must be registered.** `DingsConfig.backgroundTaskID` must appear
  in the app's `Info.plist` under `BGTaskSchedulerPermittedIdentifiers`, or
  `BGTaskScheduler` throws at registration.
- **WidgetKit budget is ~40 to 70 reloads/day.** Do not design for minute-level
  freshness. The app is the primary fetcher (it writes the cache and calls
  `reloadAllTimelines()`); the widget's own timeline cadence is a fallback.
  Always show a "last updated" timestamp; stale data is fine, silently stale is
  not.
- **`dismiss()` and a `NavigationPath` push race.** `ProviderSetupView`
  dismisses itself by default; if `onConnected` pushes the next step on the
  same path, pass `dismissesOnConnect: false` and pop it yourself, or the
  surviving destination renders blank.
- **Self-ticking relative text hangs app screens.** Use `RelativeTimeText` /
  `PeriodicRelativeView` (or `FreshnessLine` with `ticking: false`) in the app;
  widgets may keep `style: .relative` because their timeline already paces them.
- **The widget intent's title is localized by the app, not the kit.**
  AppIntents resolves intent metadata against the main bundle only, so
  `RefreshReadingsIntent`'s two strings ("Refresh readings", "Fetch the latest
  readings now.") must be translated in the widget target's own string
  catalog. Everything else in the kit comes from its own catalog.
- **Platforms.** iOS is the target. `ProviderSetupView`, `AutoFill`,
  `DisclaimerBox`, `AboutLegalSection`, `RefreshActivityView`, and
  `BackgroundDiagnostics` are UIKit-only and compile out on macOS and watchOS.
  `RefreshReadingsIntent` and `RefreshButton` are `@available(visionOS 26, *)`.
- **`BackgroundRunLog` is best-effort across processes.** Writes are serialized
  within a process; the app and the widget extension recording in the same
  instant can drop an entry. Do not add a file lock in the App Group container
  to fix it: iOS kills a process suspended while holding one (`0xdead10cc`).
