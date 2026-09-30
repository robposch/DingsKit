import Testing
import Foundation
@testable import DingsKit

/// The kit's string catalog is maintained by hand, so nothing else notices a
/// `coreLocalized("…")` call whose key was never added, or an entry whose
/// German is missing: both silently render English on a German device.
///
/// Matching tolerates interpolation: a source `\(x)` and any catalog format
/// specifier (`%@`, `%lld`, `%1$@`, …) both normalize to one placeholder, so
/// the check does not need to know each interpolated value's type.
@Suite struct LocalizationCatalogTests {
    private static let packageRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // DingsKitTests
        .deletingLastPathComponent()   // Tests
        .deletingLastPathComponent()   // package root

    private static let catalogURL = packageRoot
        .appendingPathComponent("Sources/DingsKit/Resources/Localizable.xcstrings")

    /// key -> German string unit (`state`, `value`), if any.
    private static func loadCatalog() throws -> [String: (state: String?, value: String?)] {
        let data = try Data(contentsOf: catalogURL)
        let root = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let strings = try #require(root["strings"] as? [String: Any])
        var result: [String: (state: String?, value: String?)] = [:]
        for (key, entry) in strings {
            let unit = ((entry as? [String: Any])?["localizations"] as? [String: Any])
                .flatMap { $0["de"] as? [String: Any] }
                .flatMap { $0["stringUnit"] as? [String: Any] }
            result[key] = (unit?["state"] as? String, unit?["value"] as? String)
        }
        return result
    }

    @Test func everyCoreLocalizedKeyIsInTheCatalogWithGerman() throws {
        let catalog = try Self.loadCatalog()
        var normalizedCatalog: [String: String] = [:]
        for key in catalog.keys { normalizedCatalog[PrivateKeyNormalizer.catalogKey(key)] = key }

        let sources = try Self.swiftFiles(under: Self.packageRoot.appendingPathComponent("Sources"))
        var found = 0
        for file in sources {
            let text = try String(contentsOf: file, encoding: .utf8)
            for literal in PrivateKeyNormalizer.coreLocalizedLiterals(in: text) {
                found += 1
                let location = "\(file.lastPathComponent): \(literal)"
                // A literal may itself carry a specifier when the caller
                // formats afterwards (`String(format: coreLocalized("…%@…"), x)`).
                guard let key = normalizedCatalog[PrivateKeyNormalizer.catalogKey(literal)] else {
                    Issue.record("No catalog entry for coreLocalized key (\(location))")
                    continue
                }
                let unit = catalog[key]
                #expect(unit?.state == "translated", "German not translated: \(location)")
                #expect(unit?.value?.isEmpty == false, "German missing: \(location)")
            }
        }
        // Guards the scanner itself: a broken path or parser would find
        // nothing and pass vacuously.
        #expect(found >= 60, "Only \(found) coreLocalized literals found; scanner or path is broken")
    }

    @Test func everyCatalogEntryHasTranslatedGermanWithMatchingPlaceholders() throws {
        let catalog = try Self.loadCatalog()
        #expect(!catalog.isEmpty)
        for (key, unit) in catalog {
            #expect(unit.state == "translated", "\(key): de state is \(unit.state ?? "missing")")
            guard let value = unit.value, !value.isEmpty else {
                Issue.record("\(key): de value missing")
                continue
            }
            #expect(PrivateKeyNormalizer.placeholderCount(key) == PrivateKeyNormalizer.placeholderCount(value),
                    "\(key): German has a different number of placeholders")
        }
    }

    /// The scan above proves the keys exist; this proves an interpolated call
    /// actually resolves to them at runtime, for each interpolation type the
    /// kit uses (String becomes `%@`, Int becomes `%lld`).
    ///
    /// Needs the compiled German table in the resource bundle. Xcode builds
    /// always emit it; the command-line `swift build` of older toolchains
    /// (Xcode 16) does not, so there the test is skipped rather than failed.
    @Test(.enabled(if: Self.germanTableIsBuilt, "string catalog not compiled by this toolchain"))
    func interpolatedKeysResolveInGerman() throws {
        let message = "x"
        let status: Int32 = -34018
        let httpStatus = 503
        let name = "Acme"
        #expect(try german("Cache error: \(message)") == "Cache-Fehler: x")
        #expect(try german("\(name) returned HTTP \(httpStatus). Try again later.")
                == "Acme hat HTTP 503 zurückgegeben. Versuch es später erneut.")
        // Status codes go in as strings: an Int would be locale-formatted
        // ("-34.018" in German), which is wrong for an error code.
        #expect(try german("Keychain read failed (OSStatus \(String(status)))")
                == "Lesen aus dem Schlüsselbund fehlgeschlagen (OSStatus -34018)")
        #expect(try german("reads your devices using your own free \(name) API credentials. You create them once in your \(name) account.")
                == "liest deine Geräte über deine eigenen kostenlosen Acme-API-Zugangsdaten. Du erstellst sie einmalig in deinem Acme-Konto.")
    }

    private static var germanTableIsBuilt: Bool {
        Bundle.module.url(forResource: "de", withExtension: "lproj") != nil
    }

    /// Looks the key up in the compiled German table directly. Overriding the
    /// locale of a `LocalizedStringResource` instead does not select the
    /// German table on every OS version.
    private func german(_ value: String.LocalizationValue) throws -> String {
        let url = try #require(Bundle.module.url(forResource: "de", withExtension: "lproj"))
        let bundle = try #require(Bundle(url: url))
        return String(localized: value, bundle: bundle)
    }

    private static func swiftFiles(under directory: URL) throws -> [URL] {
        let enumerator = try #require(FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil))
        return enumerator.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
    }
}

/// Extracts `coreLocalized("…")` literals from Swift source and normalizes
/// source literals and catalog keys to one comparable form.
private enum PrivateKeyNormalizer {
    static let placeholder: Character = "\u{FFFC}"

    /// `%@`, `%lld`, `%1$@`, `%.1f` and friends; `%%` is handled separately.
    private static let specifier = try? NSRegularExpression(
        pattern: #"%(\d+\$)?[-+ #0]*\d*(\.\d+)?(hh|h|ll|l|q|z|t|j)?[@dDiuUxXoOfFeEgGcCsSpaA]"#)

    static func catalogKey(_ key: String) -> String {
        guard let specifier else { return key }
        let marker = "\u{0}"
        let escaped = key.replacingOccurrences(of: "%%", with: marker)
        let range = NSRange(escaped.startIndex..., in: escaped)
        let replaced = specifier.stringByReplacingMatches(
            in: escaped, range: range, withTemplate: String(placeholder))
        return replaced.replacingOccurrences(of: marker, with: "%")
    }

    static func placeholderCount(_ string: String) -> Int {
        catalogKey(string).filter { $0 == placeholder }.count
    }

    /// Every single-line string literal passed directly as the first argument
    /// of `coreLocalized(`, with interpolations replaced by `placeholder` and
    /// escapes decoded. Calls whose argument is not a literal are skipped.
    static func coreLocalizedLiterals(in source: String) -> [String] {
        var results: [String] = []
        let chars = Array(source)
        let needle = Array("coreLocalized(")
        var i = 0
        while i + needle.count <= chars.count {
            guard Array(chars[i..<(i + needle.count)]) == needle else { i += 1; continue }
            var j = i + needle.count
            while j < chars.count, chars[j].isWhitespace { j += 1 }
            // A literal, but not a multi-line `"""` one.
            if j < chars.count, chars[j] == "\"",
               !(j + 2 < chars.count && chars[j + 1] == "\"" && chars[j + 2] == "\""),
               let (literal, end) = parseLiteral(chars, from: j + 1) {
                results.append(literal)
                i = end
            } else {
                i = j
            }
        }
        return results
    }

    /// Parses from just after an opening quote to its closing quote.
    private static func parseLiteral(_ chars: [Character], from start: Int) -> (String, Int)? {
        var out = ""
        var k = start
        while k < chars.count {
            let c = chars[k]
            if c == "\"" { return (out, k + 1) }
            if c == "\n" { return nil }
            if c == "\\", k + 1 < chars.count {
                let next = chars[k + 1]
                switch next {
                case "(":
                    guard let end = skipInterpolation(chars, from: k + 2) else { return nil }
                    out.append(placeholder)
                    k = end
                    continue
                case "n": out.append("\n")
                case "t": out.append("\t")
                case "0": out.append("\0")
                case "u":
                    guard let (scalar, end) = parseUnicodeEscape(chars, from: k + 2) else { return nil }
                    out.append(scalar)
                    k = end
                    continue
                default: out.append(next)   // \" \\ \'
                }
                k += 2
                continue
            }
            out.append(c)
            k += 1
        }
        return nil
    }

    /// From just after `\(`, returns the index after the matching `)`,
    /// skipping nested parentheses and string literals inside it.
    private static func skipInterpolation(_ chars: [Character], from start: Int) -> Int? {
        var depth = 1
        var k = start
        while k < chars.count {
            switch chars[k] {
            case "(": depth += 1
            case ")":
                depth -= 1
                if depth == 0 { return k + 1 }
            case "\"":
                guard let (_, end) = parseLiteral(chars, from: k + 1) else { return nil }
                k = end
                continue
            default: break
            }
            k += 1
        }
        return nil
    }

    /// From just after `\u`, parses `{hex}`.
    private static func parseUnicodeEscape(_ chars: [Character], from start: Int) -> (Character, Int)? {
        guard start < chars.count, chars[start] == "{",
              let close = chars[start...].firstIndex(of: "}"),
              let value = UInt32(String(chars[(start + 1)..<close]), radix: 16),
              let scalar = Unicode.Scalar(value) else { return nil }
        return (Character(scalar), close + 1)
    }
}
