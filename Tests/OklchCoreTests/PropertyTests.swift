import XCTest
@testable import OklchCore

/// Tier 2 (ARCHITECTURE.md §5.2). Deterministic by construction: a fixed lattice, plus a
/// linear congruential generator with a pinned seed. No RNG from the system,
/// no wall clock, no entropy sources.
final class PropertyTests: XCTestCase {

    /// Pinned seed. Changing it changes which colours are tested and is a
    /// material change to the suite — record it in docs/pins.md if you do.
    /// Pinned as `P-SEED-1`.
    static let seed: UInt64 = 20260725

    /// Deterministic LCG (Numerical Recipes constants).
    struct PinnedRandom {
        var state: UInt64
        mutating func next() -> Double {
            state = state &* 1664525 &+ 1013904223
            return Double(state >> 11) / Double(UInt64(1) << 53)
        }
    }

    /// Pin `P-TOL-7` (see docs/pins.md). Measured worst error over the
    /// `P-SEED-1` sweep: `8.916478666520788e-16`. Pinned at roughly 3.4x
    /// that measurement, the same 2.6-4x headroom band `P-TOL-3` and
    /// `P-TOL-5` use, for legitimate cross-platform `libm` differences (this
    /// suite also builds and runs on Linux) — not for slack. This was
    /// previously a bare `1e-9` literal with no pin, 6.5 orders of magnitude
    /// looser than the measurement; the class of defect that forced
    /// `P-TOL-5` to be re-pinned had not been applied backward to
    /// this file until now.
    static let roundTripIdentityTolerance = 3e-15

    func testRoundTripIdentityForInGamutColours() {
        var rng = PinnedRandom(state: Self.seed)
        var worst = 0.0

        // `Oklch.maxChroma` binary-searches assuming monotonicity, which does
        // not hold everywhere in sRGB (see GamutMapping.swift's file header
        // and `P-TOL-4`'s neighbourhood in docs/pins.md). On a hue/lightness
        // pair with an in-gamut "island" beyond the true first crossing, the
        // search can converge to a chroma that is not actually in gamut. If
        // that happens here, do not silently skip the sample — count it and
        // report it; it is a finding about `maxChroma`, not a test bug.
        var notActuallyInGamutCount = 0

        for _ in 0..<2000 {
            let l = rng.next()
            let h = rng.next() * 360
            let maxC = Oklch.maxChroma(lightness: l, hue: h, in: .sRGB)
            let c = rng.next() * maxC

            let original = Oklch(lightness: l, chroma: c, hue: h)

            guard oklchToRGB(original, in: .sRGB).isInGamut(epsilon: 1e-9) else {
                notActuallyInGamutCount += 1
                continue
            }

            let round = rgbToOklch(oklchToRGB(original, in: .sRGB), in: .sRGB)

            worst = max(worst, abs(round.lightness - original.lightness))
            if original.chroma > Oklch.powerlessChromaThreshold {
                worst = max(worst, abs(round.chroma - original.chroma))
            }
        }

        print("MEASURED round-trip worst error: \(worst)")
        print("MEASURED maxChroma samples not actually in gamut: \(notActuallyInGamutCount) / 2000")
        XCTAssertLessThan(worst, Self.roundTripIdentityTolerance, "in-gamut round trip is not identity")
        XCTAssertEqual(notActuallyInGamutCount, 0,
            "maxChroma returned a chroma that is not actually in gamut; the sRGB boundary "
            + "is non-monotonic, so this is possible in principle — but it was 0/2000 when "
            + "measured, and a nonzero count means effective sample coverage has silently shrunk")
    }

    func testGamutMappingIsIdempotentEverywhere() {
        var rng = PinnedRandom(state: Self.seed)
        for _ in 0..<1000 {
            let colour = Oklch(lightness: rng.next(),
                               chroma: rng.next() * 0.4,
                               hue: rng.next() * 360)
            let once = gamutMap(colour, to: .sRGB)
            let twice = gamutMap(once, to: .sRGB)
            XCTAssertEqual(once.chroma, twice.chroma, accuracy: 1e-9)
            XCTAssertEqual(once.lightness, twice.lightness, accuracy: 1e-9)
        }
    }

    func testMappedColoursAreAlwaysInGamut() {
        var rng = PinnedRandom(state: Self.seed)
        for gamut in [Gamut.sRGB, .displayP3] {
            for _ in 0..<1000 {
                let colour = Oklch(lightness: rng.next(),
                                   chroma: rng.next() * 0.4,
                                   hue: rng.next() * 360)
                let mapped = gamutMap(colour, to: gamut)
                XCTAssertTrue(oklchToRGB(mapped, in: gamut).isInGamut(epsilon: 1e-6),
                              "\(colour) mapped to \(gamut.name) is still outside")
            }
        }
    }

    /// Pin `P-TOL-6` (see docs/pins.md). This bounds a PROXY quantity, not
    /// the algorithm's true internal guarantee — see the comment on
    /// `testHueAndLightnessSurviveChromaReduction` below for why the two are
    /// different, and why this test cannot be read as a correctness check.
    static let gamutMapDeltaEProxyTolerance = 0.05

    /// An earlier form of this test asserted exact preservation
    /// (`accuracy: 1e-6`) of hue and lightness under `.cssColor4` chroma
    /// reduction. That assertion does not hold and was replaced here on
    /// measured evidence, not weakened blindly — see the comment below for
    /// the investigation and measured values.
    func testHueAndLightnessSurviveChromaReduction() {
        var rng = PinnedRandom(state: Self.seed)
        var worstLDrift = 0.0
        var worstHueDriftDegrees = 0.0
        var worstDeltaE = 0.0

        for _ in 0..<1000 {
            // Lightness away from the poles, where hue is meaningless anyway.
            let l = 0.1 + rng.next() * 0.8
            let h = rng.next() * 360
            let colour = Oklch(lightness: l, chroma: 0.35, hue: h)
            let mapped = gamutMap(colour, to: .sRGB, using: .cssColor4)

            guard mapped.chroma > Oklch.powerlessChromaThreshold else { continue }

            worstLDrift = max(worstLDrift, abs(mapped.lightness - l))
            var hueDelta = abs(mapped.hue - Oklch.wrapHue(h))
            if hueDelta > 180 { hueDelta = 360 - hueDelta }
            worstHueDriftDegrees = max(worstHueDriftDegrees, hueDelta)

            // `.cssColor4`'s search holds lightness and hue fixed on every
            // candidate it EVALUATES, but its final return is
            // `rgbToOklch(clipToGamut(oklchToRGB(candidate)))` — a clip in
            // RGB space, round-tripped back to OKLCH. That operation is not
            // hue/lightness-preserving. The algorithm's TRUE internal
            // guarantee (CSS Color 4 §14.2.2) is `deltaEOK(clipped, searchCandidate)
            // < jndThreshold` EXACTLY, measured against the search
            // candidate's own chroma — but that candidate is internal to
            // `gamutMap` and is not exposed by the public API, so this test
            // cannot compute it directly. `candidateAtMappedChroma` below,
            // built from the *post-clip* chroma instead, is a PROXY for the
            // real search candidate — a weaker, different quantity that
            // needs a looser bound than `jndThreshold` itself (see
            // `P-TOL-6` in docs/pins.md for the measured margin between the
            // two).
            let candidateAtMappedChroma = Oklch(lightness: l, chroma: mapped.chroma, hue: h)
            worstDeltaE = max(worstDeltaE, deltaEOK(mapped, candidateAtMappedChroma))
        }

        print("MEASURED worst lightness drift under cssColor4 chroma reduction: \(worstLDrift)")
        print("MEASURED worst hue drift under cssColor4 chroma reduction (degrees): \(worstHueDriftDegrees)")
        print("MEASURED worst deltaEOK vs fixed-hue/lightness proxy: \(worstDeltaE)")

        // Hue drift under this sweep is NOT confined to near-achromatic
        // colours — a broader investigation found worst drift above mapped
        // chroma 0.05 is still 19.72 degrees, and above mapped chroma 0.10
        // it is 9.43 degrees.
        // The near-pole case (~24.7 degrees at l~0.114, where `maxChroma`
        // for that hue is only ~0.025) is the single worst point, not an
        // isolated artifact confined to the poles.
        //
        // This assertion is a REGRESSION detector, not a correctness proof.
        // `GamutMappingTests.swift` (see its
        // `testCSSMappingMatchesOracleForOutOfGamutRed` comment, lines
        // 31-61) already established that a deltaEOK-vs-JND style check
        // "could not discriminate a correct implementation from a buggy
        // one" — the pre-fix, spec-noncompliant search also passed a
        // similar check. What actually pins correctness is tier 1's
        // agreement with the Color.js oracle (`P-TOL-3`/`P-TOL-4`). Tier 2's
        // job here is narrower: catch gross regressions (e.g. the search
        // diverging wildly, or losing the fixed-hue/lightness discipline
        // entirely) across a broad, deterministic sweep that the fixture
        // set does not cover point-for-point.
        XCTAssertLessThan(worstDeltaE, Self.gamutMapDeltaEProxyTolerance,
                          "cssColor4's clipped return strayed further from its fixed-hue/lightness proxy than pinned P-TOL-6 allows")
    }
}
