// swift-tools-version: 5.9
// Tools/probe/Package.swift
import PackageDescription

let package = Package(
    name: "OklchProbe",
    platforms: [.iOS(.v17), .macOS(.v14)],
    targets: [
        .target(name: "OklchProbe"),
        .testTarget(name: "OklchProbeTests", dependencies: ["OklchProbe"]),
    ]
)
