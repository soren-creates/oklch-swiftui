import XCTest
@testable import OklchCore

final class FixtureTests: XCTestCase {

    /// Pin P-TOL-3. Measured worst error across every fixture case: 3.46947470752923e-14
    /// (sRGB, srgb-corner-green), 2.3314683517128287e-15 (P3, srgb-corner-green). Tightened
    /// from the seeded 1e-6 guess to just above the measured worst (sRGB), leaving
    /// headroom only for legitimate libm differences across platforms — NOT for slack.
    /// Do not change this number without recording a new measurement in docs/pins.md.
    static let conversionTolerance = 1e-13

    func testOklchToSRGBMatchesColorJS() throws {
        let fixtures = try FixtureLoader.load()
        var worst = 0.0
        var worstID = ""

        for c in fixtures.cases {
            let colour = Oklch(lightness: c.oklch[0], chroma: c.oklch[1], hue: c.oklch[2])
            let ours = oklchToRGB(colour, in: .sRGB)
            let theirs = c.srgb

            for (i, mine) in [ours.red, ours.green, ours.blue].enumerated() {
                let e = abs(mine - theirs[i])
                if e > worst { worst = e; worstID = c.id }
            }
        }

        print("MEASURED oklch->srgb worst error: \(worst) at \(worstID)")
        XCTAssertLessThan(worst, Self.conversionTolerance,
                          "worst \(worst) at \(worstID) exceeds pinned P-TOL-3")
    }

    func testOklchToP3MatchesColorJS() throws {
        let fixtures = try FixtureLoader.load()
        var worst = 0.0
        var worstID = ""

        for c in fixtures.cases {
            let colour = Oklch(lightness: c.oklch[0], chroma: c.oklch[1], hue: c.oklch[2])
            let ours = oklchToRGB(colour, in: .displayP3)

            for (i, mine) in [ours.red, ours.green, ours.blue].enumerated() {
                let e = abs(mine - c.p3[i])
                if e > worst { worst = e; worstID = c.id }
            }
        }

        print("MEASURED oklch->p3 worst error: \(worst) at \(worstID)")
        XCTAssertLessThan(worst, Self.conversionTolerance,
                          "worst \(worst) at \(worstID) exceeds pinned P-TOL-3")
    }

    func testGamutMembershipAgreesWithColorJS() throws {
        let fixtures = try FixtureLoader.load()
        for c in fixtures.cases {
            let colour = Oklch(lightness: c.oklch[0], chroma: c.oklch[1], hue: c.oklch[2])
            let inSRGB = oklchToRGB(colour, in: .sRGB).isInGamut(epsilon: 1e-6)
            XCTAssertEqual(inSRGB, c.in_srgb_gamut,
                           "sRGB gamut membership disagrees for \(c.id)")
        }
    }

    /// Pin P-TOL-4. Measured worst error across every fixture case with a
    /// `mapped_css_srgb` reference: 2.8329560919360118e-14 (oog-green). As
    /// tight as P-TOL-3, not looser — see docs/pins.md for why. Do not
    /// change this number without recording a new measurement there.
    static let gamutMapTolerance = 1e-13

    func testGamutMappingMatchesColorJS() throws {
        let fixtures = try FixtureLoader.load()
        var worst = 0.0
        var worstID = ""

        for c in fixtures.cases {
            guard let expected = c.mapped_css_srgb else { continue }
            let colour = Oklch(lightness: c.oklch[0], chroma: c.oklch[1], hue: c.oklch[2])
            let ours = oklchToRGB(gamutMap(colour, to: .sRGB, using: .cssColor4), in: .sRGB)

            for (i, mine) in [ours.red, ours.green, ours.blue].enumerated() {
                let e = abs(mine - expected[i])
                if e > worst { worst = e; worstID = c.id }
            }
        }

        print("MEASURED gamut-map worst error vs Color.js: \(worst) at \(worstID)")
        // A second assertion against the raw JND bound (0.02) was removed
        // here: `Self.gamutMapTolerance` (1e-13) is already many orders
        // tighter than one JND, so a JND-bound check could never fire
        // independently of the assertion above — it was strictly implied,
        // not an additional check.
        XCTAssertLessThan(worst, Self.gamutMapTolerance, "gamut mapping diverges from Color.js")
    }

    func testHueArcsMatchFixtures() throws {
        let fixtures = try FixtureLoader.load()
        for arc in fixtures.hue_arcs {
            XCTAssertEqual(shortestHueArc(from: arc.from, to: arc.to),
                           arc.shortest_arc, accuracy: 1e-9,
                           "hue arc disagrees for \(arc.id)")
        }
    }

    /// Closes a gap `FixtureLoader.load()`'s hard-failure fix (a later revision)
    /// does not cover on its own: a PRESENT but silently regenerated or
    /// corrupted fixture file would still load successfully, yet every
    /// fixture-derived pin (P-TOL-3, P-TOL-4, P-TOL-5) is only meaningful
    /// against the exact colorjs/node toolchain that produced the committed
    /// values. This asserts the generator block recorded IN the committed
    /// `Fixtures/colorjs/conversions.json` still matches the pinned
    /// toolchain, and that the three case arrays are non-empty.
    func testFixtureGeneratorMatchesPinnedToolchain() throws {
        let fixtures = try FixtureLoader.load()

        // Pinned exactly (not a range) in Tools/gen-fixtures/package.json's
        // "colorjs.io": "0.7.1" dependency, and in every "Measured on" line
        // in docs/pins.md.
        XCTAssertEqual(fixtures.generator.colorjs, "0.7.1",
                       "fixtures were generated with an unpinned colorjs.io version — "
                       + "every fixture-derived pin (P-TOL-3/4/5) assumes this exact toolchain")

        // The exact node version recorded in the committed fixture file at
        // generation time (docs/pins.md: "node v26.4.0"). Not a
        // floating "current node" — a regeneration on a different node
        // version must be caught, not silently trusted.
        XCTAssertEqual(fixtures.generator.node, "v26.4.0",
                       "fixtures were generated with a different node version than pinned")

        XCTAssertFalse(fixtures.cases.isEmpty, "fixture cases array is empty")
        XCTAssertFalse(fixtures.hue_arcs.isEmpty, "fixture hue_arcs array is empty")
        XCTAssertFalse(fixtures.contrast.isEmpty, "fixture contrast array is empty")
    }
}
