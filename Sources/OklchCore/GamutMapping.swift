// CSS Color 4 section 14.2.2, "Sample Pseudocode for the Binary Search Gamut
// Mapping with Local MINDE": https://www.w3.org/TR/css-color-4/#binsearch
//
// Binary-search chroma downward, holding lightness and hue, until the colour
// fits. A candidate whose clipped form is within one JND (deltaE_OK < 0.02)
// is a CANDIDATE to accept, but the spec does not return on the first such
// candidate: it flips `min_inGamut` to false and keeps narrowing upward
// (`min = chroma`) to find the largest chroma still within JND, only
// returning once the margin to the JND edge itself is under `epsilon`
// (0.0001). An earlier draft of this file returned on the first in-JND
// candidate, which under-narrows the search and can leave a large,
// visible gap to the true boundary — measured on the fixture set as a
// worst-case 0.106 per-channel disagreement with Color.js (`oog-green`),
// five times over one JND. The `min_inGamut` refinement loop below is
// what the spec's own pseudocode uses to close that gap; implementing it
// brought the same fixture down to sub-JND agreement — see `P-TOL-4` in
// docs/pins.md for the measured value.
//
// KNOWN LIMITATION (spec-inherited, not a bug in this implementation): the
// sRGB gamut boundary is not monotonic in chroma at fixed lightness and hue.
// Empirically (measured, independently reconfirmed here in
// `testNonMonotonicBoundaryStillReturnsInGamutResult`), at L=0.45, h=264.1,
// chroma 0.31 is INSIDE sRGB while both 0.29 and 0.315 are OUTSIDE — a
// narrow in-gamut "island" beyond the first boundary crossing. Binary search
// assumes monotonicity, exactly as the CSS Color 4 spec's own reference
// algorithm does, so on such a hue/lightness pair a binary search can
// converge to a chroma inside an island rather than the true first crossing.
// This is an accepted limitation of the CSS Color 4 algorithm itself.

/// How to bring an out-of-gamut colour into gamut.
public enum GamutMap: Sendable {
    /// Binary chroma search with a deltaE_OK just-noticeable-difference guard.
    /// Holds hue and lightness. The default.
    case cssColor4
    /// Per-channel clamp to `0...1`. Shifts hue and lightness, and is provided
    /// only for parity with GPU and shader paths that clip (ARCHITECTURE.md §4.1).
    case clip
}

/// The CSS Color 4 JND threshold for accepting a clipped candidate.
let jndThreshold = 0.02

/// Euclidean distance in OKLab. Used as the JND measure by CSS Color 4.
public func deltaEOK(_ a: Oklch, _ b: Oklch) -> Double {
    let la = oklchToOklab(a), lb = oklchToOklab(b)
    let dL = la.lightness - lb.lightness
    let dA = la.a - lb.a
    let dB = la.b - lb.b
    return (dL * dL + dA * dA + dB * dB).squareRoot()
}

/// Clamps every component into `0...1`.
func clipToGamut(_ rgb: RGB) -> RGB {
    RGB(red: min(max(rgb.red, 0), 1),
        green: min(max(rgb.green, 0), 1),
        blue: min(max(rgb.blue, 0), 1),
        alpha: rgb.alpha)
}

/// Brings `c` into `gamut`, returning a colour whose RGB form is in `0...1`.
public func gamutMap(_ c: Oklch,
                     to gamut: Gamut,
                     using method: GamutMap = .cssColor4) -> Oklch {
    // Already inside: nothing to do. Checked first so mapping is idempotent.
    //
    // Deliberately reordered vs. the spec, which checks L>=100%/L<=0% before
    // checking inGamut(origin). Here the inGamut check runs first and is
    // shared across both `method` cases, with the L-bounds checks only
    // inside `.cssColor4` below. Reviewed and probed for a behavioural
    // difference against the spec's ordering; none found — do not restructure
    // to match the spec's literal order without a concrete failing case.
    if oklchToRGB(c, in: gamut).isInGamut(epsilon: 1e-9) { return c }

    switch method {
    case .clip:
        // Defect B5 (ColorTokensKit) is this branch used as a DEFAULT. It shifts
        // hue and lightness exactly where a ramp is most saturated. Offered only
        // for shader parity.
        return rgbToOklch(clipToGamut(oklchToRGB(c, in: gamut)), in: gamut)

    case .cssColor4:
        if c.lightness >= 1 { return Oklch(lightness: 1, chroma: 0, hue: c.hue, alpha: c.alpha) }
        if c.lightness <= 0 { return Oklch(lightness: 0, chroma: 0, hue: c.hue, alpha: c.alpha) }

        // Spec epsilon (14.2.2): both the binary-search terminator and the
        // "how close to the JND edge" check below use this one constant.
        let epsilon = 1e-4

        // Defect B4 (OKLCHKit): the clipped candidate must be interpreted in
        // the SAME gamut it was clipped in. Round-tripping it through sRGB
        // while targeting P3 misreads P3 components as sRGB.
        var current = c
        var clipped = rgbToOklch(clipToGamut(oklchToRGB(current, in: gamut)), in: gamut)
        if deltaEOK(clipped, current) < jndThreshold {
            return clipped
        }

        var low = 0.0
        var high = c.chroma
        // Once a candidate is found whose clip is within JND but not close
        // enough to the JND edge to return outright, `min` is no longer
        // known to be strictly in-gamut — every later candidate is judged
        // by its clip distance, not raw gamut membership, until the search
        // converges. This is what lets the search push chroma higher than
        // the first in-JND hit, closing the gap to the true boundary.
        var minInGamut = true

        while high - low > epsilon {
            let chroma = (low + high) / 2
            current = Oklch(lightness: c.lightness, chroma: chroma, hue: c.hue, alpha: c.alpha)
            let rgb = oklchToRGB(current, in: gamut)

            if minInGamut && rgb.isInGamut(epsilon: 1e-9) {
                low = chroma
                continue
            }

            clipped = rgbToOklch(clipToGamut(rgb), in: gamut)
            let e = deltaEOK(clipped, current)

            if e < jndThreshold {
                if jndThreshold - e < epsilon {
                    return clipped
                }
                minInGamut = false
                low = chroma
            } else {
                high = chroma
            }
        }

        return clipped
    }
}

public extension Oklch {
    /// The largest chroma that stays inside `gamut` at this lightness and hue.
    ///
    /// Useful for building ramps that sit on the gamut boundary without
    /// repeatedly gamut-mapping.
    ///
    /// Binary search assumes the boundary is monotonic in chroma, which does
    /// not hold everywhere in sRGB (see the file header). On a hue/lightness
    /// pair with an in-gamut island beyond the first crossing, this can
    /// converge to a chroma inside the island rather than the true first
    /// crossing. The returned value is still guaranteed to be in-gamut; it is
    /// not guaranteed to be the tightest possible bound.
    static func maxChroma(lightness: Double, hue: Double, in gamut: Gamut) -> Double {
        var low = 0.0
        var high = 0.5   // beyond any reachable chroma in sRGB or P3
        while high - low > 1e-6 {
            let mid = (low + high) / 2
            let candidate = Oklch(lightness: lightness, chroma: mid, hue: hue)
            if oklchToRGB(candidate, in: gamut).isInGamut(epsilon: 1e-9) {
                low = mid
            } else {
                high = mid
            }
        }
        return low
    }
}
