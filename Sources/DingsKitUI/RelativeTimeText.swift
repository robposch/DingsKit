import SwiftUI

/// Re-renders `content` on a coarse periodic cadence, so relative-time text
/// inside it stays honest as time passes.
///
/// This exists instead of SwiftUI's self-ticking `Text(_:style:)`, which
/// re-lays-out every second: that style caused a real hang in one of the
/// apps built on this kit (TextKit re-layout driven through
/// NotificationCenter on every tick). A `TimelineView`
/// that fires far less often, wrapping an ordinary `Text(date, format:
/// .relative(presentation: .named))`, gets the same live-updating result at
/// the render cost of a ten-second timer instead of a one-second one.
///
/// App screens only. Widgets keep `style: .relative` on purpose: a widget's
/// timeline already reloads on its own schedule and does not pay this
/// project's app-render cost model, so there is nothing to fix there.
public struct PeriodicRelativeView<Content: View>: View {
    /// How often the wrapped content re-evaluates. Ten seconds keeps
    /// "just now" and "a few seconds ago" honest during a screen visit
    /// without re-rendering every second: relative-time strings step through
    /// coarse buckets (seconds, then minutes, then hours, then days), so
    /// anything finer than a few seconds buys nothing the user can see, while
    /// still being frequent enough that a value never reads as frozen.
    public static var defaultInterval: TimeInterval { 10 }

    private let interval: TimeInterval
    private let content: () -> Content

    public init(
        interval: TimeInterval = Self.defaultInterval,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.interval = interval
        self.content = content
    }

    public var body: some View {
        TimelineView(.periodic(from: .now, by: interval)) { _ in
            content()
        }
    }
}

/// A relative time string ("5 minutes ago") for app screens, kept current on
/// `PeriodicRelativeView`'s cadence instead of self-ticking every second.
/// A drop-in replacement for `Text(date, format: .relative(presentation:
/// .named))` wherever that value is expected to stay visible and correct for
/// more than a moment, such as a Settings sheet with no other reason to
/// re-render.
public struct RelativeTimeText: View {
    private let date: Date

    public init(_ date: Date) {
        self.date = date
    }

    public var body: some View {
        PeriodicRelativeView {
            Text(date, format: .relative(presentation: .named))
        }
    }
}
