import Foundation

/// Unified-logging facility shared by the app, the widget, and the kit.
///
/// All categories live under one subsystem (the app's `Dings.config.logSubsystem`)
/// so the whole app can be streamed with:
///   `xcrun simctl spawn booted log stream --predicate 'subsystem == "com.example.app"'`
///
/// Messages are emitted as **public** so they're readable in the stream during
/// development. Never pass secrets (client secret, full client id) into a log call —
/// mask them at the call site.
///
/// On a platform without `os`, every call is a no-op.
public enum Log {
    public static let subsystem = Dings.config.logSubsystem

    public static let app = LogCategory("app")            // app lifecycle, routing, UI taps
    public static let credentials = LogCategory("credentials") // keychain + validation (masked)
    public static let client = LogCategory("client")      // provider client orchestration
    public static let token = LogCategory("token")        // OAuth token lifecycle
    public static let net = LogCategory("net")            // every HTTP request/response
    public static let cache = LogCategory("cache")        // App-Group readings cache
    public static let readings = LogCategory("readings")  // app readings view-model
    public static let widget = LogCategory("widget")      // widget timeline provider
}

#if canImport(os)
import os

/// Thin wrapper over `os.Logger` that stamps every message `.public` (readable while
/// developing) and keeps a `String`-based API so call sites do not depend on
/// `OSLogMessage`.
public struct LogCategory: Sendable {
    private let logger: Logger
    init(_ category: String) {
        logger = Logger(subsystem: Log.subsystem, category: category)
    }
    public func debug(_ message: String)  { logger.debug("\(message, privacy: .public)") }
    public func info(_ message: String)   { logger.info("\(message, privacy: .public)") }
    public func notice(_ message: String) { logger.notice("\(message, privacy: .public)") }
    public func warning(_ message: String){ logger.warning("\(message, privacy: .public)") }
    public func error(_ message: String)  { logger.error("\(message, privacy: .public)") }
}
#else
/// No-op logger for a platform without `os`.
public struct LogCategory: Sendable {
    init(_ category: String) {}
    public func debug(_ message: String) {}
    public func info(_ message: String) {}
    public func notice(_ message: String) {}
    public func warning(_ message: String) {}
    public func error(_ message: String) {}
}
#endif
