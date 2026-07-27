// swift-tools-version: 5.9
// Generates docs/assets/why-late-{light,dark}.svg — the README's eager-vs-late
// comparison — from OklchCore's own pipeline. Same pattern as gen-fixtures:
// the tool generates, DocExampleTests verifies the committed artifact.
import PackageDescription

let package = Package(
    name: "readme-swatches",
    platforms: [.macOS(.v14)],
    dependencies: [.package(name: "oklch-swiftui", path: "../..")],
    targets: [
        .executableTarget(
            name: "readme-swatches",
            dependencies: [.product(name: "OklchCore", package: "oklch-swiftui")]),
    ]
)
