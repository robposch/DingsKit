// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DingsKit",
    defaultLocalization: "en",
    platforms: [.iOS(.v17), .macOS(.v14), .watchOS(.v10), .visionOS(.v1)],
    products: [
        .library(name: "DingsKit", targets: ["DingsKit"]),
        .library(name: "DingsKitUI", targets: ["DingsKitUI"]),
        .library(name: "DingsKitTestSupport", targets: ["DingsKitTestSupport"]),
        // For UI test bundles only: drives the iOS Home Screen, widget
        // editor and system prompts.
        .library(name: "DingsKitUITesting", targets: ["DingsKitUITesting"]),
    ],
    targets: [
        .target(name: "DingsKit", resources: [.process("Resources")]),
        .target(name: "DingsKitUI", dependencies: ["DingsKit"]),
        .target(name: "DingsKitTestSupport", dependencies: ["DingsKit"]),
        .target(name: "DingsKitUITesting"),
        .testTarget(name: "DingsKitTests", dependencies: ["DingsKit", "DingsKitTestSupport"]),
    ]
)
