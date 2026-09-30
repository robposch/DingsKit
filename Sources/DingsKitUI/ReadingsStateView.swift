import SwiftUI
import DingsKit

/// The three non-loaded states a readings screen can be in. `.loaded` is not
/// one of these cases on purpose: once there is data, the screen renders
/// `ReadingsListView` instead, so this type only ever covers the states that
/// have no rows to show.
public enum ReadingsScreenState {
    case loading
    /// No devices at all. `systemImage` and `title`/`description` are
    /// parameters because "No devices" and "sensor" fit one app, "No shared
    /// readings" and "person.2.slash" the other.
    case empty(title: String, systemImage: String, description: String)
    case failed(message: String)
}

/// Renders whichever of the three non-loaded states a readings screen is in.
/// `loading` and the "couldn't load" heading/icon are identical wording on
/// both current screens, so they're originated here rather than threaded
/// through as parameters; `empty`'s title, icon and description differ per
/// app and stay parameters on `ReadingsScreenState` itself.
public struct ReadingsStateView: View {
    private let state: ReadingsScreenState
    private let retry: () -> Void

    public init(state: ReadingsScreenState, retry: @escaping () -> Void) {
        self.state = state
        self.retry = retry
    }

    public var body: some View {
        switch state {
        case .loading:
            ProgressView(coreLocalized("Loading…"))
        case .empty(let title, let systemImage, let description):
            ContentUnavailableView(title, systemImage: systemImage, description: Text(description))
        case .failed(let message):
            ContentUnavailableView {
                Label(coreLocalized("Couldn’t load"), systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button(coreLocalized("Retry"), action: retry)
            }
        }
    }
}
