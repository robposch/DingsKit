#if os(iOS)
import Testing
import SwiftUI
import UIKit

/// Compares a rendered view with its reference image in `References/`.
///
/// A missing reference is recorded and the test fails once, so a new screen
/// never passes unseen; look at the recorded image, then run again. Set
/// `SNAPSHOT_RECORD=1` (with xcodebuild: `TEST_RUNNER_SNAPSHOT_RECORD=1`) to
/// record every reference anew after an intended change.
@MainActor
enum Snapshot {
    /// iPhone 17 Pro width in points, at 2× to keep the images small.
    static let width: CGFloat = 402
    static let scale: CGFloat = 2

    static func referenceURL(_ name: String) -> URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("References/\(name).png")
    }

    static func assert(_ view: some View, named name: String, height: CGFloat? = nil,
                       sourceLocation: SourceLocation = #_sourceLocation) {
        let content = view
            .frame(width: width, height: height)
            .fixedSize(horizontal: false, vertical: height == nil)
            .background(Color(uiColor: .systemGroupedBackground))
            .environment(\.colorScheme, .light)
            .environment(\.locale, Locale(identifier: "en_US"))
            .environment(\.dynamicTypeSize, .large)
        guard let image = render(content, height: height), let png = image.pngData() else {
            Issue.record("\(name): rendering produced no image", sourceLocation: sourceLocation)
            return
        }
        let url = referenceURL(name)
        let recordAll = ProcessInfo.processInfo.environment["SNAPSHOT_RECORD"] == "1"
        guard !recordAll, let reference = UIImage(contentsOfFile: url.path) else {
            try? png.write(to: url)
            Issue.record("\(name): recorded a new reference at \(url.path); check it and run again",
                         sourceLocation: sourceLocation)
            return
        }
        if let difference = Self.difference(image, reference) {
            let actual = url.deletingPathExtension().appendingPathExtension("actual.png")
            try? png.write(to: actual)
            Issue.record("\(name): \(difference); the rendering is at \(actual.path)", sourceLocation: sourceLocation)
        }
    }

    /// Draws the view through a hosting controller in a window. SwiftUI's
    /// `ImageRenderer` leaves lists and scroll views blank, since UIKit draws
    /// those; this draws what the screen would show.
    private static func render(_ content: some View, height: CGFloat?) -> UIImage? {
        let host = UIHostingController(rootView: content)
        // No status bar or home indicator margins: they differ between
        // devices and would shift every image.
        host.safeAreaRegions = []
        let fitted = height.map { CGSize(width: width, height: $0) }
            ?? host.sizeThatFits(in: CGSize(width: width, height: .greatestFiniteMagnitude))
        let bounds = CGRect(origin: .zero, size: CGSize(width: width, height: ceil(fitted.height)))
        let window = UIWindow(frame: bounds)
        window.rootViewController = host
        window.isHidden = false
        host.view.frame = bounds
        host.view.layoutIfNeeded()
        // Lists fill their rows on the next turns of the run loop.
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        host.view.layoutIfNeeded()
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        // Rendering the layers rather than `drawHierarchy`: a test bundle has
        // no screen, and `drawHierarchy` draws nothing without one.
        let image = UIGraphicsImageRenderer(bounds: bounds, format: format).image { context in
            host.view.layer.render(in: context.cgContext)
        }
        window.isHidden = true
        return image
    }

    /// `nil` when the images match. Allows a sliver of anti-aliasing noise,
    /// not a changed word or layout.
    static func difference(_ a: UIImage, _ b: UIImage) -> String? {
        guard let pa = rgba(a), let pb = rgba(b) else { return "could not read the pixels" }
        guard pa.width == pb.width, pa.height == pb.height else {
            return "size \(pa.width)×\(pa.height) instead of \(pb.width)×\(pb.height)"
        }
        var differing = 0
        for i in stride(from: 0, to: pa.bytes.count, by: 4) {
            let delta = (0..<4).map { abs(Int(pa.bytes[i + $0]) - Int(pb.bytes[i + $0])) }.max() ?? 0
            if delta > 24 { differing += 1 }
        }
        let share = Double(differing) / Double(pa.width * pa.height)
        return share > 0.001 ? String(format: "%.2f%% of the pixels differ", share * 100) : nil
    }

    private static func rgba(_ image: UIImage) -> (bytes: [UInt8], width: Int, height: Int)? {
        guard let cg = image.cgImage else { return nil }
        let width = cg.width, height = cg.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(data: &bytes, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
        return (bytes, width, height)
    }
}
#endif
