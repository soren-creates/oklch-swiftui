import XCTest
@testable import OklchCore

/// Tier 3 (ARCHITECTURE.md §5.3). Each test is named for a defect found by reading a real
/// library's source during the 2026-07-24/25 survey (ARCHITECTURE.md §2). These are not
/// hypothetical failure modes.
final class RegressionTests: XCTestCase {

    // MARK: B1 — fwrs/OKLCHGradient

    /// Hue was interpolated linearly with no shortest-arc wrap, so red
    /// (h=28.5) to magenta (h=328.4) traversed 300 degrees through yellow,
    /// green, cyan and blue instead of the 60-degree arc.
    func test_B1_hueInterpolationTakesShortestArc_fwrsOKLCHGradient() {
        let red = Oklch(lightness: 0.63, chroma: 0.26, hue: 28.5)
        let magenta = Oklch(lightness: 0.70, chroma: 0.32, hue: 328.4)

        // Midpoint on the short arc sits near 358 degrees, NOT near 178.
        let mid = interpolate(red, magenta, t: 0.5)
        let distanceFromShortPath = abs(shortestHueArc(from: mid.hue, to: 358.45))
        XCTAssertLessThan(distanceFromShortPath, 1.0,
                          "midpoint hue \(mid.hue) is not on the short arc")

        // No sample may pass through the green/cyan region at all.
        for t in stride(from: 0.0, through: 1.0, by: 0.02) {
            let h = interpolate(red, magenta, t: t).hue
            XCTAssertFalse((100...260).contains(h),
                           "t=\(t) produced hue \(h), traversing the long way round")
        }
    }

    // MARK: B2 — fwrs/OKLCHGradient

    /// No powerless-hue rule: `.white` has chroma ~0 and a numerically garbage
    /// hue (89.9), so white to blue lerped 89.9 -> 264.1 and showed a
    /// green/cyan cast mid-gradient.
    func test_B2_powerlessWhiteDoesNotTintGradient_fwrsOKLCHGradient() {
        let white = Oklch(lightness: 1.0, chroma: 0.0, hue: 89.9)
        let blue = Oklch(lightness: 0.45, chroma: 0.31, hue: 264.1)

        for t in stride(from: 0.0, through: 1.0, by: 0.05) {
            let mid = interpolate(white, blue, t: t)
            XCTAssertEqual(mid.hue, blue.hue, accuracy: 1e-9,
                           "white's powerless hue leaked in at t=\(t)")
            // The green region is what the defect actually produced on screen.
            XCTAssertFalse((100...200).contains(mid.hue),
                           "green cast at t=\(t): hue \(mid.hue)")
        }
    }

    // MARK: B3 — nikstar/swift-oklch

    /// The gamma encoder was not sign-symmetric: negative linear channels took
    /// the `12.92 * c` branch, mis-encoding every out-of-gamut colour.
    func test_B3_gammaEncoderIsSignSymmetric_nikstarSwiftOklch() {
        for v in stride(from: 0.0001, through: 1.5, by: 0.017) {
            XCTAssertEqual(Gamut.encode(-v), -Gamut.encode(v), accuracy: 1e-12,
                           "encode asymmetric at -\(v)")
            XCTAssertEqual(Gamut.decode(-v), -Gamut.decode(v), accuracy: 1e-12,
                           "decode asymmetric at -\(v)")
        }

        // The defect's real consequence: a P3 colour outside sRGB has a
        // negative channel, and mis-encoding it corrupts the round trip.
        let p3Green = rgbToOklch(RGB(red: 0, green: 1, blue: 0), in: .displayP3)
        let asSRGB = oklchToRGB(p3Green, in: .sRGB)
        XCTAssertLessThan(asSRGB.red, 0)
        let back = rgbToOklch(asSRGB, in: .sRGB)
        XCTAssertEqual(back.lightness, p3Green.lightness, accuracy: 1e-9)
        XCTAssertEqual(back.hue, p3Green.hue, accuracy: 1e-6)
    }

    // MARK: B4 — danielcr12/OKLCHKit

    /// The deltaE_OK clip guard round-tripped the clipped candidate through
    /// `srgbToOKLCH`, misreading P3 components as sRGB whenever the target
    /// gamut was P3.
    ///
    /// An earlier tolerance here was 0.5 degrees. Measured against
    /// our own (already-correct) `gamutMap`, this exact fixture naturally
    /// drifts 1.7833 degrees under the CSS Color 4 MINDE clip-and-compare
    /// fallback (see `GamutMapping.swift`'s header on why cssColor4 does not
    /// guarantee exact hue preservation) — so 0.5 degrees fails on correct
    /// code, not just on the defect. Reintroducing the defect (round-tripping
    /// the clipped candidate through `.sRGB` instead of `gamut` on both
    /// `rgbToOklch` calls in the `.cssColor4` branch) on this SAME fixture
    /// measured 2.9612 degrees of drift, and a local sweep of hue in
    /// 130...155 degrees around this fixture showed the defect consistently
    /// adding roughly 1-1.2 degrees of extra drift over correct code, with no
    /// overlap at this exact point. Plainly: correct code drifts 1.7833
    /// degrees, the defect drifts 2.9612 degrees, and the 2.5-degree
    /// threshold sits between the two with real margin on both sides — 0.72
    /// degrees below the defect's value, 0.46 degrees above the correct
    /// value.
    func test_B4_clipGuardUsesTargetGamut_danielcr12OKLCHKit() {
        // A colour outside P3, so the JND guard is genuinely exercised.
        let wild = Oklch(lightness: 0.70, chroma: 0.38, hue: 142.5)
        let mapped = gamutMap(wild, to: .displayP3, using: .cssColor4)

        // Must be in P3 — the gamut we asked for. This is a SANITY CHECK
        // only, not a discriminator for this defect: it was proven vacuous
        // over a 113,316-sample sweep (measured in a later revision) — the wrong-gamut
        // misread this test targets still lands inside P3 by construction,
        // since both the correct and defective clip guards feed a candidate
        // that gets gamut-mapped to P3 either way. The hue-drift assertion
        // below is what actually discriminates the defect.
        XCTAssertTrue(oklchToRGB(mapped, in: .displayP3).isInGamut(epsilon: 1e-6),
                      "result is not inside the requested P3 gamut")

        // And hue must survive within the drift naturally inherent to the
        // CSS Color 4 MINDE fallback (measured 1.7833 degrees for correct
        // code on this fixture) but not the much larger drift the wrong-gamut
        // misread produces (measured 2.9612 degrees). That gap is the
        // observable signature of this defect.
        XCTAssertEqual(mapped.hue, wild.hue, accuracy: 2.5,
                       "hue shifted by \(abs(shortestHueArc(from: wild.hue, to: mapped.hue))) degrees — "
                       + "the clipped candidate was likely read in the wrong gamut")
    }

    // MARK: B5 — metasidd/ColorTokensKit-Swift

    /// A hard per-channel clip to `[0,1]` shifts hue and lightness precisely
    /// where a ramp is most saturated. Our default must not do this — and the
    /// test asserts the difference is real, so `.clip` is not silently equal.
    ///
    /// Earlier assertions demanded `.cssColor4` preserve this
    /// fixture's lightness and hue to `accuracy: 1e-6`. Measured against our
    /// own (already-correct) `gamutMap`, that fails: this fixture lands in
    /// the MINDE clip-and-compare fallback, which does not guarantee exact
    /// preservation (see `GamutMapping.swift`'s header and
    /// `GamutMappingTests.testCSSMappingMatchesOracleForOutOfGamutRed`'s own
    /// note that cssColor4 can drift lightness by 0.0169 and hue by 0.110
    /// degrees even on a matched oracle fixture, and up to ~24 degrees of hue
    /// drift elsewhere). Measured here: cssColor4 drifts lightness by 0.0127
    /// and hue by 0.257 degrees from the input — already over 1e-6, so that
    /// assertion cannot discriminate anything; it fails on correct code.
    ///
    /// What actually distinguishes "default is CSS Color 4" from "default is
    /// secretly a hard clip" (B5's real defect) is that the two methods must
    /// disagree: if `.cssColor4` were implemented as ColorTokensKit's
    /// `clipToGamut`, feeding it the same input as `.clip` would produce
    /// numerically identical output. Confirmed by reintroducing the defect
    /// (making the `.cssColor4` case body identical to `.clip`'s): the two
    /// results became byte-identical, driving `cssVsClipDrift` to exactly 0.
    /// Also kept: cssColor4's lightness drift from the input must be smaller
    /// than a raw clip's (measured 0.0127 vs 0.0513 — a real margin, and
    /// necessarily equal under the defect since css and clip then coincide).
    func test_B5_defaultMappingIsNotAHardClip_metasiddColorTokensKit() {
        let saturated = Oklch(lightness: 0.55, chroma: 0.33, hue: 264.1)

        let css = gamutMap(saturated, to: .sRGB, using: .cssColor4)
        let clipped = gamutMap(saturated, to: .sRGB, using: .clip)

        // The clip method must show real drift from the input, or this test
        // proves nothing — neither method moving would make any comparison
        // meaningless.
        let clipDriftFromInput = abs(clipped.lightness - saturated.lightness)
                                + abs(shortestHueArc(from: clipped.hue, to: saturated.hue))
        XCTAssertGreaterThan(clipDriftFromInput, 1e-3,
                             "clip produced no drift, so this test proves nothing — "
                             + "pick a more saturated colour")

        // The defect's exact signature: the default silently BEING a hard
        // clip. If cssColor4 were implemented as ColorTokensKit's default, its
        // output would be numerically identical to `.clip`'s for this same
        // input. It must not be.
        let cssVsClipDrift = abs(css.lightness - clipped.lightness)
                            + abs(shortestHueArc(from: css.hue, to: clipped.hue))
        XCTAssertGreaterThan(cssVsClipDrift, 1e-3,
                             "cssColor4 produced the same result as .clip — "
                             + "the default is silently a hard clip")

        // cssColor4 does not guarantee exact preservation of lightness when
        // its own MINDE fallback fires, but it must still drift lightness
        // less than a raw per-channel clip does — the entire point of not
        // defaulting to clip.
        let cssLightnessDrift = abs(css.lightness - saturated.lightness)
        let clipLightnessDrift = abs(clipped.lightness - saturated.lightness)
        XCTAssertLessThan(cssLightnessDrift, clipLightnessDrift,
                          "cssColor4 drifted lightness as much as a raw per-channel clip")
    }
}
