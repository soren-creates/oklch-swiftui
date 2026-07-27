import XCTest
@testable import OklchCore

final class ContrastSolverTests: XCTestCase {

    /// ARCHITECTURE.md §5.4: achieved >= requested across a grid of backdrops and hues.
    ///
    /// An earlier draft of this test derived "is this target
    /// reachable at all" from `res.isSatisfied` — but `isSatisfied` is
    /// computed from `achieved` and `requested` with the SAME slack used to
    /// decide "did we fail", so `res.isSatisfied == false` and
    /// `res.achieved < res.requested - 1e-6` are the same predicate. That
    /// makes the two branches mutually exclusive and dead: whenever a
    /// shortfall occurs the test always takes the "unreachable, allowed to
    /// fall short" branch and `continue`s, so the `failures.append` branch
    /// below it can never fire. A solver that always returned lightness 0.5
    /// regardless of target would pass that version of the test.
    ///
    /// This version instead determines reachability INDEPENDENTLY, by
    /// measuring both lightness extremes itself (gamut-mapped, exactly as
    /// the solver is required to do per ARCHITECTURE.md §4.5) rather than trusting the
    /// solver's own self-report. A genuine shortfall on a target that is
    /// demonstrably reachable now fails the test.
    func testAchievedMeetsRequestedAcrossGrid() {
        var failures: [String] = []
        var reachableCount = 0
        var unreachableCount = 0
        let target = 4.5
        let chroma = 0.05

        for backdropL in stride(from: 0.0, through: 1.0, by: 0.1) {
            for hue in stride(from: 0.0, to: 360.0, by: 30.0) {
                let backdrop = Oklch(lightness: backdropL, chroma: 0, hue: 0)
                let (_, res) = solveContrast(
                    target: .wcag(target), hue: hue, chroma: chroma,
                    against: backdrop, in: .sRGB)

                // Ground truth, computed independently of the solver: the
                // best contrast reachable at this hue/chroma is whichever
                // lightness extreme (mapped, then measured) does better.
                let darkExtreme = wcagContrast(
                    gamutMap(Oklch(lightness: 0, chroma: chroma, hue: hue), to: .sRGB),
                    backdrop, in: .sRGB)
                let lightExtreme = wcagContrast(
                    gamutMap(Oklch(lightness: 1, chroma: chroma, hue: hue), to: .sRGB),
                    backdrop, in: .sRGB)
                let bestPossible = max(darkExtreme, lightExtreme)
                let isReachable = bestPossible >= target - 1e-6

                if isReachable {
                    reachableCount += 1
                    if res.achieved < target - 1e-6 {
                        failures.append("L=\(backdropL) h=\(hue): achieved \(res.achieved) < requested \(target) (reachable, best possible \(bestPossible))")
                    }
                } else {
                    unreachableCount += 1
                    // Unreachable targets are allowed to fall short, but must
                    // report it rather than lying, and must not report having
                    // achieved more than is actually reachable.
                    if res.isSatisfied {
                        failures.append("L=\(backdropL) h=\(hue): reported satisfied but best possible is \(bestPossible) < \(target)")
                    }
                    if res.achieved > bestPossible + 1e-6 {
                        failures.append("L=\(backdropL) h=\(hue): reported achieved \(res.achieved) exceeds best possible \(bestPossible)")
                    }
                }
            }
        }

        XCTAssertTrue(failures.isEmpty, "unmet reachable targets / dishonest shortfalls:\n\(failures.joined(separator: "\n"))")
        // Sanity check on the reachable branch (this grid's actual measured
        // result is 132/132 reachable — see below — so the reachable branch
        // is the only one this grid exercises).
        XCTAssertGreaterThan(reachableCount, 0, "grid produced no reachable points to check")
        // NOTE: the unreachable branch above (lines checking `isReachable ==
        // false`) is measured DEAD CODE for this specific grid/target/chroma
        // combination — target 4.5 at chroma 0.05 across a full 0...1
        // lightness sweep is reachable from at least one extreme at every
        // one of these 132 points, so `unreachableCount` is always 0 here.
        // That is a property of this grid's chosen parameters, not a gap in
        // the solver: the unreachable path IS exercised, directly and
        // deliberately, by `testUnreachableTargetReportsShortfall` below
        // (APCA Lc 120 against mid-grey, which has no solution at any
        // lightness at that chroma).
        print("MEASURED grid: \(reachableCount) reachable, \(unreachableCount) unreachable, of \(reachableCount + unreachableCount) total points")
    }

    /// ARCHITECTURE.md §4.5: contrast is measured on the MAPPED colour, never before.
    func testSolvedColourIsInGamut() {
        let backdrop = Oklch(lightness: 0.5, chroma: 0, hue: 0)
        let (colour, _) = solveContrast(
            target: .wcag(7), hue: 250, chroma: 0.3,
            against: backdrop, in: .sRGB)
        XCTAssertTrue(oklchToRGB(colour, in: .sRGB).isInGamut(epsilon: 1e-6),
                      "solver returned an out-of-gamut colour")
    }

    /// ARCHITECTURE.md §4.6: an unreachable target returns the best achievable colour and
    /// reports the shortfall. It must never crash or refuse to produce a colour.
    func testUnreachableTargetReportsShortfall() {
        let backdrop = Oklch(lightness: 0.5, chroma: 0, hue: 0)
        let (colour, res) = solveContrast(
            target: .apca(120), hue: 200, chroma: 0.2,
            against: backdrop, in: .sRGB)

        XCTAssertFalse(res.isSatisfied, "APCA Lc 120 on mid-grey should be unreachable")
        XCTAssertLessThan(res.achieved, res.requested)
        XCTAssertTrue(oklchToRGB(colour, in: .sRGB).isInGamut(epsilon: 1e-6),
                      "even a failed solve must return a drawable colour")
    }

    /// ARCHITECTURE.md §4.5, THE CRUX PROPERTY: contrast is measured on the MAPPED
    /// colour, never before. The prior version of this test (backdrop
    /// white, hue 250, chroma 0.1) could not discriminate this: at that
    /// backdrop the solve converges to lightness ~0.57, where chroma 0.1 is
    /// already inside sRGB, so gamut mapping is a no-op along the whole
    /// search path and measure-before-map vs. map-before-measure produce the
    /// identical answer either way.
    ///
    /// This case (backdrop L 0.75, hue 285, chroma 0.4, target WCAG 7) is
    /// chosen specifically because chroma 0.4 at hue 285 is far out of sRGB
    /// gamut for most of the candidates the bisection visits, so gamut
    /// mapping is NOT a no-op. Independent review measured: under the
    /// correct order (map, then measure) the returned colour actually
    /// measures `7.000000001398624` against the backdrop — reproduced here.
    /// Under the ordering bug this task exists to prevent (measure the
    /// UNMAPPED candidate, map only at the end) the solver would internally
    /// believe it hit the target while the colour actually drawn (post-map)
    /// measures only `4.889262955498655` — a `2.11` gap, i.e. exactly the
    /// "passes internally, fails on screen" bug class.
    func testWCAGTargetIsActuallyMet() {
        let backdrop = Oklch(lightness: 0.75, chroma: 0, hue: 0)
        let (colour, res) = solveContrast(
            target: .wcag(7), hue: 285, chroma: 0.4,
            against: backdrop, in: .sRGB)

        // Re-measure the RETURNED colour directly — this is what is
        // actually drawn — rather than trusting `res.achieved`, which a
        // measure-before-map bug would misreport as passing.
        let actual = wcagContrast(colour, backdrop, in: .sRGB)
        XCTAssertGreaterThanOrEqual(actual, 7 - 1e-3,
            "the colour actually drawn must meet the target; if this fails while res.achieved reports success, contrast was measured before gamut mapping")
        XCTAssertEqual(actual, res.achieved, accuracy: 1e-6)
    }

    /// ARCHITECTURE.md §4.5 "least extreme colour that still passes" (the solver's
    /// value proposition, and an explicit claim in `ContrastSolver.swift`'s
    /// bisection loop): the returned colour must not simply BE the extreme
    /// it searched toward, and must sit close to the true boundary, not
    /// merely somewhere inside the passing region. Nothing before this test
    /// asserted either property, so a solver that always returned pure
    /// black or pure white for every request — never running the bisection
    /// loop at all — passed the whole suite.
    ///
    /// Two checks: (1) the returned lightness lies strictly between the
    /// backdrop's lightness and the extreme searched toward (catches
    /// "return the extreme, never bisect" outright — that mutation returns
    /// lightness exactly `0` or exactly `1`); (2) stepping a further 0.02 in
    /// lightness back toward the backdrop must FAIL the target (catches a
    /// bisection that runs but stops well short of the boundary).
    func testSolvedColourIsLeastExtreme() {
        let backdrop = Oklch(lightness: 0.5, chroma: 0, hue: 0)
        let (colour, res) = solveContrast(
            target: .wcag(4.5), hue: 250, chroma: 0.1,
            against: backdrop, in: .sRGB)
        XCTAssertTrue(res.isSatisfied, "target should be reachable at this hue/chroma")

        let searchedDarker = colour.lightness < backdrop.lightness
        if searchedDarker {
            XCTAssertLessThan(colour.lightness, backdrop.lightness)
            XCTAssertGreaterThan(colour.lightness, 0,
                "should not have bottomed out at the extreme if bisection actually ran")
        } else {
            XCTAssertGreaterThan(colour.lightness, backdrop.lightness)
            XCTAssertLessThan(colour.lightness, 1,
                "should not have topped out at the extreme if bisection actually ran")
        }

        // The key discriminator: a step closer to the backdrop must fail.
        // A solver that just returns the extreme (lightness exactly 0 or 1)
        // would trivially still pass at a step closer in, since it never
        // actually located the boundary.
        let stepBack = searchedDarker ? colour.lightness + 0.02 : colour.lightness - 0.02
        let closerCandidate = Oklch(lightness: stepBack, chroma: 0.1, hue: 250)
        let mapped = gamutMap(closerCandidate, to: .sRGB)
        let closerContrast = wcagContrast(mapped, backdrop, in: .sRGB)
        XCTAssertLessThan(closerContrast, 4.5,
            "a step closer to the backdrop should fail the target if the solver actually found the boundary, not just returned an extreme")
    }

    /// Spec 9: `.lighter` and `.darker` have no absolute meaning if only
    /// compared against each other or against `.automatic` — a
    /// `.lighter`/`.darker` that both silently delegated to `.automatic`
    /// would still pass a test that only checks them against one another.
    /// This asserts against the backdrop directly, at several backdrops:
    /// `.lighter` must land above the backdrop's lightness, `.darker` below,
    /// independent of which one `.automatic` would have picked.
    func testExplicitDirectionsMoveTheRightWay() {
        for backdropL in [0.1, 0.5, 0.9] {
            let backdrop = Oklch(lightness: backdropL, chroma: 0, hue: 0)
            let (lighter, _) = solveContrast(
                target: .wcag(1.5), hue: 250, chroma: 0.05,
                against: backdrop, in: .sRGB, preferring: .lighter)
            let (darker, _) = solveContrast(
                target: .wcag(1.5), hue: 250, chroma: 0.05,
                against: backdrop, in: .sRGB, preferring: .darker)

            XCTAssertGreaterThan(lighter.lightness, backdrop.lightness,
                "L=\(backdropL): .lighter must return a lightness above the backdrop")
            XCTAssertLessThan(darker.lightness, backdrop.lightness,
                "L=\(backdropL): .darker must return a lightness below the backdrop")
        }
    }

    /// ARCHITECTURE.md §4.5: the APCA SUCCESS path, not just the shortfall path
    /// (`testUnreachableTargetReportsShortfall` above only exercises an
    /// unreachable APCA target). `measure`'s APCA branch computes
    /// `abs(apcaContrast(...))` before comparing against the (already
    /// unsigned) `requested` magnitude; dropping that `abs()` would corrupt
    /// the bisection's pass/fail decisions for whichever polarity comes out
    /// negative, with nothing here to notice. Reference values independently
    /// verified: backdrop L=0.5 target `.apca(60)` solves to a LIGHTER text
    /// colour (light-on-dark, negative signed Lc); backdrop L=1.0 target
    /// `.apca(75)` solves to a DARKER text colour (dark-on-light, positive
    /// signed Lc). Both the magnitude and the sign/direction relationship
    /// are asserted.
    func testAPCATargetIsMetWithCorrectPolarity() {
        let midBackdrop = Oklch(lightness: 0.5, chroma: 0, hue: 0)
        let (lightText, lightRes) = solveContrast(
            target: .apca(60), hue: 250, chroma: 0.1,
            against: midBackdrop, in: .sRGB)
        let lightSigned = apcaContrast(text: lightText, background: midBackdrop)
        XCTAssertTrue(lightRes.isSatisfied, "APCA 60 against mid-grey should be reachable")
        XCTAssertGreaterThanOrEqual(abs(lightSigned), 60 - 1e-3)
        XCTAssertLessThan(lightSigned, 0,
            "text lighter than the backdrop is light-on-dark: signed Lc must be negative")
        XCTAssertGreaterThan(lightText.lightness, midBackdrop.lightness)

        let whiteBackdrop = Oklch(lightness: 1.0, chroma: 0, hue: 0)
        let (darkText, darkRes) = solveContrast(
            target: .apca(75), hue: 250, chroma: 0.1,
            against: whiteBackdrop, in: .sRGB)
        let darkSigned = apcaContrast(text: darkText, background: whiteBackdrop)
        XCTAssertTrue(darkRes.isSatisfied, "APCA 75 against white should be reachable")
        XCTAssertGreaterThanOrEqual(abs(darkSigned), 75 - 1e-3)
        XCTAssertGreaterThan(darkSigned, 0,
            "text darker than the backdrop is dark-on-light: signed Lc must be positive")
        XCTAssertLessThan(darkText.lightness, whiteBackdrop.lightness)
    }

    /// P-DIR-1: `.automatic` measures both lightness extremes and searches
    /// toward whichever has more headroom against the target. This checks
    /// that the "more headroom wins" half of P-DIR-1 is real — not, say, a
    /// hardcoded default — by picking backdrops where the two extremes are
    /// clearly NOT tied, and confirming `.automatic` matches whichever
    /// explicit `Direction` actually has more headroom.
    ///
    /// The exact-tie half of P-DIR-1 ("ties break toward darker") is
    /// deliberately NOT exercised here. Probing for a backdrop where the two
    /// extremes are bit-identical found one only at ~1e-15 float noise
    /// (`darkC=4.582575694955837` vs `lightC=4.58257569495584` at
    /// `lightness=0.5637092048666653`) — which side of an exact tie a
    /// floating-point comparison lands on at that scale is exactly the kind
    /// of thing that is not guaranteed to reproduce across platforms (this
    /// suite also runs on Linux/glibc; see the libm-difference headroom
    /// built into `P-TOL-3`/`P-TOL-6`). Encoding that specific value as a
    /// test fixture would be pinning platform noise, not behaviour. The
    /// tie-break is instead verified by code inspection: `solveContrast`
    /// computes `searchDarker = darkest >= lightest`, so an exact tie
    /// (`darkest == lightest`) resolves `searchDarker` to `true`, i.e.
    /// darker — matching what `docs/pins.md` documents for `P-DIR-1`.
    func testAutomaticDirectionFollowsMoreHeadroom() {
        // Backdrop near black: the LIGHT extreme has far more contrast
        // headroom, so automatic should search lighter.
        let darkBackdrop = Oklch(lightness: 0.05, chroma: 0, hue: 0)
        let (autoOnDark, _) = solveContrast(
            target: .wcag(2), hue: 0, chroma: 0, against: darkBackdrop, in: .sRGB)
        let (lighterOnDark, _) = solveContrast(
            target: .wcag(2), hue: 0, chroma: 0, against: darkBackdrop, in: .sRGB,
            preferring: .lighter)
        XCTAssertEqual(autoOnDark.lightness, lighterOnDark.lightness, accuracy: 1e-9,
                       "automatic should follow the lighter extreme when it has more headroom")

        // Backdrop near white: the DARK extreme has far more contrast
        // headroom, so automatic should search darker.
        let lightBackdrop = Oklch(lightness: 0.95, chroma: 0, hue: 0)
        let (autoOnLight, _) = solveContrast(
            target: .wcag(2), hue: 0, chroma: 0, against: lightBackdrop, in: .sRGB)
        let (darkerOnLight, _) = solveContrast(
            target: .wcag(2), hue: 0, chroma: 0, against: lightBackdrop, in: .sRGB,
            preferring: .darker)
        XCTAssertEqual(autoOnLight.lightness, darkerOnLight.lightness, accuracy: 1e-9,
                       "automatic should follow the darker extreme when it has more headroom")
    }
}
