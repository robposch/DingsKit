import Foundation

/// Non-secret snapshot the app writes and the widget reads. Lives in the App
/// Group container, never the Keychain.
public struct CachedReadings: Codable, Equatable, Sendable {
    public let devices: [DeviceReadings]
    public let rateLimitRemaining: Int?
    public let fetchedAt: Date
    /// When each provider last fetched successfully. On a fail-soft refresh the
    /// failed provider keeps its previous stamp while `fetchedAt` advances, so
    /// per-device "Synced" cues stay honest. Empty for legacy snapshots —
    /// `fetchedAt(for:)` falls back to the snapshot-level date.
    public let providerFetchedAt: [Provider: Date]
    public let isDemo: Bool

    public init(devices: [DeviceReadings], rateLimitRemaining: Int?, fetchedAt: Date,
                providerFetchedAt: [Provider: Date] = [:], isDemo: Bool = false) {
        self.devices = devices
        self.rateLimitRemaining = rateLimitRemaining
        self.fetchedAt = fetchedAt
        self.providerFetchedAt = providerFetchedAt
        self.isDemo = isDemo
    }

    /// When `provider`'s data was last fetched successfully; snapshot date for
    /// legacy caches written before per-provider stamps existed.
    public func fetchedAt(for provider: Provider) -> Date {
        providerFetchedAt[provider] ?? fetchedAt
    }

    private enum CodingKeys: String, CodingKey { case devices, rateLimitRemaining, fetchedAt, providerFetchedAt, isDemo }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        devices = try c.decode([DeviceReadings].self, forKey: .devices)
        rateLimitRemaining = try c.decodeIfPresent(Int.self, forKey: .rateLimitRemaining)
        fetchedAt = try c.decode(Date.self, forKey: .fetchedAt)
        // Stored keyed by raw value: [Provider: Date] would encode as a flat
        // [key, value, key, value] array (`Provider` is a struct that is not
        // `CodingKeyRepresentable`), unreadable and fragile.
        // `Provider.init(rawValue:)` is non-failable now, so unknown raw values
        // (from a newer app version) are kept rather than dropped.
        let rawStamps = try c.decodeIfPresent([String: Date].self, forKey: .providerFetchedAt) ?? [:]
        providerFetchedAt = Dictionary(uniqueKeysWithValues: rawStamps.map { key, date in
            (Provider(rawValue: key), date)
        })
        isDemo = try c.decodeIfPresent(Bool.self, forKey: .isDemo) ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(devices, forKey: .devices)
        try c.encodeIfPresent(rateLimitRemaining, forKey: .rateLimitRemaining)
        try c.encode(fetchedAt, forKey: .fetchedAt)
        let rawStamps = Dictionary(uniqueKeysWithValues: providerFetchedAt.map { ($0.rawValue, $1) })
        try c.encode(rawStamps, forKey: .providerFetchedAt)
        try c.encode(isDemo, forKey: .isDemo)
    }

    /// The snapshot without `provider`'s devices — used when the user
    /// disconnects one provider so its data (and widgets showing it) clears
    /// while the other provider's devices stay. `nil` when nothing remains,
    /// so the caller clears the cache entirely instead.
    ///
    /// - Parameter clearsRateLimit: drop the cached rate-limit budget too. The
    ///   rate limit is a single provider's metric (e.g. a vendor cloud API), so the caller
    ///   passes `true` when removing that provider; a neutral core carries no
    ///   provider-specific branch of its own.
    public func removing(_ provider: Provider, clearsRateLimit: Bool = false) -> CachedReadings? {
        let remaining = devices.filter { $0.provider != provider }
        guard !remaining.isEmpty else { return nil }
        return CachedReadings(
            devices: remaining,
            rateLimitRemaining: clearsRateLimit ? nil : rateLimitRemaining,
            fetchedAt: fetchedAt,
            providerFetchedAt: providerFetchedAt.filter { $0.key != provider },
            isDemo: isDemo
        )
    }
}

/// Persistence seam for the readings snapshot.
public protocol ReadingsCache: Sendable {
    func load() -> CachedReadings?
    func save(_ readings: CachedReadings) throws
    /// Remove the cached snapshot (e.g. on logout) so the widget stops showing
    /// stale data and falls back to its empty state.
    func clear()
}

/// App-Group-backed cache (`UserDefaults(suiteName:)`). The app and widget share
/// the same suite, so the widget reads exactly what the app last wrote.
public struct AppGroupReadingsCache: ReadingsCache, @unchecked Sendable {
    public static let defaultSuite = Dings.config.appGroupSuite
    private static let key = "cachedReadings"
    private let defaults: UserDefaults

    /// Production initializer. Returns `nil` if the App Group is unavailable
    /// (e.g. the entitlement is missing).
    public init?(suiteName: String = AppGroupReadingsCache.defaultSuite) {
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            Log.cache.error("App Group unavailable for suite \(suiteName)")
            return nil
        }
        self.defaults = defaults
    }

    /// Test initializer with an injected `UserDefaults`.
    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    public func load() -> CachedReadings? {
        guard let data = defaults.data(forKey: Self.key) else {
            Log.cache.debug("cache load: empty")
            return nil
        }
        guard let snapshot = try? JSONDecoder().decode(CachedReadings.self, from: data) else {
            Log.cache.error("cache load: decode failed (\(data.count) B)")
            return nil
        }
        Log.cache.debug("cache load: \(snapshot.devices.count) device(s), age \(Int(Date().timeIntervalSince(snapshot.fetchedAt)))s")
        return snapshot
    }

    public func save(_ readings: CachedReadings) throws {
        do {
            let data = try JSONEncoder().encode(readings)
            defaults.set(data, forKey: Self.key)
            Log.cache.info("cache wrote \(readings.devices.count) device(s) (\(data.count) B)")
        }
        catch {
            Log.cache.error("cache encode failed")
            throw DingsError.storage(coreLocalized("Could not encode readings snapshot."))
        }
    }

    public func clear() {
        defaults.removeObject(forKey: Self.key)
        Log.cache.info("cache cleared")
    }
}
