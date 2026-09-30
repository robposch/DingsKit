import Foundation

/// A `UserDefaults` that keeps every value in memory, for tests of the
/// `UserDefaults`-backed stores (`DataModeStore`, `BackgroundRunLog`,
/// `AppGroupReadingsCache`, `FreshInstallGuard`'s launch marker).
///
/// A real `UserDefaults(suiteName:)` that is written to leaves a
/// `<suite>.plist` in `~/Library/Preferences` on every test run. Removing the
/// domain afterwards does not help: the preferences daemon flushes an empty
/// plist a few seconds after the test process exits. This subclass overrides
/// the reading and writing entry points so nothing reaches the daemon or disk.
///
/// ```swift
/// let store = DataModeStore(defaults: InMemoryUserDefaults())
/// store.save(.demo)
/// #expect(store.load() == .demo)
/// ```
///
/// Each instance starts empty and is independent of every other instance.
public final class InMemoryUserDefaults: UserDefaults, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String: Any] = [:]

    /// Designated initializer, overridden so `InMemoryUserDefaults()` (the
    /// inherited convenience initializer) creates an empty in-memory store.
    /// `suitename` is ignored: every instance is its own isolated store.
    public override init?(suiteName suitename: String?) {
        super.init(suiteName: nil)
    }

    // MARK: Writing

    public override func set(_ value: Any?, forKey defaultName: String) {
        lock.withLock { storage[defaultName] = value }
    }
    public override func set(_ value: Bool, forKey defaultName: String) { set(value as Any?, forKey: defaultName) }
    public override func set(_ value: Int, forKey defaultName: String) { set(value as Any?, forKey: defaultName) }
    public override func set(_ value: Double, forKey defaultName: String) { set(value as Any?, forKey: defaultName) }
    public override func set(_ value: Float, forKey defaultName: String) { set(value as Any?, forKey: defaultName) }
    public override func set(_ url: URL?, forKey defaultName: String) { set(url as Any?, forKey: defaultName) }
    public override func removeObject(forKey defaultName: String) {
        lock.withLock { storage[defaultName] = nil }
    }
    public override func removePersistentDomain(forName domainName: String) {
        lock.withLock { storage.removeAll() }
    }

    // MARK: Reading

    public override func object(forKey defaultName: String) -> Any? {
        lock.withLock { storage[defaultName] }
    }
    public override func string(forKey defaultName: String) -> String? { object(forKey: defaultName) as? String }
    public override func data(forKey defaultName: String) -> Data? { object(forKey: defaultName) as? Data }
    public override func array(forKey defaultName: String) -> [Any]? { object(forKey: defaultName) as? [Any] }
    public override func dictionary(forKey defaultName: String) -> [String: Any]? {
        object(forKey: defaultName) as? [String: Any]
    }
    public override func stringArray(forKey defaultName: String) -> [String]? { object(forKey: defaultName) as? [String] }
    public override func url(forKey defaultName: String) -> URL? { object(forKey: defaultName) as? URL }
    public override func bool(forKey defaultName: String) -> Bool { object(forKey: defaultName) as? Bool ?? false }
    public override func integer(forKey defaultName: String) -> Int { object(forKey: defaultName) as? Int ?? 0 }
    public override func double(forKey defaultName: String) -> Double { object(forKey: defaultName) as? Double ?? 0 }
    public override func float(forKey defaultName: String) -> Float { object(forKey: defaultName) as? Float ?? 0 }
    public override func dictionaryRepresentation() -> [String: Any] { lock.withLock { storage } }
}
