import Foundation

/// Facade over the per-provider credential stores: one place to ask "which
/// providers are connected?" and to load/save/clear each. At most one
/// connection per provider. Fully registry-driven; apps with bespoke legacy
/// stores wrap them in `ProviderCredentialStore` adapters.
public struct ConnectionsStore: Sendable {
    private let stores: [Provider: any ProviderCredentialStore]
    private let order: [Provider]

    public init(stores: [Provider: any ProviderCredentialStore], order: [Provider]) {
        self.stores = stores
        self.order = order
    }

    #if canImport(Security)
    /// Production initializer: one keychain-backed store per registered
    /// provider spec, in spec order.
    public init() {
        var stores: [Provider: any ProviderCredentialStore] = [:]
        for spec in Dings.config.providers {
            stores[spec.provider] = KeychainProviderCredentialStore(provider: spec.provider)
        }
        self.init(stores: stores, order: Dings.config.providers.map(\.provider))
    }
    #endif

    /// Providers with saved credentials, in `order`. A keychain read error
    /// counts as "not configured" - refresh and routing must not crash over a
    /// transiently unreadable item.
    public func configuredProviders() -> [Provider] {
        order.filter { (try? stores[$0]?.load()).flatMap { $0 } != nil }
    }

    public func loadCredentials(_ provider: Provider) throws -> ProviderCredentials? {
        try stores[provider]?.load()
    }

    public func saveCredentials(_ credentials: ProviderCredentials, for provider: Provider) throws {
        guard let store = stores[provider] else {
            throw ProviderAPIError.storage(provider, coreLocalized("No credential store configured."))
        }
        try store.save(credentials)
    }

    public func clear(_ provider: Provider) throws {
        try stores[provider]?.clear()
    }
}
