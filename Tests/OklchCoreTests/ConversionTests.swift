import XCTest
@testable import OklchCore

final class ConversionTests: XCTestCase {

    /// Defect B3, from nikstar/swift-oklch: the gamma encoder took the linear
    /// branch for negative inputs, mis-encoding every out-of-gamut colour.
    /// The transfer curve must be odd: f(-x) == -f(x).
    func testTransferCurveIsSignSymmetric() {
        for v in stride(from: -1.5, through: 1.5, by: 0.05) {
            XCTAssertEqual(Gamut.encode(-v), -Gamut.encode(v), accuracy: 1e-12,
                           "encode is not sign-symmetric at \(v)")
            XCTAssertEqual(Gamut.decode(-v), -Gamut.decode(v), accuracy: 1e-12,
                           "decode is not sign-symmetric at \(v)")
        }
    }

    func testTransferCurveRoundTrips() {
        for v in stride(from: -1.5, through: 1.5, by: 0.01) {
            XCTAssertEqual(Gamut.decode(Gamut.encode(v)), v, accuracy: 1e-12)
        }
    }

    func testWhiteIsLightnessOneZeroChroma() {
        let white = rgbToOklch(RGB(red: 1, green: 1, blue: 1), in: .sRGB)
        XCTAssertEqual(white.lightness, 1.0, accuracy: 1e-12)
        XCTAssertEqual(white.chroma, 0.0, accuracy: 1e-12)
        XCTAssertTrue(white.isPowerless)
    }

    /// The matrix pairs must be genuine inverses. Review found two
    /// pairs that were not, costing eight orders of magnitude of round-trip
    /// accuracy while every other test still passed.
    func testMatrixPairsAreInverses() {
        func residual(_ a: Matrix3, _ b: Matrix3) -> Double {
            var worst = 0.0
            for i in 0..<3 {
                let basis = (i == 0 ? 1.0 : 0.0, i == 1 ? 1.0 : 0.0, i == 2 ? 1.0 : 0.0)
                let round = b.apply(a.apply(basis))
                let expected = [basis.0, basis.1, basis.2]
                for (j, got) in [round.0, round.1, round.2].enumerated() {
                    worst = max(worst, abs(got - expected[j]))
                }
            }
            return worst
        }

        XCTAssertLessThan(residual(Gamut.sRGB.toXYZ, Gamut.sRGB.fromXYZ), 1e-12)
        XCTAssertLessThan(residual(Gamut.displayP3.toXYZ, Gamut.displayP3.fromXYZ), 1e-12)
        XCTAssertLessThan(residual(lmsToXYZ, xyzToLMS), 1e-12)
        XCTAssertLessThan(residual(lmsToOklab, oklabToLms), 1e-12)
    }

    func testBlackIsLightnessZero() {
        let black = rgbToOklch(RGB(red: 0, green: 0, blue: 0), in: .sRGB)
        XCTAssertEqual(black.lightness, 0.0, accuracy: 1e-12)
    }

    /// P3 green is outside sRGB, so its sRGB red channel must go negative.
    /// This is the same signal probe A3 measured on device.
    func testP3GreenIsOutsideSRGB() {
        let p3Green = rgbToOklch(RGB(red: 0, green: 1, blue: 0), in: .displayP3)
        let asSRGB = oklchToRGB(p3Green, in: .sRGB)
        XCTAssertLessThan(asSRGB.red, 0, "P3 green should be unreachable in sRGB")
    }
}
