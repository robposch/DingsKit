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
    ],
    targets: [
        .target(name: "DingsKit", resources: [.process("Resources")]),
        .target(name: "DingsKitUI", dependencies: ["DingsKit"]),
        .target(name: "DingsKitTestSupport", dependencies: ["DingsKit"]),
        .testTarget(name: "DingsKitTests", dependencies: ["DingsKit", "DingsKitTestSupport"]),
    ]
)
