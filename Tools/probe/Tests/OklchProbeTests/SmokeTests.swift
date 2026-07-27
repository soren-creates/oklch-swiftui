// Tools/probe/Tests/OklchProbeTests/SmokeTests.swift
import XCTest
import SwiftUI
@testable import OklchProbe

/// `@MainActor`: SwiftUI's `ImageRenderer` is main-actor isolated, so every
/// probe that renders must be too. Measured, not assumed — see the build
/// failure recorded in the probe findings.
@MainActor
final class SmokeTests: XCTestCase {
    func testHarnessRunsAndEmitsEvidence() {
        Evidence.record("smoke", ["ok": true])
    }

    func testImageRendererIsAvailable() throws {
        guard #available(iOS 17.0, macOS 14.0, *) else {
            throw XCTSkip("below deployment floor")
        }
        let renderer = ImageRenderer(content: Color.red.frame(width: 4, height: 4))
        XCTAssertNotNil(renderer.cgImage, "ImageRenderer produced no image")
    }
}
