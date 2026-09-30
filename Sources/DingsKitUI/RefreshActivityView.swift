#if canImport(UIKit) && !os(watchOS) // iOS and visionOS: watchOS has UIKit but lacks APIs this group of views uses
import SwiftUI
import DingsKit

/// The refresh log on its own screen. It's the first thing to check when a
/// widget looks stale, but at up to `BackgroundRunLog.maxEntries` rows it is
/// long, so it sits behind a row in Settings instead of pushing the sections
/// below it out of reach.
///
/// Shared by every app on top of `BackgroundRunLog`: the log itself, the
/// runs it holds, and the wording describing them are all mechanism, not app
/// vocabulary, so this view lives here instead of being duplicated per app.
public struct RefreshActivityView: View {
    @Binding private var runs: [RefreshRun]

    public init(runs: Binding<[RefreshRun]>) {
        self._runs = runs
    }

    public var body: some View {
        List {
            Section {
                if runs.isEmpty {
                    Text(coreLocalized("No refreshes recorded yet."))
                        .font(.footnote).foregroundStyle(.secondary)
                } else {
                    ForEach(runs.indices, id: \.self) { i in
                        let run = runs[i]
                        HStack(spacing: 10) {
                            // Success/failure is carried by this icon alone: the row's
                            // text is the source and the time. Without a label a
                            // VoiceOver user never learns the refresh failed.
                            Image(systemName: run.succeeded ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                .foregroundStyle(run.succeeded ? .green : .orange)
                                .accessibilityLabel(run.succeeded ? Text(coreLocalized("Succeeded")) : Text(coreLocalized("Failed")))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(Self.sourceLabel(run.source))
                                if let detail = run.detail {
                                    Text(detail).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            RelativeTimeText(run.date)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } footer: {
                Text(coreLocalized("Which path last fetched data. “Background” runs while the app is closed or the device is locked. iOS throttles these to a few times a day."))
            }

            if !runs.isEmpty {
                Section {
                    Button(coreLocalized("Clear log"), role: .destructive) {
                        BackgroundRunLog()?.clear()
                        runs = []
                    }
                    .accessibilityIdentifier("refreshActivity.clear")
                }
            }
        }
        .navigationTitle(coreLocalized("Refresh activity"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private static func sourceLabel(_ source: RefreshSource) -> String {
        switch source {
        case .backgroundTask: return coreLocalized("Background")
        case .widgetTimeline: return coreLocalized("Widget")
        case .appForeground: return coreLocalized("App open")
        }
    }
}
#endif
