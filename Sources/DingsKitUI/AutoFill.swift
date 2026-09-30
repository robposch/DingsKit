#if canImport(UIKit) && !os(watchOS) // iOS and visionOS: watchOS has UIKit but lacks APIs this group of views uses
import SwiftUI

/// Maps a credential form's fields onto the username/password pair that iOS
/// Password AutoFill understands, so saved items for the app's associated
/// domains are offered on these forms and iOS can offer to save them the first
/// time they're entered.
///
/// None of these providers issue a username and a password. They issue keys —
/// sometimes one, sometimes two, sometimes three. AutoFill has no vocabulary
/// for that, so we map by *position* rather than by meaning: the first field is
/// the thing you identify the credential by, the second is the secret. That is
/// semantically loose (a provider's application key is not a "username") but it
/// is the only shape a password manager can store and re-offer as one item.
public enum AutoFill {
    /// - Parameters:
    ///   - position: index of the field in the provider's form.
    ///   - total: how many fields the form has.
    public static func contentType(at position: Int, of total: Int) -> UITextContentType? {
        // A lone key has nothing to pair with. Calling it `.password` still lets
        // a manager offer saved secrets; iOS won't prompt to save it, because it
        // has no username to file it under.
        guard total > 1 else { return position == 0 ? .password : nil }

        switch position {
        case 0: return .username
        case 1: return .password
        // Anything further (e.g. a provider's refresh token) has no AutoFill role.
        // Claiming a second `.password` would make the manager offer the wrong
        // secret for it.
        default: return nil
        }
    }
}
#endif
