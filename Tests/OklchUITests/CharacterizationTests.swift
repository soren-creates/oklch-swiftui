// Tests/OklchUITests/CharacterizationTests.swift
//
// Tier 5 (ARCHITECTURE.md §5.5). One test per environment input, each proving the OUTPUT
// changes — not merely that the input was readable.
//
// These assert Apple's behaviour, not ours, so they cannot be specified in
// advance (ARCHITECTURE.md §5.7). Green here means "SwiftUI still does what we measured in
// July 2026" — a regression signal, not a specification.
import XCTest
import SwiftUI
@testable import OklchUI
import OklchCore

@available(iOS 17.0, macOS 14.0, *)
@MainActor
final class CharacterizationTests: XCTestCase {

    /// P-TOL-1: Color.Resolved is Float32-backed. The literal itself lives in
    /// `TestTolerances.swift`'s `resolvedFloat32Tolerance`, shared with
    /// `ResolveTests`.
    private let tolerance = resolvedFloat32Tolerance

    private let style = OklchStyle(Oklch(lightness: 0.55, chroma: 0.12, hue: 250))
        .dark(Oklch(lightness: 0.85, chroma: 0.09, hue: 250))
        .increasedContrast(light: Oklch(lightness: 0.25, chroma: 0.16, hue: 250),
                           dark: Oklch(lightness: 0.97, chroma: 0.10, hue: 250))

    private func differs(_ a: Color.Resolved, _ b: Color.Resolved) -> Bool {
        abs(Double(a.red) - Double(b.red)) > tolerance
            || abs(Double(a.green) - Double(b.green)) > tolerance
            || abs(Double(a.blue) - Double(b.blue)) > tolerance
    }

    func testColorSchemeChangesTheResolvedColour() throws {
        let light = try HostedRenderer.capture(style) {
            AnyView($0.environment(\.colorScheme, .light))
        }
        let dark = try HostedRenderer.capture(style) {
            AnyView($0.environment(\.colorScheme, .dark))
        }

        XCTAssertEqual(light.scheme, .light)
        XCTAssertEqual(dark.scheme, .dark)
        XCTAssertTrue(differs(light.resolved, dark.resolved),
            "colorScheme changed but the resolved colour did not")
    }

    func testColorGamutChangesTheResolvedColour() throws {
        let wide = OklchStyle(Oklch(lightness: 0.87, chroma: 0.28, hue: 142.5))

        let srgb = try HostedRenderer.capture(wide) {
            AnyView($0.colorGamut(.sRGB))
        }
        let p3 = try HostedRenderer.capture(wide) {
            AnyView($0.colorGamut(.displayP3))
        }

        XCTAssertEqual(srgb.gamut, .sRGB)
        XCTAssertEqual(p3.gamut, .displayP3)
        XCTAssertTrue(differs(srgb.resolved, p3.resolved),
            "colorGamut changed but the resolved colour did not")
    }

    /// The contrast input cannot be varied in-process (P-ENV-1: the key is a
    /// read-only KeyPath). This test records what the CURRENT system setting
    /// produces; `Tools/run-characterization.sh` runs the suite once per
    /// setting and diffs the two recordings.
    func testColorSchemeContrastIsObservedAndRecorded() throws {
        let observed = try HostedRenderer.capture(style)

        let record: [String: Any] = [
            "probe": "C-contrast",
            "contrast_seen": "\(observed.contrast)",
            "resolved_red": Double(observed.resolved.red),
            "resolved_green": Double(observed.resolved.green),
            "resolved_blue": Double(observed.resolved.blue),
        ]
        if let data = try? JSONSerialization.data(withJSONObject: record,
                                                  options: [.sortedKeys]) {
            print("CHARACTERIZATION \(String(decoding: data, as: UTF8.self))")
        }

        // The suite must at least see a real value; the cross-setting
        // comparison is the runner's job.
        XCTAssertTrue(observed.contrast == .standard || observed.contrast == .increased)
    }
}
