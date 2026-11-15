import SwiftUI

/// Side by side at ordinary text sizes, stacked at the accessibility sizes.
///
/// A label and a value next to each other share one line. At the largest
/// text sizes that line is too short for both, so each wraps inside its
/// words ("Ra / don", "Avail- / able"). Stacked, each gets the full width,
/// which is what Apple's own apps do at these sizes.
public struct AdaptiveStack<Content: View>: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    private let spacing: CGFloat?
    private let content: Content

    public init(spacing: CGFloat? = nil, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    public var body: some View {
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: spacing ?? 4) { content }
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            HStack(spacing: spacing) { content }
        }
    }
}

#if !os(watchOS)
/// A segmented picker at ordinary text sizes, a list of rows at the
/// accessibility sizes. A segmented control's text does not grow with the
/// user's text size; rows do.
public struct SegmentedOrInlinePickerStyle: ViewModifier {
    @Environment(\.dynamicTypeSize) private var typeSize

    public init() {}

    public func body(content: Content) -> some View {
        if typeSize.isAccessibilitySize {
            content.pickerStyle(.inline)
        } else {
            content.pickerStyle(.segmented)
        }
    }
}

public extension View {
    /// See `SegmentedOrInlinePickerStyle`.
    func segmentedOrInlinePickerStyle() -> some View {
        modifier(SegmentedOrInlinePickerStyle())
    }
}
#endif
