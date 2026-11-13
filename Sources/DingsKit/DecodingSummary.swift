import Foundation

/// One short phrase for a failed decode, for error messages people read.
/// `DecodingError`'s own description is a multi-line dump of coding keys and
/// contexts; this keeps only what helps: which field, and what was wrong.
public func decodingSummary(_ error: Error) -> String {
    guard let error = error as? DecodingError else { return error.localizedDescription }
    func path(_ context: DecodingError.Context, appending key: CodingKey? = nil) -> String {
        let keys = context.codingPath + (key.map { [$0] } ?? [])
        return keys.map { $0.intValue.map(String.init) ?? $0.stringValue }.joined(separator: ".")
    }
    switch error {
    case .keyNotFound(let key, let context):
        return "missing field ‘\(path(context, appending: key))’"
    case .typeMismatch(_, let context):
        return "unexpected value at ‘\(path(context))’"
    case .valueNotFound(_, let context):
        return "missing value at ‘\(path(context))’"
    case .dataCorrupted(let context):
        return context.codingPath.isEmpty ? "not valid JSON" : "unreadable value at ‘\(path(context))’"
    @unknown default:
        return "unexpected format"
    }
}
