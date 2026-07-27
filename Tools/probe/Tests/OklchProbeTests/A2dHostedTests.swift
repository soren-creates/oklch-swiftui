// Tools/probe/Tests/OklchProbeTests/A2dHostedTests.swift
//
// A2d: the decider for A2b, added during the probe run.
//
// A2c established that the Increase Contrast setting DOES reach the test
// process (UIKit reports isDarkerSystemColorsEnabled == true and
// accessibilityContrast == high) while resolve(in:) under ImageRenderer still
// reports .standard. That narrows the cause but does not settle it, because
// ImageRenderer is an off-screen renderer that builds its own environment.
//
// This probe renders through a REAL view hierarchy — UIHostingController inside
// a UIWindow — which is the path an actual app uses. The comparison between
// this result and A2b's is what licenses a conclusion:
//
//   hosted sees .increased  -> ImageRenderer is the limitation (cause ii).
//                              ARCHITECTURE.md §4.2 stands; the probe method was wrong.
//   hosted sees .standard   -> SwiftUI does not deliver the trait to resolve
//                              at all (cause i). ARCHITECTURE.md §4.2 must be amended.
import XCTest
import SwiftUI
@testable import OklchProbe
#if canImport(UIKit)
import UIKit
#endif

@available(iOS 17.0, macOS 14.0, *)
@MainActor
final class A2dHostedTests: XCTestCase {

    func testHostedHierarchyContrastReachesResolve() throws {
        #if canImport(UIKit)
        let log = RecordingStyle.Log()
        let view = Rectangle()
            .fill(RecordingStyle(log: log))
            .frame(width: 8, height: 8)

        let host = UIHostingController(rootView: view)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 64, height: 64))
        window.rootViewController = host
        window.makeKeyAndVisible()

        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()

        // Force the layer tree to actually draw, so resolve(in:) must run.
        let renderer = UIGraphicsImageRenderer(bounds: window.bounds)
        _ = renderer.image { ctx in
            window.layer.render(in: ctx.cgContext)
        }

        let seen = log.calls.first.map { "\($0.contrast)" } ?? "resolve-never-called"

        var windowTraitContrast = "n/a"
        switch window.traitCollection.accessibilityContrast {
        case .high:        windowTraitContrast = "high"
        case .normal:      windowTraitContrast = "normal"
        case .unspecified: windowTraitContrast = "unspecified"
        @unknown default:  windowTraitContrast = "unknown"
        }

        Evidence.record("A2d-hosted", [
            "seen_by_resolve": seen,
            "resolve_call_count": log.calls.count,
            "window_trait_accessibility_contrast": windowTraitContrast,
            "render_path": "UIHostingController in UIWindow",
        ])

        XCTAssertGreaterThan(log.calls.count, 0,
            "resolve(in:) was never invoked in the hosted hierarchy")
        #else
        throw XCTSkip("UIKit-only probe")
        #endif
    }
}
