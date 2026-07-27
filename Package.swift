// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "oklch-swiftui",
    platforms: [.iOS(.v17), .macOS(.v14), .tvOS(.v17), .visionOS(.v1), .watchOS(.v10)],
    products: [
        .library(name: "OklchCore", targets: ["OklchCore"]),
        .library(name: "OklchUI", targets: ["OklchUI"]),
    ],
    targets: [
        // No SwiftUI, no UIKit — see ARCHITECTURE.md §4.1. This target must build on Linux.
        .target(name: "OklchCore"),
        .testTarget(name: "OklchCoreTests", dependencies: ["OklchCore"]),
        // SwiftUI only. OklchCore must NOT gain a dependency on this.
        .target(name: "OklchUI", dependencies: ["OklchCore"]),
        .testTarget(name: "OklchUITests", dependencies: ["OklchUI", "OklchCore"]),
    ]
)
