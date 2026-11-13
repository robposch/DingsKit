#if canImport(Security)
import Foundation
import Security

/// Keychain persistence for one provider's credential bag: a generic-password
/// item under the app's service and shared access group (so the widget
/// extension can read it), account "<provider>-credentials", with the
/// protection class from `KeychainSupport` (readable while the device is
/// locked, which widgets and background refresh need). Items an app stored
/// under other account names are untouched. Providers listed in
/// `DingsConfig.keychainSyncedProviders` sync through iCloud Keychain.
public struct KeychainProviderCredentialStore: ProviderCredentialStore {
    private let provider: Provider
    private let service: String
    private let accessGroup: String?
    public let synchronizable: Bool

    public init(
        provider: Provider,
        service: String = Dings.config.keychainService,
        accessGroup: String? = Dings.config.keychainAccessGroup,
        synchronizable: Bool? = nil
    ) {
        self.provider = provider
        self.service = service
        self.accessGroup = accessGroup
        self.synchronizable = synchronizable ?? Dings.config.keychainSyncedProviders.contains(provider)
    }

    private var account: String { "\(provider.rawValue)-credentials" }

    private func baseQuery() -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        if let accessGroup { query[kSecAttrAccessGroup as String] = accessGroup }
        return query
    }

    private func query(for operation: KeychainSupport.Operation) -> [String: Any] {
        KeychainSupport.scoped(baseQuery(), synchronizable: synchronizable, for: operation)
    }

    /// Moves a device-only item saved before this provider synced to iCloud
    /// Keychain. No-op for a device-only store. Call once at app start.
    public func moveToSynchronizableIfNeeded() {
        guard synchronizable else { return }
        KeychainSupport.moveToSynchronizable(baseQuery())
    }

    public func load() throws -> ProviderCredentials? {
        var query = query(for: .read)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound {
            Log.credentials.debug("keychain load (\(provider.rawValue)): none stored")
            return nil
        }
        guard status == errSecSuccess, let data = item as? Data else {
            Log.credentials.error("keychain read failed (\(provider.rawValue), OSStatus \(status))")
            throw ProviderAPIError.storage(provider, coreLocalized("Keychain read failed (OSStatus \(String(status)))"))
        }
        do {
            let creds = try JSONDecoder().decode(ProviderCredentials.self, from: data)
            Log.credentials.debug("keychain load (\(provider.rawValue)): found (\(creds.fields.count) field(s))")
            return creds
        } catch {
            Log.credentials.error("keychain decode failed (\(provider.rawValue))")
            throw ProviderAPIError.storage(provider, coreLocalized("Could not decode stored credentials."))
        }
    }

    public func save(_ credentials: ProviderCredentials) throws {
        let data: Data
        do { data = try JSONEncoder().encode(credentials) }
        catch { throw ProviderAPIError.storage(provider, coreLocalized("Could not encode credentials.")) }

        // Add-or-update: `SecItemUpdate` keeps the item in place so there is
        // no delete/re-add crash window.
        var addQuery = query(for: .write)
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = KeychainSupport.accessibility
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        switch status {
        case errSecSuccess:
            Log.credentials.info("keychain saved (\(provider.rawValue), \(credentials.fields.count) field(s))")
        case errSecDuplicateItem:
            let updates: [String: Any] = [
                kSecValueData as String: data,
                kSecAttrAccessible as String: KeychainSupport.accessibility,
            ]
            let updateStatus = SecItemUpdate(query(for: .write) as CFDictionary, updates as CFDictionary)
            guard updateStatus == errSecSuccess else {
                Log.credentials.error("keychain update failed (\(provider.rawValue), OSStatus \(updateStatus))")
                throw ProviderAPIError.storage(provider, coreLocalized("Keychain write failed (OSStatus \(String(updateStatus)))"))
            }
            Log.credentials.info("keychain updated (\(provider.rawValue))")
        default:
            Log.credentials.error("keychain write failed (\(provider.rawValue), OSStatus \(status))")
            throw ProviderAPIError.storage(provider, coreLocalized("Keychain write failed (OSStatus \(String(status)))"))
        }
    }

    public func clear() throws {
        let status = SecItemDelete(query(for: .delete) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            Log.credentials.error("keychain delete failed (\(provider.rawValue), OSStatus \(status))")
            throw ProviderAPIError.storage(provider, coreLocalized("Keychain delete failed (OSStatus \(String(status)))"))
        }
    }
}
#endif
