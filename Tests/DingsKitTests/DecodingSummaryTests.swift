import Testing
import Foundation
@testable import DingsKit

/// A raw `DecodingError` dump is several lines of Swift internals; the
/// readings banner and the run log need one short phrase.
@Suite struct DecodingSummaryTests {
    private struct Body: Decodable { let body: Inner }
    private struct Inner: Decodable { let temp: Double }

    private func summary(_ json: String) -> String {
        do {
            _ = try JSONDecoder().decode(Body.self, from: Data(json.utf8))
            return "decoded"
        } catch {
            return decodingSummary(error)
        }
    }

    @Test func missingField() { #expect(summary(#"{}"#) == "missing field ‘body’") }
    @Test func wrongType() { #expect(summary(#"{"body":{"temp":"warm"}}"#) == "unexpected value at ‘body.temp’") }
    @Test func nullValue() { #expect(summary(#"{"body":{"temp":null}}"#) == "missing value at ‘body.temp’") }
    @Test func notJSON() { #expect(summary("<html>") == "not valid JSON") }
    @Test func otherErrorsKeepTheirDescription() {
        #expect(decodingSummary(CocoaError(.fileNoSuchFile)) == CocoaError(.fileNoSuchFile).localizedDescription)
    }
}
