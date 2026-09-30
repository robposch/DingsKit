import Foundation

/// iOS keychain items survive app uninstall; standard UserDefaults do not.
/// A missing launch marker with stored credentials therefore means the app
/// was deleted and reinstalled: wipe the stale credentials so a reinstall
/// genuinely starts clean. An app that tells its users "deleting the app
/// deletes your credentials" needs this to make the statement true.
public enum FreshInstallGuard {
    static let markerKey = "dings.hasLaunchedBefore"

    /// Call once at app start, after `Dings.bootstrap`. Not from extensions.
    /// - Returns: true when a stale-credential wipe was performed.
    @discardableResult
    public static func run(
        connections: ConnectionsStore,
        cache: (any ReadingsCache)? = nil,
        marker: UserDefaults = .standard
    ) -> Bool {
        defer { marker.set(true, forKey: markerKey) }
        guard !marker.bool(forKey: markerKey) else { return false }
        let stale = connections.configuredProviders()
        guard !stale.isEmpty else { return false }
        for provider in stale { try? connections.clear(provider) }
        cache?.clear()
        Log.credentials.notice("fresh install: wiped stale credentials for \(stale.count) provider(s)")
        return true
    }
}
