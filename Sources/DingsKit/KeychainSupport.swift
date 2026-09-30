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
}
#endif
