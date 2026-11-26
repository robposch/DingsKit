import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Fetches the latest readings from every configured provider (both bespoke
/// and registry-driven) and, when a cache is provided, persists the merged
/// result so the widget extension can read it via the shared App Group.
///
/// Merge semantics:
/// - each configured provider is fetched independently;
/// - success **replaces** that provider's devices in the snapshot;
/// - failure **keeps** that provider's previous devices from the existing
///   cache (per-device `recorded` freshness cues communicate age); a demo
///   snapshot never counts as previous data for a live refresh;
/// - `fetchedAt` advances when ≥1 provider succeeds; `refresh()` throws only
///   when *all* configured providers fail;
/// - `providerFetchedAt` stamps each provider's last *successful* fetch — a
///   failed provider carries its previous stamp forward, so per-device
///   "Synced" cues reflect that provider, not the run.
///
/// Callers are responsible for any post-refresh actions (e.g. calling
/// `WidgetCenter.shared.reloadAllTimelines()`). This type must not import
/// WidgetKit so it remains usable in the app target, background extensions,
/// and the CLI.
public struct ReadingsRefresher: Sendable {

    /// Who asked for a refresh, which decides whether per-provider floors
    /// apply.
    public enum Trigger: Sendable, Equatable {
        /// The user asked (opening the app, pull-to-refresh, the widget's
        /// refresh button) or the connections changed: every configured
        /// provider is fetched.
        case onDemand
        /// A periodic tick, a widget timeline or a background task: a provider
        /// with its own floor (`RefreshPolicyValues.providerIntervals`) is
        /// left out while its last successful fetch is younger than
        /// `RefreshPolicy.interval(for:)`. Its devices and fetch stamp carry
        /// over, and its outcome is marked `notDue`.
        case unattended
    }

    private let connections: ConnectionsStore
    private let cache: (any ReadingsCache)?
    private let transport: Transport
    private let dataModeStore: DataModeStore?
    /// Per-provider client factories that bypass the registry — the seam apps
    /// use for providers with bespoke clients (a consuming app's hand-rolled providers).
    /// An override wins over any registered `ProviderSpec` for that provider.
    private let clientOverrides: [Provider: @Sendable (Transport) throws -> any ProviderClient]
    /// Demo-mode client factories, appended to the registry's demo pipeline.
    private let demoClients: [(Provider, @Sendable () throws -> any ProviderClient)]
    /// Transport feeding the registry providers' real clients during demo mode.
    /// The canned payloads are provider-specific and live with the consuming app,
    /// so the app passes its `MockTransport(routes:)`; the default empty
    /// `MockTransport()` 404s every route (fine when no registry provider needs demo).
    private let demoTransport: Transport
    /// A UI-test situation to serve instead of live or demo data; see
    /// `TestScenario`. `nil` outside UI tests, and always in release builds.
    private let testScenario: TestScenario?

    /// - Parameters:
    ///   - connections: Source of the user's own per-provider credentials.
    ///   - cache:     Optional destination for the fetched snapshot. Pass `nil`
    ///                to skip caching (e.g. during a dry-run or in tests that
    ///                only care about the return value). Also read back for the
    ///                keep-on-failure merge.
    ///   - transport: HTTP transport. Defaults to the live `URLSessionTransport`;
    ///                inject a `StubTransport` in tests.
    ///   - dataModeStore: Source of the live/demo mode. Defaults to the shared
    ///                App-Group store. When it resolves to `.demo`, `refresh()`
    ///                serves built-in demo data (from `demoClients` plus the
    ///                registry, no credentials or network) and stamps `isDemo`.
    ///   - clientOverrides: Bespoke client factories keyed by provider; an entry
    ///                takes precedence over that provider's registered spec.
    ///   - demoClients: Bespoke demo client factories, run before the registry's
    ///                demo pipeline (same fail-soft logging).
    public init(
        connections: ConnectionsStore,
        cache: (any ReadingsCache)?,
        transport: Transport = URLSessionTransport(),
        dataModeStore: DataModeStore? = DataModeStore(),
        clientOverrides: [Provider: @Sendable (Transport) throws -> any ProviderClient] = [:],
        demoClients: [(Provider, @Sendable () throws -> any ProviderClient)] = [],
        demoTransport: Transport = MockTransport(),
        testScenario: TestScenario? = TestScenarioStore.current
    ) {
        self.connections = connections
        self.cache = cache
        self.transport = transport
        self.dataModeStore = dataModeStore
        self.clientOverrides = clientOverrides
        self.demoClients = demoClients
        self.demoTransport = demoTransport
        self.testScenario = testScenario
    }

    /// The readings the last refresh cached, for an app to show at launch
    /// before its first refresh finishes. With them on screen, a first refresh
    /// that fails keeps them and reports the failure, as every later refresh
    /// does, instead of replacing them with an error while the widgets still
    /// show them.
    ///
    /// `nil` when nothing is cached, or when the cache belongs to the other
    /// mode (demo readings while live, or live readings in demo).
    public func cachedResult() -> ReadingsResult? {
        guard let cached = cache?.load(), !cached.devices.isEmpty else { return nil }
        let isDemo = (dataModeStore?.load() ?? .live) == .demo
        guard cached.isDemo == isDemo else { return nil }
        // Snapshots from before per-provider stamps carry none; the
        // snapshot's own time stands in, so "Synced" still shows.
        var stamps = cached.providerFetchedAt
        for provider in Set(cached.devices.map(\.provider)) where stamps[provider] == nil {
            stamps[provider] = cached.fetchedAt
        }
        return ReadingsResult(devices: cached.devices, rateLimitRemaining: cached.rateLimitRemaining,
                              providerFetchedAt: stamps)
    }

    /// Fetches fresh readings from every configured provider and writes the
    /// merged snapshot to the cache if one was supplied.
    ///
    /// - Throws: `DingsError.missingCredentials` when no provider is
    ///           configured. When *all* configured providers fail, the first
    ///           provider's error propagates (in configuration order).
    /// - Parameter trigger: `.unattended` lets providers with their own,
    ///           longer floor sit out a run (see `Trigger`). Demo mode and
    ///           test scenarios touch no network and ignore it. When every
    ///           configured provider sits out, nothing is fetched or written
    ///           and the cached readings come back.
    /// - Returns: The merged `ReadingsResult`, with a per-provider outcome list.
    @discardableResult
    public func refresh(_ trigger: Trigger = .onDemand) async throws -> ReadingsResult {
        if let testScenario {
            return try await refreshScenario(testScenario)
        }
        if (dataModeStore?.load() ?? .live) == .demo {
            return try await refreshDemo()
        }
        return try await refreshLive(trigger)
    }

    /// Demo mode: built-in demo data, no credentials, no network.
    private func refreshDemo() async throws -> ReadingsResult {
        var devices: [DeviceReadings] = []
        let now = Date()
        var providerFetchedAt: [Provider: Date] = [:]
        var rateLimitRemaining: Int?
        // Bespoke demo clients first (a consuming app's hand-rolled providers), then the
        // registry providers' real clients against MockTransport's canned
        // payloads — so every sensor type can be exercised without hardware
        // or credentials. Fail-soft: demo must survive one provider's fixture
        // or platform limitation (e.g. signing off-platform).
        for (provider, make) in demoClients {
            do {
                let client = try make()
                devices += try await client.fetchAllReadings()
                providerFetchedAt[provider] = now
                if let reporter = client as? RateLimitReporting,
                   let remaining = reporter.rateLimitRemaining {
                    rateLimitRemaining = remaining
                }
            } catch {
                Log.client.error("demo (\(provider.rawValue)) failed: \(error.localizedDescription)")
            }
        }
        for spec in ProviderSpec.all {
            do {
                devices += try await spec.makeClient(spec.demoCredentials, demoTransport)
                    .fetchAllReadings()
                providerFetchedAt[spec.provider] = now
            } catch {
                Log.client.error("demo (\(spec.provider.rawValue)) failed: \(error.localizedDescription)")
            }
        }
        let result = ReadingsResult(
            devices: devices,
            rateLimitRemaining: rateLimitRemaining,
            providerFetchedAt: providerFetchedAt)
        try saveSnapshot(result, isDemo: true)
        return result
    }

    /// Live mode: every configured provider, fail-soft per provider.
    private func refreshLive(_ trigger: Trigger) async throws -> ReadingsResult {
        let providers = connections.configuredProviders()
        guard !providers.isEmpty else {
            throw DingsError.missingCredentials(coreLocalized("No saved credentials."))
        }
        let now = Date()
        let previous = trigger == .unattended ? cache?.load().flatMap { $0.isDemo ? nil : $0 } : nil
        let sources = providers.map { provider in
            Source(provider: provider, notDue: Self.isNotDue(provider, previous: previous, now: now)) {
                let client = try makeClient(for: provider)
                let devices = try await client.fetchAllReadings()
                return (devices, (client as? RateLimitReporting)?.rateLimitRemaining)
            }
        }
        return try await mergeRefresh(sources, now: now)
    }

    /// A provider with its own floor whose last successful fetch is younger
    /// than that floor. Only its own fetch stamp counts: without one (never
    /// fetched, or a snapshot from before per-provider stamps) it is due, and
    /// so is a stamp in the future (a clock that ran ahead must not hold the
    /// provider back).
    private static func isNotDue(_ provider: Provider, previous: CachedReadings?, now: Date) -> Bool {
        guard RefreshPolicy.hasOwnInterval(provider),
              let stamp = previous?.providerFetchedAt[provider], stamp <= now else { return false }
        return now.timeIntervalSince(stamp) < RefreshPolicy.interval(for: provider)
    }

    /// A UI-test scenario: the demo data, changed the way the scenario says,
    /// through the same merge as a live refresh. A provider whose demo
    /// fixture does not load takes no part, so only a scenario's own
    /// failures show up as failures.
    private func refreshScenario(_ scenario: TestScenario) async throws -> ReadingsResult {
        if scenario.delay > 0 { try await Task.sleep(for: .seconds(scenario.delay)) }
        var available: [(Provider, [DeviceReadings])] = []
        let fixtures: [(Provider, @Sendable () throws -> any ProviderClient)] = demoClients
            + ProviderSpec.all.map { spec in
                (spec.provider, { spec.makeClient(spec.demoCredentials, demoTransport) })
            }
        for (provider, make) in fixtures {
            do {
                available.append((provider, try await make().fetchAllReadings()))
            } catch {
                Log.client.error("scenario: no demo data for \(provider.rawValue): \(error.localizedDescription)")
            }
        }
        let sources = available.enumerated().map { index, entry in
            Source(provider: entry.0) {
                if scenario.fails(entry.0, isFirst: index == 0) {
                    throw ProviderAPIError.http(entry.0, 503)
                }
                return (scenario.apply(to: entry.1), nil)
            }
        }
        return try await mergeRefresh(sources, now: Date().addingTimeInterval(-scenario.age))
    }

    /// One provider's fetch for `mergeRefresh`: its devices and, if it
    /// reports one, its remaining rate limit.
    private struct Source {
        let provider: Provider
        /// Sits out this run (see `Trigger.unattended`); `fetch` is not called.
        var notDue = false
        let fetch: () async throws -> ([DeviceReadings], Int?)
    }

    /// The live merge: each provider fetched on its own, fail-soft. `now` is
    /// what this run stamps as its fetch time.
    private func mergeRefresh(_ sources: [Source], now: Date) async throws -> ReadingsResult {
        let providers = sources.map(\.provider)

        // A demo snapshot is not previous *live* data. Right after a switch
        // from demo to live the cache still holds it; carrying its devices,
        // rate limit or fetch stamps forward would put demo data into a
        // snapshot stamped `isDemo: false`.
        let previous = cache?.load().flatMap { $0.isDemo ? nil : $0 }
        var devicesByProvider: [Provider: [DeviceReadings]] = [:]
        var outcomes: [ProviderRefreshOutcome] = []
        var rateLimitRemaining = previous?.rateLimitRemaining
        var providerFetchedAt: [Provider: Date] = [:]
        var firstError: Error?

        for source in sources {
            let provider = source.provider
            if source.notDue {
                let kept = previous?.devices.filter { $0.provider == provider } ?? []
                devicesByProvider[provider] = kept
                providerFetchedAt[provider] = previous?.providerFetchedAt[provider]
                outcomes.append(ProviderRefreshOutcome(provider: provider, succeeded: true, message: nil, notDue: true))
                Log.client.info("refresh (\(provider.rawValue)): not due (own floor \(Int(RefreshPolicy.interval(for: provider)))s)")
                continue
            }
            do {
                let (fetched, remaining) = try await source.fetch()
                if let remaining {
                    rateLimitRemaining = remaining
                }
                outcomes.append(ProviderRefreshOutcome(provider: provider, succeeded: true, message: nil))
                providerFetchedAt[provider] = now
                devicesByProvider[provider] = keepingPreviousReadings(for: fetched, of: provider, from: previous)
            } catch {
                // Fail-soft per provider: keep its previous devices from the
                // cache — and its previous fetch stamp, so "Synced" cues stay
                // honest — so one provider's outage never blanks the other's data.
                if firstError == nil { firstError = error }
                let kept = previous?.devices.filter { $0.provider == provider } ?? []
                devicesByProvider[provider] = kept
                providerFetchedAt[provider] = previousStamp(for: provider, in: previous, hasDevices: !kept.isEmpty)
                outcomes.append(ProviderRefreshOutcome(
                    provider: provider, succeeded: false, message: error.localizedDescription))
                Log.client.error("refresh (\(provider.rawValue)) failed: \(error.localizedDescription)")
            }
        }

        let fetchedSome = outcomes.contains { $0.succeeded && !$0.notDue }
        if !fetchedSome, let firstError {
            // Every provider that was fetched failed — surface the first error
            // and leave the existing cache untouched.
            throw firstError
        }
        guard fetchedSome || outcomes.contains(where: \.notDue) else {
            throw DingsError.network(coreLocalized("All providers failed."))
        }

        let devices = providers.flatMap { devicesByProvider[$0] ?? [] }
        let result = ReadingsResult(
            devices: devices,
            rateLimitRemaining: rateLimitRemaining,
            outcomes: outcomes,
            providerFetchedAt: providerFetchedAt
        )
        // Nothing fetched (every provider sat out): the cache already holds
        // exactly this, and its fetch time must not move.
        if fetchedSome { try saveSnapshot(result, isDemo: false, fetchedAt: now) }
        return result
    }

    /// An override wins over the registry; otherwise the spec supplies the
    /// client and the generic store supplies the credentials.
    private func makeClient(for provider: Provider) throws -> any ProviderClient {
        if let make = clientOverrides[provider] {
            return try make(transport)
        }
        guard let spec = ProviderSpec.spec(for: provider),
              let creds = try connections.loadCredentials(provider) else {
            throw ProviderAPIError.missingCredentials(provider)
        }
        return spec.makeClient(creds, transport)
    }

    /// A fetch can succeed yet deliver a device without readings (a station
    /// that is offline at the source reports an empty observation). Replacing
    /// good cached readings with nothing makes the app look broken, so carry
    /// the previous readings — with their honest `recorded` stamp — forward
    /// per device until real data returns.
    private func keepingPreviousReadings(
        for fetched: [DeviceReadings], of provider: Provider, from previous: CachedReadings?
    ) -> [DeviceReadings] {
        guard let previous else { return fetched }
        return fetched.map { fresh in
            guard fresh.readings.isEmpty,
                  let old = previous.devices.first(where: {
                      $0.provider == provider && $0.serialNumber == fresh.serialNumber
                  }),
                  !old.readings.isEmpty else { return fresh }
            Log.client.notice("refresh (\(provider.rawValue)): device \(Self.masked(fresh.serialNumber)) returned no readings — keeping previous")
            return old
        }
    }

    /// The fetch stamp a failed provider carries forward. Only a provider that
    /// has fetched before has one: its own stamp, or, for a snapshot written
    /// before per-provider stamps existed, the snapshot's date if it holds
    /// that provider's devices. A provider that has never succeeded gets
    /// `nil`, so nothing claims a sync that did not happen.
    private func previousStamp(
        for provider: Provider, in previous: CachedReadings?, hasDevices: Bool
    ) -> Date? {
        guard let previous else { return nil }
        if let stamp = previous.providerFetchedAt[provider] { return stamp }
        return previous.providerFetchedAt.isEmpty && hasDevices ? previous.fetchedAt : nil
    }

    /// Last four characters only: logs are public (see `Log`), and a full
    /// serial identifies the user's hardware.
    private static func masked(_ serial: String) -> String {
        "…" + serial.suffix(4)
    }

    private func saveSnapshot(_ result: ReadingsResult, isDemo: Bool, fetchedAt: Date = Date()) throws {
        guard let cache else { return }
        try cache.save(CachedReadings(
            devices: result.devices,
            rateLimitRemaining: result.rateLimitRemaining,
            fetchedAt: fetchedAt,
            providerFetchedAt: result.providerFetchedAt,
            isDemo: isDemo
        ))
    }
}
