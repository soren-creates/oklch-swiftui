import XCTest
@testable import OklchCore

final class InterpolationTests: XCTestCase {

    func testShortestArcTakesTheShortWayRound() {
        XCTAssertEqual(shortestHueArc(from: 28.5, to: 328.4), -60.1, accuracy: 1e-9)
        XCTAssertEqual(shortestHueArc(from: 328.4, to: 28.5), 60.1, accuracy: 1e-9)
        XCTAssertEqual(shortestHueArc(from: 30, to: 90), 60, accuracy: 1e-9)
        XCTAssertEqual(abs(shortestHueArc(from: 0, to: 180)), 180, accuracy: 1e-9)
    }

    func testEndpointsAreExact() {
        let a = Oklch(lightness: 0.3, chroma: 0.1, hue: 20)
        let b = Oklch(lightness: 0.8, chroma: 0.2, hue: 200)
        XCTAssertEqual(interpolate(a, b, t: 0).hue, a.hue, accuracy: 1e-9)
        XCTAssertEqual(interpolate(a, b, t: 1).hue, b.hue, accuracy: 1e-9)
        XCTAssertEqual(interpolate(a, b, t: 1).lightness, b.lightness, accuracy: 1e-9)
    }

    /// Defect B2: white has chroma 0 and a numerically garbage hue. Interpolating
    /// that hue produces a green/cyan cast mid-gradient. The powerless component
    /// must adopt its partner's hue instead.
    func testPowerlessEndpointAdoptsPartnerHue() {
        let white = Oklch(lightness: 1.0, chroma: 0.0, hue: 89.9)
        let blue = Oklch(lightness: 0.45, chroma: 0.31, hue: 264.1)

        for t in stride(from: 0.0, through: 1.0, by: 0.1) {
            let mid = interpolate(white, blue, t: t)
            XCTAssertEqual(mid.hue, blue.hue, accuracy: 1e-9,
                           "hue drifted from the powered endpoint at t=\(t)")
        }
    }

    func testBothPowerlessStaysAchromatic() {
        let a = Oklch(lightness: 0, chroma: 0, hue: 12)
        let b = Oklch(lightness: 1, chroma: 0, hue: 300)
        let mid = interpolate(a, b, t: 0.5)
        XCTAssertEqual(mid.chroma, 0, accuracy: 1e-12)
    }
}
