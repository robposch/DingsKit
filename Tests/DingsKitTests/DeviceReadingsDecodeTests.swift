import Testing
import Foundation
@testable import DingsKit
import DingsKitTestSupport

extension GlobalConfig {
    /// In `GlobalConfig` because each test installs a different
    /// `legacyDecodeProvider`.
    @Suite struct DeviceReadingsDecodeTests {
        /// A snapshot written before the `provider` key existed.
        private let legacyJSON = Data(#"""
        {"serialNumber":"1","name":"Room","model":"X","readings":[],"batteryPercentage":null,"recorded":null}
        """#.utf8)

        @Test func decodingWithoutProviderKeyThrowsWhenNoFallbackConfigured() {
            TestDings.bootstrap(legacyDecodeProvider: nil)
            #expect(throws: DecodingError.self) {
                try JSONDecoder().decode(DeviceReadings.self, from: legacyJSON)
            }
        }

        @Test func decodingWithoutProviderKeyUsesConfiguredFallback() throws {
            TestDings.bootstrap(legacyDecodeProvider: Provider("original-vendor"))
            let decoded = try JSONDecoder().decode(DeviceReadings.self, from: legacyJSON)
            #expect(decoded.provider == Provider("original-vendor"))
        }

        /// An explicit `provider` key always wins over the fallback.
        @Test func explicitProviderKeyBeatsFallback() throws {
            TestDings.bootstrap(legacyDecodeProvider: Provider("original-vendor"))
            let json = Data(#"""
            {"serialNumber":"1","name":"Room","model":"X","readings":[],"provider":"newer-vendor"}
            """#.utf8)
            let decoded = try JSONDecoder().decode(DeviceReadings.self, from: json)
            #expect(decoded.provider == Provider("newer-vendor"))
            #expect(decoded.batteryPercentage == nil)
            #expect(decoded.recorded == nil)
        }
    }
}
