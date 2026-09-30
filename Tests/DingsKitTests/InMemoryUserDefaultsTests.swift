import Testing
import Foundation
import DingsKitTestSupport

/// The fake behind every `UserDefaults`-backed store test: it must behave like
/// a fresh suite and never share state between instances.
@Suite struct InMemoryUserDefaultsTests {
    @Test func startsEmptyAndInstancesAreIsolated() {
        let first = InMemoryUserDefaults()
        let second = InMemoryUserDefaults()
        first.set("x", forKey: "k")
        #expect(first.string(forKey: "k") == "x")
        #expect(second.object(forKey: "k") == nil)
        #expect(second.dictionaryRepresentation().isEmpty)
    }

    @Test func typedAccessorsRoundTrip() {
        let defaults = InMemoryUserDefaults()
        defaults.set(true, forKey: "bool")
        defaults.set(42, forKey: "int")
        defaults.set(1.5, forKey: "double")
        defaults.set(Data([1, 2]), forKey: "data")
        #expect(defaults.bool(forKey: "bool"))
        #expect(defaults.integer(forKey: "int") == 42)
        #expect(defaults.double(forKey: "double") == 1.5)
        #expect(defaults.data(forKey: "data") == Data([1, 2]))
        #expect(defaults.bool(forKey: "missing") == false)

        defaults.removeObject(forKey: "int")
        #expect(defaults.object(forKey: "int") == nil)
    }
}
