import Foundation

public enum WatchSyncError: Error, Equatable {
    /// The payload was written by a build with a different wire format.
    case unsupportedVersion(Int)
}

/// Everything an Apple Watch needs from the iPhone to fetch readings on its
/// own: the user's credentials per provider, plus the two preferences that
/// change what is fetched or shown. Sent device to device over
/// WatchConnectivity; it never touches a server.
///
/// The field names, `userInfoKey` and `currentVersion` are wire format between
/// two separately updated apps. Do not rename them; bump the version instead.
public struct WatchSyncPayload: Codable, Equatable, Sendable {
    public static let currentVersion = 1
    public static let userInfoKey = "dingsWatchSync"

    public var version: Int
    /// Keyed by `Provider.rawValue`. A provider missing here is disconnected.
    public var credentials: [String: ProviderCredentials]
    public var unitSystem: UnitSystem
    public var dataMode: DataMode

    public init(
        version: Int = WatchSyncPayload.currentVersion,
        credentials: [String: ProviderCredentials],
        unitSystem: UnitSystem,
        dataMode: DataMode
    ) {
        self.version = version
        self.credentials = credentials
        self.unitSystem = unitSystem
        self.dataMode = dataMode
    }

    /// What `apply` did. `removed` lists providers whose credentials were
    /// cleared, so the caller can drop their devices from its readings cache.
    public struct Applied: Equatable, Sendable {
        public var changed: Bool
        public var removed: [Provider]
        public init(changed: Bool, removed: [Provider]) {
            self.changed = changed
            self.removed = removed
        }
    }

    /// The phone's current state. Throws when any credential store cannot be
    /// read: an unreadable keychain must not be mistaken for "disconnected",
    /// because applying that payload would wipe the watch.
    public static func snapshot(
        connections: ConnectionsStore,
        units: UnitPreferenceStore?,
        dataMode: DataModeStore?
    ) throws -> WatchSyncPayload {
        var credentials: [String: ProviderCredentials] = [:]
        for provider in connections.providers {
            if let stored = try connections.loadCredentials(provider) {
                credentials[provider.rawValue] = stored
            }
        }
        return WatchSyncPayload(
            credentials: credentials,
            unitSystem: units?.load() ?? .metric,
            dataMode: dataMode?.load() ?? .live)
    }

    /// Makes the local stores match this payload. Idempotent: a store that
    /// already holds the incoming value is not written again. Providers the
    /// local `connections` does not know are ignored. A failed write throws
    /// midway; applying the same payload again finishes the job.
    @discardableResult
    public func apply(
        to connections: ConnectionsStore,
        units: UnitPreferenceStore?,
        dataMode: DataModeStore?
    ) throws -> Applied {
        guard version == Self.currentVersion else {
            throw WatchSyncError.unsupportedVersion(version)
        }
        var changed = false
        var removed: [Provider] = []
        for provider in connections.providers {
            let existing = try connections.loadCredentials(provider)
            if let incoming = credentials[provider.rawValue] {
                if existing != incoming {
                    try connections.saveCredentials(incoming, for: provider)
                    changed = true
                }
            } else if existing != nil {
                try connections.clear(provider)
                removed.append(provider)
                changed = true
            }
        }
        if let units, units.load() != unitSystem {
            units.save(unitSystem)
            changed = true
        }
        if let dataMode, dataMode.load() != self.dataMode {
            dataMode.save(self.dataMode)
            changed = true
        }
        return Applied(changed: changed, removed: removed)
    }

    /// The property-list dictionary WatchConnectivity carries.
    public func userInfo() throws -> [String: Any] {
        [Self.userInfoKey: try JSONEncoder().encode(self)]
    }

    /// `nil` when the dictionary carries no payload or one this build cannot
    /// decode.
    public init?(userInfo: [String: Any]) {
        guard let data = userInfo[Self.userInfoKey] as? Data,
              let decoded = try? JSONDecoder().decode(WatchSyncPayload.self, from: data)
        else { return nil }
        self = decoded
    }
}
