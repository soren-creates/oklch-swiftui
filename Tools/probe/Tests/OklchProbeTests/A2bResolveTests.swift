// Tools/probe/Tests/OklchProbeTests/A2bResolveTests.swift
import XCTest
import SwiftUI
@testable import OklchProbe

@available(iOS 17.0, macOS 14.0, *)
@MainActor
final class A2bResolveTests: XCTestCase {

    private func render(into log: RecordingStyle.Log) {
        let view = Rectangle()
            .fill(RecordingStyle(log: log))
            .frame(width: 8, height: 8)

        _ = ImageRenderer(content: view).cgImage
    }

    /// Path 1: explicit environment override — UNAVAILABLE on this toolchain.
    ///
    /// The plan anticipated a runtime skip here, but a non-settable environment
    /// key is a *compile* error, not a runtime condition: writing the override
    /// would fail the build for the whole target and take A3/A4/A5 down with it.
    /// Compile probe A2a is the authority and reported `false` —
    /// `\.colorSchemeContrast` is a read-only `KeyPath`, not a `WritableKeyPath`.
    ///
    /// This is recorded rather than deleted so the evidence file states that the
    /// path was unavailable, not merely unmeasured.
    func testOverridePropagatesToResolve() throws {
        Evidence.record("A2b-override", [
            "override_path_available": false,
            "reason": "colorSchemeContrast is a read-only KeyPath, not WritableKeyPath",
            "authority": "compile probe A2a",
        ])

        throw XCTSkip("""
            \\.colorSchemeContrast is not settable via .environment(_:_:) on \
            Xcode 26.6 / Swift 6.3.3. See docs/evidence/2026-07-25-compile-probes.json \
            (a2a_contrast_settable = false). The system-setting path below is the \
            only measurable route.
            """)
    }

    /// Path 2: the real system setting. The suite is run twice by
    /// run-app-probes.sh with simctl toggling Increase Contrast between runs;
    /// this records what resolve saw on each run.
    func testSystemContrastReachesResolve() {
        let log = RecordingStyle.Log()
        render(into: log)

        let seen = log.calls.first.map { "\($0.contrast)" } ?? "resolve-never-called"

        Evidence.record("A2b-system", [
            "seen_by_resolve": seen,
            "resolve_call_count": log.calls.count,
        ])

        XCTAssertGreaterThan(log.calls.count, 0, "resolve(in:) was never invoked")
    }
}
