#if canImport(Security)
import Testing
import Foundation
import Security
@testable import DingsKit
import DingsKitTestSupport

/// The query shapes that decide which keychain items a store touches. The
/// Security calls themselves need the shared access-group entitlement, which
/// `swift test` lacks, so they are verified on device; the queries are not.
@Suite("Keychain sync queries")
struct KeychainSyncQueryTests {
    private let base: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "svc",
        kSecAttrAccount as String: "acct",
    ]

    private func syncValue(_ query: [String: Any]) -> CFTypeRef? {
        query[kSecAttrSynchronizable as String] as CFTypeRef?
    }

    @Test func localStoreLeavesEveryQueryUnchanged() {
        for operation in [KeychainSupport.Operation.read, .write, .delete] {
            let query = KeychainSupport.scoped(base, synchronizable: false, for: operation)
            #expect(syncValue(query) == nil)
            #expect(query.count == base.count)
        }
    }

    @Test func syncedStoreWritesSynchronizableItems() {
        let query = KeychainSupport.scoped(base, synchronizable: true, for: .write)
        #expect(CFEqual(syncValue(query), kCFBooleanTrue))
    }

    /// Reads and deletes also match the device-only item an earlier build
    /// saved, so the widget finds the key before the app has moved it and
    /// signing out leaves nothing behind.
    @Test func syncedStoreReadsAndDeletesBothKinds() {
        for operation in [KeychainSupport.Operation.read, .delete] {
            let query = KeychainSupport.scoped(base, synchronizable: true, for: operation)
            #expect(CFEqual(syncValue(query), kSecAttrSynchronizableAny))
        }
    }
}

extension GlobalConfig {
    @Suite("Keychain sync config")
    struct KeychainSyncConfigTests {
        @Test func providersStayOnDeviceByDefault() {
            TestDings.bootstrap()
            #expect(Dings.config.keychainSyncedProviders.isEmpty)
            #expect(KeychainProviderCredentialStore(provider: Provider("a")).synchronizable == false)
        }

        @Test func storeSyncsWhenItsProviderIsListed() {
            TestDings.bootstrap(keychainSyncedProviders: [Provider("a")])
            #expect(KeychainProviderCredentialStore(provider: Provider("a")).synchronizable)
            #expect(KeychainProviderCredentialStore(provider: Provider("b")).synchronizable == false)
        }
    }
}
#endif
