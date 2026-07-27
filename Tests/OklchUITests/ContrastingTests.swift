import XCTest
import SwiftUI
@testable import OklchUI
import OklchCore

@available(iOS 17.0, macOS 14.0, *)
@MainActor
final class ContrastingTests: XCTestCase {

    private func env(backdrop: Oklch?, gamut: Gamut = .sRGB) -> EnvironmentValues {
        var e = EnvironmentValues()
        e.colorGamut = gamut
        e.themeBackground = backdrop
        return e
    }

    func testContrastingMeetsWCAGTargetAgainstExplicitBackdrop() {
        let backdrop = Oklch(lightness: 1.0, chroma: 0, hue: 0)
        let style = OklchStyle.contrasting(.wcag(4.5), hue: 250, chroma: 0.1,
                                           against: .explicit(backdrop))
        let colour = style.resolve(in: env(backdrop: nil))

        // Re-measure through OklchCore rather than trusting the style.
        let resolved = colour.resolve(in: env(backdrop: nil))
        let asOklch = rgbToOklch(RGB(red: Double(resolved.red),
                                     green: Double(resolved.green),
                                     blue: Double(resolved.blue)), in: .sRGB)
        XCTAssertGreaterThanOrEqual(wcagContrast(asOklch, backdrop, in: .sRGB), 4.5 - 0.05)
    }

    func testContrastingReadsTheEnvironmentBackdrop() {
        let style = OklchStyle.contrasting(.wcag(7), hue: 30, chroma: 0.05)

        let onWhite = style.resolve(in: env(backdrop: Oklch(lightness: 1, chroma: 0, hue: 0)))
        let onBlack = style.resolve(in: env(backdrop: Oklch(lightness: 0, chroma: 0, hue: 0)))

        let w = onWhite.resolve(in: EnvironmentValues())
        let b = onBlack.resolve(in: EnvironmentValues())
        let delta = abs(Double(w.red) - Double(b.red))
            + abs(Double(w.green) - Double(b.green))
            + abs(Double(w.blue) - Double(b.blue))
        XCTAssertGreaterThan(delta, 0.05,
            "backdrop changed but the solved colour barely moved — "
            + "contrasting is probably not reading \\.themeBackground")
    }

    /// ARCHITECTURE.md §4.6: unreachable targets never crash, always draw, and report.
    func testUnreachableTargetFiresDiagnosticAndStillDraws() {
        final class Box: @unchecked Sendable { var seen: ContrastResolution? }
        let box = Box()

        var e = env(backdrop: Oklch(lightness: 0.5, chroma: 0, hue: 0))
        e.oklchDiagnostics = { box.seen = $0 }

        let style = OklchStyle.contrasting(.apca(120), hue: 200, chroma: 0.2)
        let colour = style.resolve(in: e)
        let r = colour.resolve(in: e)

        XCTAssertNotNil(box.seen, "unreachable target did not fire the diagnostic")
        if let seen = box.seen {
            XCTAssertLessThan(seen.achieved, seen.requested)
        }
        // Still drew something in gamut.
        XCTAssertGreaterThanOrEqual(Double(r.red), -1e-5)
        XCTAssertLessThanOrEqual(Double(r.red), 1 + 1e-5)
    }

    func testReachableTargetDoesNotFireDiagnostic() {
        final class Box: @unchecked Sendable { var fired = false }
        let box = Box()

        var e = env(backdrop: Oklch(lightness: 1, chroma: 0, hue: 0))
        e.oklchDiagnostics = { _ in box.fired = true }

        _ = OklchStyle.contrasting(.wcag(4.5), hue: 250, chroma: 0.05).resolve(in: e)
        XCTAssertFalse(box.fired, "a reachable target fired the shortfall diagnostic")
    }

    /// CRITICAL regression found in review: `ContrastRequest.solve(in:)`
    /// used to pass the RAW backdrop straight to `solveContrast`'s `against:`
    /// without gamut-mapping it first. `solveContrast` always gamut-maps every
    /// CANDIDATE before measuring (ARCHITECTURE.md §4.5), but the backdrop side had no
    /// equivalent guarantee — and `resolve(in:)` draws
    /// `gamutMap(chosen, to: gamut)`, so an out-of-gamut backdrop was being
    /// measured against a colour the screen never actually shows.
    ///
    /// Fixture is the measured worst case: backdrop
    /// `L=0.25 C=0.30 h=285` (out of sRGB), target `.wcag(7)`. Before the fix,
    /// the solver reported `isSatisfied == true` while the ACTUAL contrast
    /// against the drawn (gamut-mapped) backdrop was only `5.668` — a 1.332
    /// shortfall. This test re-measures the solved colour against the backdrop
    /// AS DRAWN and asserts the target really is achieved.
    func testSolveMeasuresAgainstTheDrawnBackdropNotTheRawOne() {
        let outOfGamutBackdrop = Oklch(lightness: 0.25, chroma: 0.30, hue: 285)
        let request = ContrastRequest(target: .wcag(7), hue: 250, chroma: 0.1,
                                      direction: .automatic,
                                      backdrop: .explicit(outOfGamutBackdrop))
        let solved = request.solve(in: env(backdrop: nil, gamut: .sRGB))

        // The backdrop as it is actually drawn — resolve(in:) never shows the
        // raw, unmapped backdrop, so measuring against anything else is the
        // exact defect class this package exists to prevent.
        let drawnBackdrop = gamutMap(outOfGamutBackdrop, to: .sRGB)
        let achieved = wcagContrast(solved, drawnBackdrop, in: .sRGB)

        XCTAssertGreaterThanOrEqual(achieved, 7.0 - 0.05,
            "solved colour does not meet the target against the backdrop as actually drawn — "
            + "the solver is measuring against a colour the screen never shows")
    }

    /// IMPORTANT: `.dark(_:)` and
    /// `.increasedContrast(light:dark:)` both `guard case .fixed(var v) =
    /// source else { return self }` — on a `.contrasting` style, that guard
    /// fails and the call silently returns the receiver unchanged. No compile
    /// error, no runtime signal. Not fixed here (trapping this in the type
    /// system would be a breaking API change, out of scope for v1) —
    /// this test only pins the documented no-op so a future change to that
    /// behaviour is a deliberate, visible decision rather than an accident.
    func testDarkAndIncreasedContrastAreNoOpsOnAContrastingStyle() {
        let original = OklchStyle.contrasting(.wcag(4.5), hue: 250, chroma: 0.1)

        let afterDark = original.dark(Oklch(lightness: 0.1, chroma: 0.2, hue: 10))
        XCTAssertEqual(afterDark, original,
            ".dark(_:) silently discarded its argument on a .fixed style, or changed behaviour "
            + "on a .contrasting one — this test only pins the CURRENT no-op")

        let afterIncreased = original.increasedContrast(
            light: Oklch(lightness: 0.9, chroma: 0.01, hue: 10),
            dark: Oklch(lightness: 0.1, chroma: 0.2, hue: 10))
        XCTAssertEqual(afterIncreased, original,
            ".increasedContrast(light:dark:) silently discarded its arguments on a .contrasting "
            + "style — this test only pins the CURRENT no-op")
    }

    /// With no backdrop published and none given, fall back to white rather
    /// than crashing — and produce a colour that actually meets the target
    /// against that fallback, so the fallback is real rather than nominal.
    func testMissingBackdropFallsBackToWhiteAndStillMeetsTarget() {
        let style = OklchStyle.contrasting(.wcag(4.5), hue: 250, chroma: 0.05)
        let r = style.resolve(in: env(backdrop: nil)).resolve(in: env(backdrop: nil))

        let asOklch = rgbToOklch(RGB(red: Double(r.red),
                                     green: Double(r.green),
                                     blue: Double(r.blue)), in: .sRGB)
        let white = ContrastRequest.fallbackBackdrop
        XCTAssertGreaterThanOrEqual(wcagContrast(asOklch, white, in: .sRGB), 4.5 - 0.05,
            "the no-backdrop fallback did not actually meet the target against white")
    }
}
