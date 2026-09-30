# Changelog

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
