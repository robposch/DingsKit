import Foundation
import DingsKit

/// Test bootstrap: installs a minimal config so defaulted initializers work.
public enum TestDings {
    public static func bootstrap(
        providers: [ProviderSpec] = [],
        sensors: [SensorDescriptor] = [],
        appGroupSuite: String = "group.dingskit.tests",
        legacyDecodeProvider: Provider? = nil
    ) {
        Dings._resetForTesting(DingsConfig(
            appGroupSuite: appGroupSuite,
            keychainService: "dingskit.tests",
            keychainAccessGroup: nil,
            logSubsystem: "dingskit.tests",
            backgroundTaskID: "dingskit.tests.refresh",
            providers: providers,
            sensors: sensors,
            legacyDecodeProvider: legacyDecodeProvider))
    }
}
