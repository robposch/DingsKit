import Testing

/// Parent suite for every test that reads or replaces the process-global
/// `Dings.config`.
///
/// `Dings.config` is one value per process, and `TestDings.bootstrap` (via
/// `Dings._resetForTesting`) overwrites it. Under Swift Testing's default
/// parallelism, two suites bootstrapping different configs would each see the
/// other's providers, sensors, or legacy-decode fallback mid-test.
///
/// The mechanism: `.serialized` on a suite applies recursively to every suite
/// nested inside it, so any suite declared in `extension GlobalConfig { ... }`
/// runs one test at a time with respect to all other such suites, whichever
/// file it lives in. Each test bootstraps the exact config it needs (usually in
/// its suite's `init`) and nothing else can replace it until the test finishes.
///
/// Rule for new tests: if a test touches `Dings.config` directly or indirectly
/// (`SensorType.label`, `Provider.displayName`, `ProviderSpec.all`,
/// `RefreshPolicy`'s defaults, `ReadingsRefresher`, or anything that logs,
/// since `Log.subsystem` reads the config), declare its suite inside
/// `extension GlobalConfig`. Suites that never touch it stay outside and keep
/// running in parallel.
@Suite(.serialized)
enum GlobalConfig {}
