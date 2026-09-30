#if canImport(Security)
import Foundation
import Security

/// Keychain persistence for one provider's credential bag: a generic-password
/// item under the app's service and shared access group (so the widget
/// extension can read it), account "<provider>-credentials", with the
/// protection class from `KeychainSupport` (readable while the device is
/// locked, which widgets and background refresh need). Items an app stored
/// under other account names are untouched.
public struct KeychainProviderCredentialStore: ProviderCredentialStore {
    private let provider: Provider
    private let service: String
    private let accessGroup: String?

    public init(
        provider: Provider,
        service: String = Dings.config.keychainService,
        accessGroup: String? = Dings.config.keychainAccessGroup
    ) {
        self.provider = provider
        self.service = service
        self.accessGroup = accessGroup
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

    public func load() throws -> ProviderCredentials? {
        var query = baseQuery()
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
        var addQuery = baseQuery()
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
            let updateStatus = SecItemUpdate(baseQuery() as CFDictionary, updates as CFDictionary)
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
        let status = SecItemDelete(baseQuery() as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            Log.credentials.error("keychain delete failed (\(provider.rawValue), OSStatus \(status))")
            throw ProviderAPIError.storage(provider, coreLocalized("Keychain delete failed (OSStatus \(String(status)))"))
        }
    }
}
#endif
