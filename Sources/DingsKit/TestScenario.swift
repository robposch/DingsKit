import Foundation

/// A deterministic data situation for UI tests: what the network "answers"
/// when the app refreshes. Built from the app's own demo data, so an app gets
/// every scenario without writing any, and run through the same merge as a
/// live refresh (per-provider outcomes, fail-soft, cache carry-over, sync
/// stamps), so the app and its widgets behave as they would if live data had
/// gone wrong in exactly this way.
///
/// Set with the launch argument `--uitest-scenario <spec>`; see
/// `TestScenarioStore`. Only consulted in debug builds.
///
/// Specs, combinable with `+`:
/// - `live`: the demo data, presented as live data
/// - `partial-failure`, `partial-failure:<provider>`: the first provider (or
///   the named one) fails with HTTP 503
/// - `all-failed`: every provider fails
/// - `empty`: the account has no devices
/// - `stale`, `stale:<minutes>`: everything is 3 hours (or that many
///   minutes) old
/// - `item-removed:<serial>`: that item no longer exists
/// - `keep-cache`: keep the readings an earlier launch cached; by default a
///   scenario starts from an empty cache
public struct TestScenario: Codable, Equatable, Sendable {
    public enum Failure: Codable, Equatable, Sendable {
        case none
        /// The first provider that has demo data.
        case first
        case all
        /// By `Provider.rawValue`.
        case providers([String])
    }

    public var failure: Failure
    public var isEmpty: Bool
    /// Seconds by which readings and sync stamps are moved into the past.
    public var age: TimeInterval
    /// Serial numbers of items that no longer exist.
    public var removedItems: [String]
    /// Whether activating keeps the readings an earlier launch cached.
    public var keepsCache: Bool

    public init(failure: Failure = .none, isEmpty: Bool = false,
                age: TimeInterval = 0, removedItems: [String] = [], keepsCache: Bool = false) {
        self.failure = failure
        self.isEmpty = isEmpty
        self.age = age
        self.removedItems = removedItems
        self.keepsCache = keepsCache
    }

    /// `nil` for an empty or unknown spec, so a typo never runs a test
    /// against a different situation than intended.
    public init?(spec: String) {
        var scenario = TestScenario()
        let parts = spec.split(separator: "+").map(String.init)
        guard !parts.isEmpty else { return nil }
        for part in parts {
            let pieces = part.split(separator: ":", maxSplits: 1).map(String.init)
            let argument = pieces.count > 1 ? pieces[1] : nil
            switch pieces.first {
            case "live" where argument == nil:
                break
            case "partial-failure":
                scenario.failure = argument.map { .providers([$0]) } ?? .first
            case "all-failed" where argument == nil:
                scenario.failure = .all
            case "empty" where argument == nil:
                scenario.isEmpty = true
            case "stale":
                if let argument {
                    guard let minutes = Double(argument), minutes >= 0 else { return nil }
                    scenario.age = minutes * 60
                } else {
                    scenario.age = 3 * 3600
                }
            case "keep-cache" where argument == nil:
                scenario.keepsCache = true
            case "item-removed":
                guard let argument, !argument.isEmpty else { return nil }
                scenario.removedItems.append(argument)
            default:
                return nil
            }
        }
        self = scenario
    }

    func fails(_ provider: Provider, isFirst: Bool) -> Bool {
        switch failure {
        case .none: return false
        case .first: return isFirst
        case .all: return true
        case .providers(let names): return names.contains(provider.rawValue)
        }
    }

    /// The demo devices as this scenario's network would return them.
    func apply(to devices: [DeviceReadings]) -> [DeviceReadings] {
        guard !isEmpty else { return [] }
        return devices
            .filter { !removedItems.contains($0.serialNumber) }
            .map { device in
                guard age > 0 else { return device }
                return DeviceReadings(
                    serialNumber: device.serialNumber, name: device.name, model: device.model,
                    readings: device.readings, batteryPercentage: device.batteryPercentage,
                    recorded: device.recorded?.addingTimeInterval(-age), provider: device.provider)
            }
    }
}

/// The active `TestScenario`, kept in the App Group so the widget extension,
/// which never sees the app's launch arguments, uses the same one.
public struct TestScenarioStore: @unchecked Sendable {
    public static let launchArgument = "--uitest-scenario"
    private static let key = "uitestScenario"
    private let defaults: UserDefaults

    public init?(suiteName: String = AppGroupReadingsCache.defaultSuite) {
        guard let defaults = UserDefaults(suiteName: suiteName) else { return nil }
        self.defaults = defaults
    }

    public init(defaults: UserDefaults) { self.defaults = defaults }

    /// The scenario a refresher in this process should use: the stored one
    /// in debug builds, never one in release builds.
    public static var current: TestScenario? {
        #if DEBUG
        TestScenarioStore()?.load()
        #else
        nil
        #endif
    }

    /// Call at app launch. Stores the scenario named by `--uitest-scenario`,
    /// or clears it when the argument is absent, so a scenario never outlives
    /// the test run that set it. A new scenario also empties the readings
    /// cache unless it says `keep-cache`, so each test starts from nothing.
    /// Does nothing in release builds.
    public func activate(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        cache: (any ReadingsCache)? = AppGroupReadingsCache()
    ) {
        #if DEBUG
        guard let index = arguments.firstIndex(of: Self.launchArgument),
              arguments.indices.contains(index + 1),
              let scenario = TestScenario(spec: arguments[index + 1]) else {
            if arguments.contains(Self.launchArgument) {
                Log.app.error("test scenario: unknown spec, none active")
            }
            clear()
            return
        }
        save(scenario)
        if !scenario.keepsCache { cache?.clear() }
        Log.app.info("test scenario active: \(arguments[index + 1])")
        #endif
    }

    public func load() -> TestScenario? {
        guard let data = defaults.data(forKey: Self.key) else { return nil }
        return try? JSONDecoder().decode(TestScenario.self, from: data)
    }

    func save(_ scenario: TestScenario) {
        defaults.set(try? JSONEncoder().encode(scenario), forKey: Self.key)
    }

    func clear() {
        defaults.removeObject(forKey: Self.key)
    }
}
