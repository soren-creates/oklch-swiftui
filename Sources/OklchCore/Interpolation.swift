//
// Hue interpolation per CSS Color 4:
//   - shortest arc by default
//   - powerless components adopt their partner's hue
//
// Both rules exist to prevent observed defects. Without the first, red to
// magenta travels 300 degrees through yellow, green and cyan instead of the
// 60-degree arc (defect B1). Without the second, white to blue shows a green
// cast mid-gradient because white's hue is numerical noise (defect B2).

/// The signed shortest angular distance from `a` to `b`, in `-180...180`.
///
/// For exactly antipodal inputs the sign is order-dependent: `arc(0, 180) ==
/// +180` while `arc(180, 0) == -180`. Both describe the same physical angle
/// (180 degrees either way round the circle is the same point), and the
/// general identity `arc(a, b) == -arc(b, a)` holds for these too — it is
/// only the ANTIPODAL case where `+180` and `-180` are both "correct" and
/// neither is preferred by this function's tie-breaking (`d > 180` rounds
/// down, `d < -180` rounds up, and exactly `180`/`-180` triggers neither).
public func shortestHueArc(from a: Double, to b: Double) -> Double {
    var d = (b - a).truncatingRemainder(dividingBy: 360)
    if d > 180 { d -= 360 }
    if d < -180 { d += 360 }
    return d
}

/// Interpolates between two OKLCH colours, taking the shortest hue arc and
/// honouring CSS powerless-component rules.
///
/// **Surprising but correct:** when exactly ONE endpoint is powerless, the
/// result adopts the POWERED partner's hue at every `t`, including `t == 0`
/// and `t == 1` — not just in between. That means `interpolate(a, b, t: 0)`
/// is not necessarily component-wise equal to `a` when `a` is powerless: its
/// numerically meaningless hue is replaced by `b`'s hue even at the `a`
/// endpoint itself. This is what CSS Color 4's powerless-component rule
/// actually specifies (defect B2's fix), and it is harmless in practice
/// because the powerless endpoint's chroma is ~0 there, so the substituted
/// hue has no visible effect — but it is a real, deliberate deviation from
/// naive component-wise lerp, not an oversight.
public func interpolate(_ a: Oklch, _ b: Oklch, t: Double) -> Oklch {
    let lightness = a.lightness + (b.lightness - a.lightness) * t
    let chroma = a.chroma + (b.chroma - a.chroma) * t
    let alpha = a.alpha + (b.alpha - a.alpha) * t

    let hue: Double
    switch (a.isPowerless, b.isPowerless) {
    case (true, true):
        // Neither endpoint carries hue information; the result is
        // achromatic. Keeping `a.hue` here (rather than `b.hue`, or an
        // average) is an arbitrary choice among equals, not a derived one —
        // any of the three would be equally defensible, and it is harmless
        // regardless of which is picked because chroma stays 0 throughout
        // this branch, so the chosen hue has no visible effect.
        hue = a.hue
    case (true, false):
        hue = b.hue
    case (false, true):
        hue = a.hue
    case (false, false):
        hue = Oklch.wrapHue(a.hue + shortestHueArc(from: a.hue, to: b.hue) * t)
    }

    return Oklch(lightness: lightness, chroma: chroma, hue: hue, alpha: alpha)
}
