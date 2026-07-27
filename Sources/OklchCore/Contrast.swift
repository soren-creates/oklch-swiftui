// Two contrast measures.
//
// WCAG 2.1 relative luminance ratio: simple, universally referenced, and
// known to be a poor perceptual model at low luminance.
//
// APCA: polarity-sensitive and far better matched to perception. The
// constants and algorithm structure below are transcribed verbatim from the
// vendored authoritative source, `Tools/gen-fixtures/node_modules/colorjs.io/
// src/contrast/APCA.js` (Color.js 0.7.1) — this is the G-4g constant set.
// THE VERSION LABEL IS AMBIGUOUS ACROSS THE ECOSYSTEM: Color.js self-labels
// this same set "0.0.98G" in that file's own header comment, while the
// identical constants are published elsewhere as "0.1.9". We therefore pin
// the CONSTANTS, not a version string. See P-APCA-1 in docs/pins.md.
//
// Reference: https://github.com/Myndex/apca-w3

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#else
#error("OklchCore requires Darwin, Glibc, or Musl")
#endif

/// A contrast level to solve for or assert against.
public enum ContrastTarget: Sendable, Hashable {
    /// APCA lightness contrast, `Lc`. Sign indicates polarity.
    case apca(Double)
    /// WCAG 2.1 contrast ratio, `1...21`.
    case wcag(Double)
}

// MARK: - WCAG 2.1

/// WCAG 2.1 relative luminance of an encoded RGB colour in `gamut`.
///
/// Relative luminance is intrinsic to a colour: the sRGB and Display P3
/// paths MUST agree for any colour representable in both, because luminance
/// does not depend on which gamut it happened to be encoded through. That
/// requires using `gamut`'s own XYZ Y row, not a hardcoded one — an earlier
/// version of this function hardcoded `Gamut.sRGB.toXYZ`'s row regardless of
/// the `gamut` argument, which silently returned a WRONG number (not merely
/// an approximate one) whenever called with `.displayP3`: measured 2.2% off
/// for an in-gamut colour pair, and P3 pure blue's luminance came back as
/// exactly sRGB blue's `Y` (`0.07219231536073385` vs the true
/// `0.079286914093745`) — the fingerprint of using the wrong matrix row.
/// Fixed round 1; see `P-TOL-5` in docs/pins.md.
///
/// Uses the full-precision `gamut.toXYZ` Y row, NOT the WCAG 2.1 spec's
/// officially published rounded constants (`0.2126, 0.7152, 0.0722`).
/// Measured: with the rounded constants, worst agreement with Color.js
/// across the fixture set was `5.4e-4` — Color.js computes luminance via an
/// actual XYZ conversion (full precision), not the rounded published
/// formula, so the rounded constants are a real defect here, not just a
/// stylistic choice.
public func relativeLuminance(_ rgb: RGB, in gamut: Gamut) -> Double {
    let r = Gamut.decode(rgb.red)
    let g = Gamut.decode(rgb.green)
    let b = Gamut.decode(rgb.blue)
    let yRow = gamut.toXYZ.m
    return yRow.3 * r + yRow.4 * g + yRow.5 * b
}

/// WCAG 2.1 contrast ratio between two colours. Symmetric, `1...21`.
///
/// Each luminance is clamped to `max(Y, 0)` before forming the ratio,
/// matching Color.js's `WCAG21.js` (`Math.max(getLuminance(color), 0)`).
/// Without this clamp, an out-of-gamut colour's negative-luminance
/// contribution can push the ratio outside the documented `1...21` range —
/// measured `24.860440877119924` (18% over 21) for `oklch(0.05 0.4 300)`
/// against white before this fix, vs Color.js's `21.000000000000007`.
///
/// - Warning: Measures the colour as given. If `a` or `b` may be outside
///   `gamut`, gamut-map it first — measuring an unmapped colour reports a
///   contrast the screen will never actually show, which is the defect
///   class this package exists to prevent (see `ContrastSolver.swift`'s file
///   header). `solveContrast` does this for you.
public func wcagContrast(_ a: Oklch, _ b: Oklch, in gamut: Gamut) -> Double {
    let la = max(relativeLuminance(oklchToRGB(a, in: gamut), in: gamut), 0)
    let lb = max(relativeLuminance(oklchToRGB(b, in: gamut), in: gamut), 0)
    let lighter = max(la, lb), darker = min(la, lb)
    return (lighter + 0.05) / (darker + 0.05)
}

// MARK: - APCA (G-4g constants, pinned as P-APCA-1)

// exponents
private let apcaNormBG = 0.56
private let apcaNormTXT = 0.57
private let apcaRevTXT = 0.62
private let apcaRevBG = 0.65

// clamps
private let apcaBlkThrs = 0.022
private let apcaBlkClmp = 1.414
private let apcaLoClip = 0.1
private let apcaDeltaYmin = 0.0005

// scalers
private let apcaScaleBoW = 1.14
private let apcaLoBoWoffset = 0.027
private let apcaScaleWoB = 1.14
private let apcaLoWoBoffset = 0.027

/// Toe-clamps luminance near black, where perception compresses (accounts for
/// screen flare). Matches `fclamp` in APCA.js exactly, including its `>=`
/// (not `>`) boundary.
private func apcaClampBlack(_ y: Double) -> Double {
    y >= apcaBlkThrs ? y : y + pow(apcaBlkThrs - y, apcaBlkClmp)
}

/// Sign-preserving power curve. Matches `linearize` in APCA.js exactly.
///
/// This differs from a naive `pow(max(0, val), 2.4)`: RGB components from
/// `oklchToRGB` are ENCODED and sign-symmetric (`Gamut.encode`/`decode` are
/// both sign-symmetric — see `Gamut.swift`), and are negative whenever a
/// colour is out of the target gamut. Clamping negatives to zero here would
/// silently diverge from Color.js for any out-of-gamut input, even though it
/// happens not to matter for the in-gamut fixture cases this task measures
/// against. Preserving sign is what the vendored source actually does.
private func apcaLinearize(_ val: Double) -> Double {
    let sign: Double = val < 0 ? -1 : 1
    return sign * pow(abs(val), 2.4)
}

/// APCA screen luminance. Note the coefficients differ from WCAG's.
private func apcaLuminance(_ rgb: RGB) -> Double {
    apcaLinearize(rgb.red) * 0.2126729
        + apcaLinearize(rgb.green) * 0.7151522
        + apcaLinearize(rgb.blue) * 0.072175
}

/// APCA lightness contrast `Lc` of `text` against `background`.
///
/// Positive for dark text on a light background, negative for the reverse.
/// Magnitude is what a target compares against.
///
/// - Warning: Measures the colours as given. If `text` or `background` may
///   be outside sRGB, gamut-map it first — measuring an unmapped colour
///   reports a contrast the screen will never actually show, which is the
///   defect class this package exists to prevent (see `ContrastSolver.swift`'s
///   file header). `solveContrast` does this for you.
///
/// Unlike `wcagContrast`, this function takes NO `gamut` parameter — that
/// asymmetry is deliberate, not an oversight. APCA is defined on sRGB, full
/// stop: APCA.js's `contrastAPCA` unconditionally converts both inputs
/// `to(color, "srgb")` before computing luminance (`APCA.js:58,68`),
/// regardless of what space they started in. An earlier version of this
/// function accepted a `gamut` parameter and used it for the luminance step,
/// which was measurably wrong: it returned two different numbers for the
/// same colour pair depending on whether `.sRGB` or `.displayP3` was passed,
/// when APCA.js would give one answer regardless. Swift emits no
/// unused-parameter warning for a parameter that is accepted but silently
/// ignored, so a `gamut` parameter here — even a correctly-ignored one —
/// would be a trap for a caller passing `.displayP3` and expecting it to
/// matter. Dropping the parameter entirely reflects the reality that APCA
/// has no such axis to control; a parameter that is silently ignored does
/// not. This is exactly why `apcaLinearize`'s sign-preserving `pow` matters:
/// out-of-gamut P3 colours land as negative sRGB components and must keep
/// their sign through the luminance computation, not get clamped to zero.
///
/// Structure matches APCA.js's `contrastAPCA` verbatim: the noise-gate check
/// (`abs(Ybg - Ytxt) < deltaYmin`) and the low-contrast clip check
/// (`abs(C) < loClip`) are both against the SIGNED delta/contrast, and the
/// offset's sign is chosen by `C > 0` rather than by which polarity branch
/// was taken. This matters whenever APCA luminance exceeds 1 (possible for
/// saturated out-of-gamut colours under the sign-preserving `pow`): branch
/// polarity and `C`'s sign can then disagree, and only the vendored source's
/// literal structure — not a branch-tied shortcut — reproduces
/// Color.js in that case.
public func apcaContrast(text: Oklch, background: Oklch) -> Double {
    let yText = apcaClampBlack(apcaLuminance(oklchToRGB(text, in: .sRGB)))
    let yBG = apcaClampBlack(apcaLuminance(oklchToRGB(background, in: .sRGB)))

    let isDarkOnLight = yBG > yText

    var contrast: Double
    if abs(yBG - yText) < apcaDeltaYmin {
        contrast = 0
    } else if isDarkOnLight {
        contrast = (pow(yBG, apcaNormBG) - pow(yText, apcaNormTXT)) * apcaScaleBoW
    } else {
        contrast = (pow(yBG, apcaRevBG) - pow(yText, apcaRevTXT)) * apcaScaleWoB
    }

    let output: Double
    if abs(contrast) < apcaLoClip {
        output = 0
    } else if contrast > 0 {
        output = contrast - apcaLoBoWoffset
    } else {
        output = contrast + apcaLoWoBoffset
    }
    return output * 100
}
