#if canImport(Security)
import Foundation
import Security

/// Generic keychain mechanics shared by every keychain-backed credential store,
/// app-agnostic. The per-app *values* (service, shared access group) flow in
/// through `DingsConfig`; this only owns the protection-class policy that is the
/// same for all of them.
public enum KeychainSupport {
    /// Protection class for credential items. Credentials are read by the
    /// background-refresh task (and the widget's stale-cache fallback), which can
    /// run while the device is locked. The default protection class
    /// (`WhenUnlocked`) makes those reads fail with `errSecInteractionNotAllowed`
    /// (-25308) once the device locks, so items are stored `AfterFirstUnlock`:
    /// readable in the background as long as the user has unlocked at least once
    /// since boot, while still migrating with an encrypted backup so the user
    /// keeps their key when moving to a new device.
    public static var accessibility: CFString { kSecAttrAccessibleAfterFirstUnlock }

    /// What a query is used for; decides which items a synced store matches.
    public enum Operation: Sendable { case read, write, delete }

    /// Scopes a store's base query to its sync mode. A device-only store keeps
    /// the base query, which matches device-only items only. A synced store
    /// writes synced items, and reads and deletes both kinds, so a device-only
    /// item saved by an earlier build is still found (the widget can run before
    /// the app has moved it) and signing out leaves nothing behind.
    public static func scoped(
        _ base: [String: Any], synchronizable: Bool, for operation: Operation
    ) -> [String: Any] {
        guard synchronizable else { return base }
        var query = base
        switch operation {
        case .write: query[kSecAttrSynchronizable as String] = kCFBooleanTrue
        case .read, .delete: query[kSecAttrSynchronizable as String] = kSecAttrSynchronizableAny
        }
        return query
    }

    /// Moves the device-only item matching `base` to iCloud Keychain: adds a
    /// synced copy, then deletes the device-only one, so a crash in between
    /// leaves two equal items rather than none. When a synced item already
    /// exists (another device synced one) it wins and the local copy goes.
    /// Idempotent; does nothing when there is no device-only item.
    ///
    /// Device-verified only: `swift test` has no entitlement for a shared
    /// access group.
    public static func moveToSynchronizable(_ base: [String: Any]) {
        var read = base
        read[kSecReturnData as String] = true
        read[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let readStatus = SecItemCopyMatching(read as CFDictionary, &item)
        guard readStatus == errSecSuccess, let data = item as? Data else {
            if readStatus != errSecItemNotFound {
                Log.credentials.error("keychain sync move: read failed (OSStatus \(readStatus))")
            }
            return
        }
        var add = scoped(base, synchronizable: true, for: .write)
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = accessibility
        let addStatus = SecItemAdd(add as CFDictionary, nil)
        guard addStatus == errSecSuccess || addStatus == errSecDuplicateItem else {
            Log.credentials.error("keychain sync move: add failed (OSStatus \(addStatus))")
            return
        }
        let deleteStatus = SecItemDelete(base as CFDictionary)
        guard deleteStatus == errSecSuccess || deleteStatus == errSecItemNotFound else {
            Log.credentials.error("keychain sync move: delete failed (OSStatus \(deleteStatus))")
            return
        }
        Log.credentials.notice("keychain: moved credentials to iCloud Keychain")
    }
}
#endif
