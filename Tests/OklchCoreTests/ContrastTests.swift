import XCTest
@testable import OklchCore

final class ContrastTests: XCTestCase {

    private let white = Oklch(lightness: 1.0, chroma: 0, hue: 0)
    private let black = Oklch(lightness: 0.0, chroma: 0, hue: 0)

    func testWCAGWhiteOnBlackIsTwentyOne() {
        XCTAssertEqual(wcagContrast(white, black, in: .sRGB), 21, accuracy: 1e-6)
    }

    func testWCAGIdenticalColoursIsOne() {
        let grey = Oklch(lightness: 0.5, chroma: 0, hue: 0)
        XCTAssertEqual(wcagContrast(grey, grey, in: .sRGB), 1, accuracy: 1e-9)
    }

    func testWCAGIsSymmetric() {
        let a = Oklch(lightness: 0.3, chroma: 0.1, hue: 250)
        let b = Oklch(lightness: 0.9, chroma: 0.05, hue: 90)
        XCTAssertEqual(wcagContrast(a, b, in: .sRGB),
                       wcagContrast(b, a, in: .sRGB), accuracy: 1e-12)
    }

    /// Relative luminance is intrinsic to a colour: for a pair that is
    /// in-gamut in BOTH sRGB and Display P3, the WCAG ratio computed via
    /// either gamut must agree, because the underlying colour (and thus its
    /// true luminance) is the same regardless of which gamut it happened to
    /// be encoded through. A later revision: an earlier version hardcoded sRGB's
    /// XYZ Y row inside `relativeLuminance` regardless of the `gamut`
    /// argument, so the `.displayP3` path silently returned a WRONG number
    /// (measured 2.2% off) rather than merely an approximate one.
    func testWCAGAgreesAcrossGamutsForInGamutColours() {
        let a = Oklch(lightness: 0.5, chroma: 0.1, hue: 30)
        let b = Oklch(lightness: 0.8, chroma: 0.05, hue: 200)
        XCTAssertEqual(wcagContrast(a, b, in: .sRGB),
                       wcagContrast(a, b, in: .displayP3), accuracy: 1e-12)
    }

    /// Color.js's WCAG21 implementation clamps each luminance to `max(Y, 0)`
    /// before forming the ratio. Without that clamp, an out-of-gamut colour's
    /// negative luminance contribution can push the ratio outside the
    /// documented `1...21` range — measured `24.860440877119924` for this
    /// exact colour against white before this fix.
    func testWCAGStaysWithinDocumentedRangeForOutOfGamutColour() {
        let outOfGamut = Oklch(lightness: 0.05, chroma: 0.4, hue: 300)
        XCTAssertLessThanOrEqual(wcagContrast(outOfGamut, white, in: .sRGB), 21 + 1e-6)
    }

    /// APCA is polarity-sensitive: dark-on-light and light-on-dark differ.
    /// This is the property that makes it worth implementing over WCAG.
    func testAPCAIsPolaritySensitive() {
        let darkOnLight = apcaContrast(text: black, background: white)
        let lightOnDark = apcaContrast(text: white, background: black)
        XCTAssertNotEqual(darkOnLight, lightOnDark, accuracy: 1e-6)
        XCTAssertGreaterThan(abs(darkOnLight), 100)
    }

    func testAPCAIdenticalColoursIsZero() {
        let grey = Oklch(lightness: 0.5, chroma: 0, hue: 0)
        XCTAssertEqual(apcaContrast(text: grey, background: grey),
                       0, accuracy: 1e-9)
    }

    /// Pin P-TOL-5. Measured worst error across the fixture's `contrast-*`
    /// cases (a later revision, 6 cases: 5 in-gamut sRGB, 1 out-of-gamut sRGB):
    /// WCAG `3.552713678800501e-15`, APCA `2.4868995751603507e-14`. Sized
    /// roughly 3-4x the measurement, the same headroom band `P-TOL-3` uses,
    /// for legitimate cross-platform `libm` differences — see docs/pins.md
    /// for the full derivation, including the two real defects
    /// (rounded-constant luminance, unclamped negative luminance) this pin
    /// replaced a nine-to-ten-orders-looser `1e-6`/`1e-4` pair with.
    static let wcagTolerance = 1e-14
    static let apcaTolerance = 1e-13

    func testContrastMatchesColorJS() throws {
        let fixtures = try FixtureLoader.load()
        var worstWCAG = 0.0, worstAPCA = 0.0

        for c in fixtures.contrast {
            let fg = Oklch(lightness: c.fg_oklch[0], chroma: c.fg_oklch[1], hue: c.fg_oklch[2])
            let bg = Oklch(lightness: c.bg_oklch[0], chroma: c.bg_oklch[1], hue: c.bg_oklch[2])

            worstWCAG = max(worstWCAG, abs(wcagContrast(fg, bg, in: .sRGB) - c.wcag21))
            worstAPCA = max(worstAPCA,
                            abs(apcaContrast(text: fg, background: bg) - c.apca))
        }

        print("MEASURED wcag worst error: \(worstWCAG)")
        print("MEASURED apca worst error: \(worstAPCA)")
        XCTAssertLessThan(worstWCAG, Self.wcagTolerance)
        XCTAssertLessThan(worstAPCA, Self.apcaTolerance)
    }
}
