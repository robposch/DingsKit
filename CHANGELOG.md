# Changelog

## Unreleased

### DingsKit

- `DingsConfig.keychainSyncedProviders`: providers whose credentials sync
  through iCloud Keychain. A device-only keychain item often does not come
  back after a restore onto a new device; a synced one does. Deleting a synced
  item deletes it on every device, so leave out providers whose stored
  credentials rotate. Empty by default, so nothing changes until an app opts in.
- `KeychainProviderCredentialStore` takes the setting (or an explicit
  `synchronizable:`); a synced store still reads and deletes a device-only item
  an earlier build saved. `moveToSynchronizableIfNeeded()` moves that item to
  iCloud Keychain, add first and delete second.
- `KeychainSupport.scoped(_:synchronizable:for:)` and
  `KeychainSupport.moveToSynchronizable(_:)`: the same for an app's own stores.
- `ConnectionsStore.credentialsLost(given:)`: live readings are cached but no
  provider has a key. An unreadable keychain (before the first unlock) does not
  count as lost.

## 0.3.0 - Apple Watch sync

The plumbing an Apple Watch app needs to fetch readings on its own. No raw
values changed.

### DingsKit

- `WatchSyncPayload`: a versioned snapshot of the user's credentials, unit
  system and data mode. `snapshot` builds it from the phone's stores and fails
  rather than send an empty payload when the keychain is unreadable; `apply`
  makes the watch's stores match it and reports which providers were removed.
  A provider whose store fails is skipped and reported in `failed`, so it
  cannot hold back the providers after it.
- `WatchSyncTransport`, `WatchSyncSender`, `WatchSyncReceiver`: the phone
  sends when its state changed and answers the watch's requests; the watch
  applies what arrives and reports real changes only.
- `WCSessionTransport`: the WatchConnectivity implementation (iOS and
  watchOS). Credentials travel as a user-info transfer, never as application
  context. `request()` waits up to five seconds for the session to activate
  and the counterpart to become reachable, so a request made at launch is not
  lost; a failed transfer is logged.
- `ConnectionsStore.providers`: every provider the store covers, configured or
  not.
- `DataMode` is `Codable`.
- `URLSessionTransport` defaults to an ephemeral session with no URL cache,
  cookie or credential storage and a 15-second request timeout. Responses
  used to be written to `Cache.db` keyed by full URL, which for some
  providers includes the API key; whatever an earlier build stored there is
  removed once.
- `Log.redactedPath(_:)`: request paths in logs keep their route but drop
  the query and shorten account, station and device identifiers.
- `TestScenario` and `TestScenarioStore`: deterministic data situations for
  UI tests, set with `--uitest-scenario` (a provider failing, all failing,
  an empty account, stale data, a removed item). Built from the app's own
  demo data and run through the same merge as a live refresh, so the app and
  its widgets behave as with real data gone wrong. Only consulted in debug
  builds.
- `decodingSummary(_:)`: one short phrase for a failed decode ("missing
  field ‘body’") instead of `DecodingError`'s multi-line dump.
- `WCSessionTransport` cancels credential transfers still queued for a
  watch that was unpaired or had the app removed.

### DingsKitUI

- `ProviderSetupView` hides a revealed secret again when the app leaves the
  foreground, so it is not captured in the app-switcher snapshot.
- `RefreshErrorBanner(message:title:)`: an optional headline replaces
  "Couldn’t refresh. Showing older data" where no older data is on screen.

### DingsKitTestSupport

- `FakeWatchSyncTransport`.

### DingsKitUITesting (new)

For UI test bundles only. Drives iOS the way a person does, so app UI tests
need not repeat it:

- `HomeScreen`: places an app's widget from the widget gallery, finds and
  removes placed widgets, clears widgets an interrupted run left behind.
- `PlacedWidget` and `WidgetEditor`: read what a widget shows, open iOS's
  widget editor, pick a field's value, open a list field's options, check
  what is offered, pick one.
- `SystemPrompts.dismissSavePassword(in:)`, including the iOS 27 dialog
  that ignores an element tap.
- `Screenshots.attach(_:to:)`.

## 0.2.0 - shared onboarding, readings, and widget layer

Everything LuftDings and ZuckerDings turned out to share beyond the refresh
core, lifted into the kit so the two apps cannot drift. No raw values changed.

### DingsKit

- `DisclosureContent`, `LegalLink`, `DisclaimerSeverity`: one source for the
  first-use and About disclosure, carried on `DingsConfig.disclosure`.
- `FreshInstallGuard`: wipes keychain credentials that survived an uninstall.
- `RefreshReadingsIntent`: shared iOS 17 tap-to-refresh widget intent, wired
  through the new `DingsConfig.makeRefresher` and `DingsConfig.demoTransport`
  hooks.
- `WidgetDeviceSelection` and `WidgetContentState`: the rule for which cached
  device a widget instance renders, never substituting another device.
- `SensorCycle` / `CycleDirection` and `StepperSensorStore`: Switcher-widget
  sensor stepping and its App Group persistence.
- `BackgroundRunLog`, `RefreshRun`, `RefreshSource`: a durable ring buffer of
  recent refresh runs shared by app and widget.
- `Freshness.Kind.symbolName` and `Freshness.shortAge(_:now:)` for compact
  freshness rendering; `Freshness.Kind.label` is localized.
- `ProviderSpec` gains `demoCredentials`, `setupIntro`, and the
  `credentialsHeader` / `credentialsFooter` / `credentialsSourceHeader` /
  `credentialsSourceFooter` copy overrides for providers whose credential is a
  login rather than a pasted key.
- `ProviderConnectionModel` surfaces the provider's own error copy instead of
  "Unexpected error".
- `coreLocalized` is public so `DingsKitUI` copy resolves against the kit's
  string catalog.
- Removed the `SensorType.other` shim; doc comments are vendor-neutral.
- Every user-facing string the core produces (error messages, setup-form
  defaults) is in the kit's catalog with a German translation.
- Fixes:
  - `ReadingsRefresher` no longer carries demo devices, rate limits, or fetch
    stamps into a live snapshot after a demo-to-live switch.
  - A provider that has never fetched successfully gets no fetch stamp when it
    fails, instead of inheriting the snapshot's.
  - `withTimeout` no longer traps on a negative, NaN, or infinite duration.
  - `BackgroundRunLog.record` and `clear` are serialized within a process.
  - `Provider.legacyDisplayNames` is lock-protected.
  - `makeURL` leaves the query string out of its error message, and the
    refresher logs device serials masked.
  - A fallback `SensorType.shortLabel` no longer ends in a space.
- The package now builds on every declared platform: `RefreshReadingsIntent`
  is `@available(visionOS 26, *)`.

### DingsKitUI

- Onboarding: `OnboardingPageView` + `OnboardingBullet` (shared page chrome),
  `HowDataWorksView` (why there is no push and why Measured and Synced can
  differ), `ConnectedSummaryView` + `ConnectedSummaryItem` (what was just
  connected), `DisclaimerBox` (`.prominent` / `.footer`).
- Readings screen: `ReadingsListView` driven by a `ReadingsPresenting`
  conformance (every per-reading call receives its `DeviceReadings`, so a
  reading's icon and rating can depend on its value and its device), and
  `ReadingsStateView` over `ReadingsScreenState`.
- Freshness and time: `FreshnessLine` (`FreshnessDensity`, `FreshnessLayout`,
  `ticking:`), `RelativeTimeText` and `PeriodicRelativeView` (ten-second
  cadence instead of SwiftUI's per-second self-ticking style).
- Widgets: `WidgetPlaceholderView`, `AccessoryPlaceholderView`,
  `RefreshButton`.
- Settings: `AboutLegalSection`, `RefreshActivityView`.
- `ProviderSetupView` gains `dismissesOnConnect:` to avoid the `dismiss()` +
  `NavigationPath` push race; setup copy is provider-generic; German bullet
  fix.
- All shared copy resolves against the kit's own catalog, so an app no longer
  has to re-translate the setup form, About section, disclaimer, refresh
  banner, or diagnostics labels. The one exception is
  `RefreshReadingsIntent`'s title and description, which AppIntents reads from
  the app's bundle.
- Fixes: `FreshnessLine` glyphs align in one column; `ReadingsListView` and
  `OnboardingPageView` no longer produce duplicate `ForEach` ids (two devices
  with one serial across providers, two readings of one type, two identical
  bullets).
- The UIKit-only views compile out on watchOS as well as macOS;
  `RefreshButton` is `@available(visionOS 26, *)`.
- `RefreshActivityView`'s `runs` binding is no longer a public property
  (`init(runs:)` is unchanged).

### DingsKitTestSupport

- `InMemoryUserDefaults`: a `UserDefaults` that never touches disk, for
  testing the App Group stores without leaving plists behind.

### Docs and tooling

- `AGENTS.md` covers every public type, the two ways to consume the package,
  and the new pitfalls. `README.md` and `CONTRIBUTING.md` point agents at it.
- Install URL points at the real repo slug.
- Tests grew from 50 to 128, including the first coverage of
  `ReadingsRefresher`, and a test that fails when a `coreLocalized` key is
  missing from the catalog or untranslated.
- CI also builds for iOS, where the UIKit-only views compile. `SECURITY.md`
  added.

## 0.1.0 - initial extraction from LuftDings

First release. Extracted the reusable infrastructure from the LuftDings app:

- `Dings.bootstrap(DingsConfig)` per-process configuration (App Group, keychain,
  logging, refresh policy, provider and sensor registries).
- String-backed, extensible `Provider` and `SensorType` with a
  `SensorDescriptor` display registry.
- Spec-driven provider registry: `ProviderSpec`, `CredentialFieldSpec`,
  `ProviderClient`, and live credential validation.
- Credential storage: `ProviderCredentials`, `ProviderCredentialStore`,
  `KeychainProviderCredentialStore`, and the `ConnectionsStore` facade.
- App Group readings cache: `CachedReadings`, `ReadingsCache`,
  `AppGroupReadingsCache`.
- Fail-soft multi-provider refresh engine: `ReadingsRefresher` with
  `clientOverrides`, `demoClients`, and `RateLimitReporting`.
- Refresh-policy plumbing: `RefreshPolicy` and `RefreshPolicyValues`.
- `DingsKitUI`: `ProviderSetupView`, `RefreshErrorBanner`,
  `BackgroundDiagnostics`.
- `DingsKitTestSupport`: `TestDings.bootstrap`, `StubTransport`, `FakeClock`,
  `InMemoryReadingsCache`, `InMemoryProviderCredentialStore`.
