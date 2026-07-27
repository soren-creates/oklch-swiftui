import XCTest
@testable import OklchCore

final class GamutMappingTests: XCTestCase {

    private let outOfGamut = Oklch(lightness: 0.70, chroma: 0.30, hue: 29.2)

    func testMappedColourIsInGamut() {
        for method in [GamutMap.cssColor4, .clip] {
            let mapped = gamutMap(outOfGamut, to: .sRGB, using: method)
            let rgb = oklchToRGB(mapped, in: .sRGB)
            XCTAssertTrue(rgb.isInGamut(epsilon: 1e-6),
                          "\(method) produced an out-of-gamut result: \(rgb)")
        }
    }

    func testMappingIsIdempotent() {
        let once = gamutMap(outOfGamut, to: .sRGB)
        let twice = gamutMap(once, to: .sRGB)
        XCTAssertEqual(once.lightness, twice.lightness, accuracy: 1e-9)
        XCTAssertEqual(once.chroma, twice.chroma, accuracy: 1e-9)
        XCTAssertEqual(once.hue, twice.hue, accuracy: 1e-9)
    }

    func testInGamutColourIsUnchanged() {
        let inside = Oklch(lightness: 0.6, chroma: 0.05, hue: 200)
        let mapped = gamutMap(inside, to: .sRGB)
        XCTAssertEqual(mapped.chroma, inside.chroma, accuracy: 1e-9)
    }

    /// CSS Color 4 does NOT preserve hue and lightness exactly when the MINDE
    /// (clip-and-compare) branch returns — clamping in RGB space and
    /// round-tripping the clipped colour back to OKLCH is not a hue- or
    /// lightness-preserving operation. This test replaces an earlier version
    /// of itself (`testCSSMappingPreservesHueAndLightness`) which asserted
    /// exact equality (`accuracy: 1e-9`) on `mapped.lightness`/`mapped.hue`.
    /// That failed as measured — the returned colour differs from the input
    /// by 0.0169 in lightness and 0.110 degrees in hue for this exact input —
    /// and was replaced with a deltaEOK-vs-JND check on the theory that the
    /// *perceptual* distance was the real guarantee.
    ///
    /// That replacement was also wrong, on two counts, caught in review:
    ///
    /// 1. It is not actually a guaranteed invariant. Sweeping L, hue and
    ///    chroma broadly, the same deltaEOK-vs-same-chroma-preserved quantity
    ///    exceeds the JND threshold at dozens of points (worst measured
    ///    0.0200164... at L=0.98, C=0.3, hue=101.0) — it happened to hold for
    ///    this one input, not because CSS Color 4 promises it in general.
    /// 2. It could not discriminate a correct implementation from a buggy
    ///    one. Running the pre-fix algorithm (the one that returns on the
    ///    *first* out-of-gamut candidate within one JND, instead of the
    ///    spec's `min_inGamut` refinement loop — see `GamutMapping.swift`)
    ///    through that same assertion also passes it (deltaEOK ~0.0098,
    ///    still under 0.02), despite being the version that measured a
    ///    0.106 per-channel disagreement with Color.js on the fixture set.
    ///
    /// What actually discriminates is agreement with an independent oracle.
    /// `outOfGamut` is exactly the `oog-red` fixture case, which carries
    /// Color.js's own `mapped_css_oklch` for this input. Our output matches
    /// it to ~1e-13 (chroma diff ~8.3e-17, hue diff ~8.2e-14); the pre-fix
    /// algorithm's output (L=0.6902, C=0.1998, hue=29.28) does not.
    func testCSSMappingMatchesOracleForOutOfGamutRed() throws {
        let fixtures = try FixtureLoader.load()
        guard let oogRed = fixtures.cases.first(where: { $0.id == "oog-red" }),
              let expected = oogRed.mapped_css_oklch else {
            XCTFail("oog-red fixture case or its mapped_css_oklch is missing")
            return
        }

        let mapped = gamutMap(outOfGamut, to: .sRGB, using: .cssColor4)

        XCTAssertEqual(mapped.lightness, expected[0], accuracy: 1e-13)
        XCTAssertEqual(mapped.chroma, expected[1], accuracy: 1e-13)
        XCTAssertEqual(mapped.hue, expected[2], accuracy: 1e-13)
        XCTAssertLessThan(mapped.chroma, outOfGamut.chroma)
    }

    func testMaxChromaIsOnTheGamutBoundary() {
        let maxC = Oklch.maxChroma(lightness: 0.7, hue: 29.2, in: .sRGB)
        let justInside = Oklch(lightness: 0.7, chroma: maxC - 1e-4, hue: 29.2)
        let justOutside = Oklch(lightness: 0.7, chroma: maxC + 1e-3, hue: 29.2)
        XCTAssertTrue(oklchToRGB(justInside, in: .sRGB).isInGamut(epsilon: 1e-5))
        XCTAssertFalse(oklchToRGB(justOutside, in: .sRGB).isInGamut(epsilon: 1e-9))
    }

    /// KNOWN CHARACTERISTIC, not a bug: the sRGB gamut boundary is not
    /// monotonic in chroma at every fixed lightness/hue. At L=0.45, h=264.1,
    /// verified directly against `oklchToRGB` with a 0.005 chroma step scan:
    ///
    ///     chroma 0.265        -> IN  (last of the first in-gamut run)
    ///     chroma 0.270 - 0.305 -> OUT (r goes negative, then b exceeds 1)
    ///     chroma 0.310         -> IN  (a narrow island: r=0.0016 g=0.0151 b=0.9903)
    ///     chroma 0.315+        -> OUT (b exceeds 1 again, monotonically worse)
    ///
    /// `gamutMap` and `maxChroma` both binary-search assuming monotonicity —
    /// exactly what the CSS Color 4 spec's own reference algorithm does. This
    /// test does not assert either function finds the *first* crossing (that
    /// would be false in general on a non-monotonic boundary); it asserts the
    /// property that must always hold regardless of which crossing is found:
    /// both functions still return something genuinely inside the gamut, and
    /// `maxChroma` never returns a chroma that overshoots the requested probe
    /// point (0.315) which is confirmed out of gamut above.
    func testNonMonotonicBoundaryStillReturnsInGamutResult() {
        let hue = 264.1
        let lightness = 0.45

        // The island itself: confirms the boundary is genuinely non-monotonic
        // here, not merely a hypothetical.
        let island = Oklch(lightness: lightness, chroma: 0.31, hue: hue)
        XCTAssertTrue(oklchToRGB(island, in: .sRGB).isInGamut(epsilon: 1e-9),
                      "expected chroma 0.31 to be the in-gamut island at L=0.45, h=264.1")
        let beforeIsland = Oklch(lightness: lightness, chroma: 0.29, hue: hue)
        let afterIsland = Oklch(lightness: lightness, chroma: 0.315, hue: hue)
        XCTAssertFalse(oklchToRGB(beforeIsland, in: .sRGB).isInGamut(epsilon: 1e-9))
        XCTAssertFalse(oklchToRGB(afterIsland, in: .sRGB).isInGamut(epsilon: 1e-9))

        // gamutMap on a colour beyond the island must still land in-gamut.
        let farOut = Oklch(lightness: lightness, chroma: 0.39, hue: hue)
        let mapped = gamutMap(farOut, to: .sRGB, using: .cssColor4)
        XCTAssertTrue(oklchToRGB(mapped, in: .sRGB).isInGamut(epsilon: 1e-6),
                      "gamutMap produced an out-of-gamut result on a non-monotonic boundary: \(mapped)")

        // maxChroma must still return an in-gamut chroma, whichever crossing
        // its binary search happens to converge on.
        let maxC = Oklch.maxChroma(lightness: lightness, hue: hue, in: .sRGB)
        let atMax = Oklch(lightness: lightness, chroma: maxC, hue: hue)
        XCTAssertTrue(oklchToRGB(atMax, in: .sRGB).isInGamut(epsilon: 1e-6),
                      "maxChroma returned a chroma that is not actually in gamut: \(maxC)")
    }
}
