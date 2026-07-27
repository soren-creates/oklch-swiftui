// Tools/probe/Tests/OklchProbeTests/A5PrecisionTests.swift
import XCTest
import SwiftUI
@testable import OklchProbe

@available(iOS 17.0, macOS 14.0, *)
@MainActor
final class A5PrecisionTests: XCTestCase {

    /// Sweeps a deterministic grid of sRGB components through
    /// Color -> Color.Resolved and records the worst absolute error.
    /// Seed is fixed; no RNG, no wall clock.
    func testResolvedPrecisionFloor() {
        var worst = 0.0
        var worstAt = ""
        let steps = 64

        for i in 0...steps {
            let v = Double(i) / Double(steps)
            let color = Color(.sRGB, red: v, green: v * 0.5, blue: 1 - v, opacity: 1)
            let r = color.resolve(in: EnvironmentValues())

            let errors = [
                abs(Double(r.red) - v),
                abs(Double(r.green) - v * 0.5),
                abs(Double(r.blue) - (1 - v)),
            ]
            if let e = errors.max(), e > worst {
                worst = e
                worstAt = "v=\(v)"
            }
        }

        Evidence.record("A5", [
            "max_roundtrip_error": worst,
            "worst_at": worstAt,
            "grid_steps": steps,
            "component_storage": "Float32",
        ])

        // Float32 has ~7 decimal digits; anything worse means SwiftUI is
        // quantising further and OklchCore tolerances must widen accordingly.
        XCTAssertLessThan(worst, 1e-5, "precision floor worse than Float32 alone")
    }
}
