# DingsKit

Infrastructure for client-side, bring-your-own-credentials iOS widget apps:
keychain credential stores, an App Group readings cache, a fail-soft
multi-provider refresh engine, a spec-driven setup UI, and the shared
onboarding, readings, and widget views that go with them. Built to be driven
by AI coding agents. All network traffic is client-side; no backend ever sees
a user's credentials.

> **Working with an AI coding agent?** Point it at [`AGENTS.md`](AGENTS.md)
> first. It is the manual: architecture map, every public type, the hard
> constraints, the provider recipe, and the platform pitfalls. `CLAUDE.md`
> already does this for Claude Code.

## Status

Pre-1.0. The API can change between minor versions; every change is listed in
[`CHANGELOG.md`](CHANGELOG.md). DingsKit is extracted from shipping apps and
grows when one of them needs something (see [`ROADMAP.md`](ROADMAP.md)), so
expect it to be opinionated about that shape of app.

## Products

| Product | What it gives you |
| --- | --- |
| `DingsKit` | Core: `Dings.bootstrap` / `DingsConfig`, `Provider` / `SensorType` registries, `ProviderSpec` + `ProviderClient`, keychain credential stores and `ConnectionsStore`, `AppGroupReadingsCache` and the other App Group stores (`DataModeStore`, `UnitPreferenceStore`, `StepperSensorStore`, `BackgroundRunLog`), `ReadingsRefresher` + `RefreshReadingsIntent`, `RefreshPolicy`, `Freshness`, widget rules (`WidgetDeviceSelection`, `SensorCycle`), `DisclosureContent`, `FreshInstallGuard`, `MockTransport`, `Log`. |
| `DingsKitUI` | SwiftUI: `ProviderSetupView` (spec-driven credential form), onboarding (`OnboardingPageView`, `HowDataWorksView`, `ConnectedSummaryView`, `DisclaimerBox`), readings screen (`ReadingsListView` + `ReadingsPresenting`, `ReadingsStateView`, `RefreshErrorBanner`), freshness and time (`FreshnessLine`, `RelativeTimeText`), widget chrome (`WidgetPlaceholderView`, `AccessoryPlaceholderView`, `RefreshButton`), Settings (`AboutLegalSection`, `RefreshActivityView`, `BackgroundDiagnostics`). |
| `DingsKitTestSupport` | `TestDings.bootstrap`, `StubTransport`, `FakeClock`, `InMemoryReadingsCache`, `InMemoryProviderCredentialStore`, `InMemoryUserDefaults`. |

## Requirements

iOS 17, macOS 14, watchOS 10, visionOS 1. Swift 6. Building the package itself
needs Xcode (the Command Line Tools alone lack `xcstringstool`).

iOS is the platform the kit is built for and the only one the apps ship on.
The core builds everywhere. In `DingsKitUI`, the setup form, the About and
disclaimer views, the refresh log and the background diagnostics are UIKit-only
(iOS and visionOS); macOS and watchOS get the rest. `RefreshReadingsIntent` and
`RefreshButton` need visionOS 26 on visionOS.

## Install

Swift Package Manager. Add the package and depend on the products you need:

```swift
.package(url: "https://github.com/robposch/DingsKit.git", from: "0.2.0"),
```

```swift
.target(name: "MyApp", dependencies: [
    .product(name: "DingsKit", package: "DingsKit"),
    .product(name: "DingsKitUI", package: "DingsKit"),
]),
```

## Quick start

Bootstrap once per process (app, widget extension, CLI), before any other core
call. The keychain access group must carry your team-ID prefix (see AGENTS.md).

```swift
import DingsKit

extension Provider { static let awair = Provider("awair") }

let awairSpec = ProviderSpec(
    provider: .awair,
    displayName: "Awair",
    detail: "CO₂, VOC, PM for indoor air quality",
    isBeta: true,
    fields: [
        CredentialFieldSpec(id: "token", label: "Access Token", placeholder: "eyJ…"),
    ],
    instructionSteps: [
        "Sign in at developer.getawair.com.",
        "Create a token and paste it here.",
    ],
    instructionsURL: "https://developer.getawair.com",
    instructionsLinkTitle: "Open Awair developer console",
    makeClient: { credentials, transport in
        AwairClient(token: credentials["token"], transport: transport)
    }
)

Dings.bootstrap(DingsConfig(
    appGroupSuite: "group.io.example.myapp.shared",
    keychainService: "io.example.myapp",
    keychainAccessGroup: "ABCDE12345.io.example.myapp",
    logSubsystem: "io.example.myapp",
    backgroundTaskID: "io.example.myapp.refresh",
    providers: [awairSpec],
    sensors: [
        SensorDescriptor(type: SensorType("co2"), label: "CO₂", symbolName: "carbon.dioxide.cloud"),
    ],
    appName: "MyApp",
    disclosure: DisclosureContent(
        disclaimer: "MyApp reads your devices through the Awair cloud API using credentials you create.",
        severity: .info
    )
))
```

Your client conforms to `ProviderClient`:

```swift
struct AwairClient: ProviderClient {
    let token: String
    let transport: Transport
    func fetchAllReadings() async throws -> [DeviceReadings] { /* fetch + map */ }
}
```

Then refresh and cache in one call:

```swift
let refresher = ReadingsRefresher(
    connections: ConnectionsStore(),
    cache: AppGroupReadingsCache()
)
let result = try await refresher.refresh()
```

Present the setup form with `ProviderSetupView(model:)` from `DingsKitUI`.

DingsKit ships no provider clients. The Awair example above is illustrative:
your app talks to a third-party API with your users' own credentials, so
complying with that API's terms of use is your app's responsibility.

## Built with DingsKit

- [**LuftDings**](https://luftdings.poschenrieder.io/): air-quality widgets.
- [**ZuckerDings**](https://zuckerdings.poschenrieder.io/): glucose widgets
  (coming soon).

Both apps are closed source; DingsKit is the part they share.

## Docs

- [`AGENTS.md`](AGENTS.md): the manual for agents (and people) building apps on
  DingsKit. Read it before adding a provider or starting an app.
- [`CHANGELOG.md`](CHANGELOG.md), [`ROADMAP.md`](ROADMAP.md),
  [`CONTRIBUTING.md`](CONTRIBUTING.md), [`SECURITY.md`](SECURITY.md).

## License

MIT. See `LICENSE`. Copyright (c) 2026 Robert Poschenrieder.

DingsKit is not affiliated with or endorsed by any sensor or device vendor.
Product and company names used in examples and comments are trademarks of
their respective owners.
