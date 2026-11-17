import Foundation
import DingsKit

/// Test bootstrap: installs a minimal config so defaulted initializers work.
public enum TestDings {
    public static func bootstrap(
        providers: [ProviderSpec] = [],
        sensors: [SensorDescriptor] = [],
        appGroupSuite: String = "group.dingskit.tests",
        legacyDecodeProvider: Provider? = nil,
        keychainSyncedProviders: Set<Provider> = [],
        disclosure: DisclosureContent = DisclosureContent(disclaimer: "", severity: .info)
    ) {
        var config = DingsConfig(
            appGroupSuite: appGroupSuite,
            keychainService: "dingskit.tests",
            keychainAccessGroup: nil,
            logSubsystem: "dingskit.tests",
            backgroundTaskID: "dingskit.tests.refresh",
            providers: providers,
            sensors: sensors,
            legacyDecodeProvider: legacyDecodeProvider,
            disclosure: disclosure)
        config.keychainSyncedProviders = keychainSyncedProviders
        Dings._resetForTesting(config)
    }
}
