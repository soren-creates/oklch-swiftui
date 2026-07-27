// Solves for a colour meeting a contrast target against a backdrop, by
// bisecting on lightness.
//
// ORDERING REQUIREMENT (ARCHITECTURE.md §4.5): every candidate is gamut-mapped FIRST, then
// contrast is measured on the mapped colour. Measuring before mapping yields a
// colour that fails its target the moment it is displayed — precisely the bug
// class this package exists to prevent.
//
// MONOTONICITY, STATED HONESTLY (ARCHITECTURE.md §4.5): contrast is monotone in luminance
// on each side of the backdrop, so bisection is stable. But chroma reduction
// during gamut mapping perturbs luminance slightly, so the COMPOSED function is
// not strictly monotone. That is accepted — the CSS Color 4 gamut-mapping
// algorithm's own guarantee bounds the perturbation at ONE JND (deltaEOK <
// 0.02, see `jndThreshold` in GamutMapping.swift), not "well below" it: this
// suite's own measured worst case is 0.01944706978379128 against a proxy
// (P-TOL-6), essentially at the bound, not comfortably under it. The
// composed function's near-monotonicity is accepted on that basis, with a
// hard iteration cap rather than a claim of exactness.

/// The outcome of a contrast solve. `achieved` is what the returned colour
/// actually measures, so a shortfall is observable rather than silent (ARCHITECTURE.md §4.6).
public struct ContrastResolution: Sendable, Hashable {
    public let requested: Double
    public let achieved: Double

    public init(requested: Double, achieved: Double) {
        self.requested = requested
        self.achieved = achieved
    }

    /// True when the target was met, within a small numerical slack.
    public var isSatisfied: Bool { achieved >= requested - 1e-6 }
}

/// Which way to move from the backdrop to gain contrast.
public enum Direction: Sendable, Hashable {
    case lighter
    case darker
    /// Pick whichever direction has more headroom. Ties break toward `darker`
    /// — pinned as `P-DIR-1`.
    case automatic
}

/// Hard iteration cap. Bisection on `0...1` reaches 1e-9 resolution in about 30
/// steps; 40 is generous and bounds the adversarial case (spec 8's risk table).
private let maxIterations = 40

/// Measures a candidate against the backdrop, after gamut mapping.
private func measure(_ candidate: Oklch,
                     against backdrop: Oklch,
                     target: ContrastTarget,
                     in gamut: Gamut) -> Double {
    // ORDERING: map first, measure second. Never the other way round.
    let mapped = gamutMap(candidate, to: gamut)
    switch target {
    case .wcag:
        return wcagContrast(mapped, backdrop, in: gamut)
    case .apca:
        return abs(apcaContrast(text: mapped, background: backdrop))
    }
}

/// Finds a colour at `hue`/`chroma` that meets `target` against `backdrop`.
///
/// Always returns a drawable, in-gamut colour. When the target is unreachable
/// the best achievable colour is returned and the shortfall is reported in the
/// resolution — renders never break, and regressions are still catchable.
///
/// `direction` — not `target`'s sign — is the polarity control here. For
/// `.apca(let lc)`, only `abs(lc)` is used as the magnitude to solve for;
/// the sign on the target itself is deliberately ignored, and which side of
/// the backdrop the solve lands on is governed entirely by `direction`
/// (`.lighter`, `.darker`, or `.automatic`'s headroom comparison — see
/// `P-DIR-1`). Concretely: `.apca(-60)` and `.apca(60)` against the same
/// backdrop with `direction: .automatic` return the bit-identical colour,
/// even though APCA's own sign convention (`Contrast.swift`) encodes
/// light-on-dark vs dark-on-light polarity. This is an explicit, reviewed
/// design choice for this task, not an oversight — flagged here rather than
/// silently changed, in case a future task wants `target`'s sign to also
/// constrain `direction`.
public func solveContrast(target: ContrastTarget,
                          hue: Double,
                          chroma: Double,
                          against backdrop: Oklch,
                          in gamut: Gamut,
                          preferring direction: Direction = .automatic) -> (colour: Oklch,
                                                                            resolution: ContrastResolution) {
    let requested: Double
    switch target {
    case .wcag(let r): requested = r
    case .apca(let lc): requested = abs(lc)
    }

    let candidate = { (l: Double) in Oklch(lightness: l, chroma: chroma, hue: hue) }

    // Evaluate both extremes; the better one tells us which way to search.
    let darkest = measure(candidate(0), against: backdrop, target: target, in: gamut)
    let lightest = measure(candidate(1), against: backdrop, target: target, in: gamut)

    let searchDarker: Bool
    switch direction {
    case .darker: searchDarker = true
    case .lighter: searchDarker = false
    case .automatic:
        // P-DIR-1: more headroom wins; ties break toward darker.
        searchDarker = darkest >= lightest
    }

    // Bisect between the backdrop's lightness and the chosen extreme.
    // Contrast increases as we move away from the backdrop — monotonically
    // in the underlying luminance, and near-monotonically (not exactly, per
    // the file header above) once gamut mapping's own perturbation is
    // composed in.
    var near = backdrop.lightness
    var far = searchDarker ? 0.0 : 1.0

    var best = candidate(far)
    var bestValue = searchDarker ? darkest : lightest

    // If even the extreme cannot meet the target, return it with the shortfall.
    if bestValue < requested {
        let mapped = gamutMap(best, to: gamut)
        return (mapped, ContrastResolution(requested: requested, achieved: bestValue))
    }

    for _ in 0..<maxIterations {
        let mid = (near + far) / 2
        let value = measure(candidate(mid), against: backdrop, target: target, in: gamut)

        if value >= requested {
            // Meets the target: record it and try closer to the backdrop.
            // This converges toward the least extreme colour that still
            // passes, but is not a guaranteed exact minimum: the acknowledged
            // non-monotonicity above means bisection assumes a monotone
            // boundary crossing, so an adversarial input could in principle
            // stop short of the true boundary. `ContrastSolverTests.swift`'s
            // `testSolvedColourIsLeastExtreme` bounds this empirically (a
            // fixed step back toward the backdrop must fail the target) for
            // the cases it exercises, rather than proving it in general.
            best = candidate(mid)
            bestValue = value
            far = mid
        } else {
            near = mid
        }

        if abs(far - near) < 1e-9 { break }
    }

    return (gamutMap(best, to: gamut),
            ContrastResolution(requested: requested, achieved: bestValue))
}
