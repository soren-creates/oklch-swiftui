// Tools/probe/Tests/OklchProbeTests/A4TraitTests.swift
import XCTest
import SwiftUI
@testable import OklchProbe

@available(iOS 17.0, macOS 14.0, *)
@MainActor
final class A4TraitTests: XCTestCase {

    func testTraitCollectionInsideResolve() {
        let log = RecordingStyle.Log()
        let outside = RecordingStyle.currentGamut()

        let view = Rectangle()
            .fill(RecordingStyle(log: log))
            .frame(width: 8, height: 8)

        let renderer = ImageRenderer(content: view)
        _ = renderer.cgImage

        let inside = log.calls.first?.gamut ?? "resolve-never-called"

        Evidence.record("A4", [
            "gamut_inside_resolve": inside,
            "gamut_outside_resolve": outside,
            "resolve_call_count": log.calls.count,
        ])

        XCTAssertGreaterThan(log.calls.count, 0, "resolve(in:) was never invoked")
    }
}
