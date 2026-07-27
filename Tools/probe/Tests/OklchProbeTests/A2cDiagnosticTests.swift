// Tools/probe/Tests/OklchProbeTests/A2cDiagnosticTests.swift
//
// A2c: disambiguation probe, added during the probe run.
//
// A2b measured `seen_by_resolve == "standard"` under BOTH simctl contrast
// settings. The probe plan requires distinguishing two causes before
// any conclusion about ARCHITECTURE.md §4 is drawn:
//
//   (i)  SwiftUI does not propagate the contrast trait to resolve(in:) at all
//        -> architecture failure; §4.2 must drop colorSchemeContrast.
//   (ii) ImageRenderer specifically renders outside the trait environment
//        -> probe limitation; question moves to the on-device harness (§5.6).
//
// This probe reads the same underlying setting through three independent
// channels. If UIKit sees the setting but resolve(in:) does not, the cause is
// (ii). If no channel sees it, the setting never reached the process and
// NEITHER conclusion is licensed by this run.
import XCTest
import SwiftUI
@testable import OklchProbe
#if canImport(UIKit)
import UIKit
#endif

@available(iOS 17.0, macOS 14.0, *)
@MainActor
final class A2cDiagnosticTests: XCTestCase {

    func testContrastChannelsAgree() {
        // Channel 1: UIKit accessibility API — the setting at its source.
        var uikitDarkerColors = "n/a"
        var uikitTraitContrast = "n/a"
        #if canImport(UIKit)
        uikitDarkerColors = "\(UIAccessibility.isDarkerSystemColorsEnabled)"
        switch UITraitCollection.current.accessibilityContrast {
        case .high:        uikitTraitContrast = "high"
        case .normal:      uikitTraitContrast = "normal"
        case .unspecified: uikitTraitContrast = "unspecified"
        @unknown default:  uikitTraitContrast = "unknown"
        }
        #endif

        // Channel 2: a default-constructed EnvironmentValues (no SwiftUI
        // hierarchy at all) — establishes what the type's own default is.
        let bare = "\(EnvironmentValues().colorSchemeContrast)"

        // Channel 3: inside resolve(in:) driven by ImageRenderer.
        let log = RecordingStyle.Log()
        let view = Rectangle()
            .fill(RecordingStyle(log: log))
            .frame(width: 8, height: 8)
        _ = ImageRenderer(content: view).cgImage
        let insideResolve = log.calls.first.map { "\($0.contrast)" } ?? "resolve-never-called"

        Evidence.record("A2c-diagnostic", [
            "uikit_is_darker_system_colors_enabled": uikitDarkerColors,
            "uikit_trait_accessibility_contrast": uikitTraitContrast,
            "bare_environmentvalues_contrast": bare,
            "inside_resolve_contrast": insideResolve,
        ])

        // No assertion on the values: this probe's output IS the deliverable,
        // and both outcomes are informative. Only the harness itself must work.
        XCTAssertGreaterThan(log.calls.count, 0, "resolve(in:) was never invoked")
    }
}
