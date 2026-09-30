# Contributing

Read [`AGENTS.md`](AGENTS.md) first. It is written for AI coding agents, and
it is the manual for people too: the architecture map, the hard constraints,
the provider recipe, and the pitfalls. Nothing in this file repeats it.

## Scope

DingsKit is not built speculatively. Features land when one of the apps built
on it needs them (see [`ROADMAP.md`](ROADMAP.md)). Fixes and doc improvements
are welcome any time; a new feature should come with the consumer that needs
it, or at least a description of it.

## Building and testing

Xcode is required (the Command Line Tools alone cannot compile the string
catalog). Then:

```sh
swift test
swiftlint          # brew install swiftlint
```

CI runs both, plus an iOS build of the UIKit-only views that `swift test` on
macOS skips, on pushes to `main` and on pull requests.

## Rules that will come up in review

- **Swift Testing** (`import Testing`, `@Test`, `#expect`), not XCTest. A suite
  that touches `Dings.config`, even indirectly, goes inside
  `extension GlobalConfig` (see `Tests/DingsKitTests/GlobalConfigSuite.swift`);
  `UserDefaults`-backed stores are tested with `InMemoryUserDefaults`.
- **No force-unwraps** in parsing or networking paths; `makeURL(_:)`, not
  `URL(string:)!`.
- **Raw values are wire format.** Never change a `Provider` or `SensorType`
  raw value; add a new constant.
- **DingsKitUI has no app vocabulary.** Every user-facing noun is a parameter
  or comes from a `ReadingsPresenting` conformance.
- **Shared UI copy goes through `coreLocalized`.** Add the string to
  `Sources/DingsKit/Resources/Localizable.xcstrings` and keep the German
  translation alongside the English. A test enforces both.
- **Every public type gets a doc comment** that says why it exists, not just
  what it is, and a line in `AGENTS.md`'s architecture map.
- **Update `CHANGELOG.md`** under the unreleased version for any public API
  change.

## Releasing

Tags are semver (`0.2.0`). `README.md`'s install snippet pins `from:` to the
latest tag; bump it in the same commit as the changelog entry.
