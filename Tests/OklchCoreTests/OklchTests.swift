// Tests/OklchCoreTests/OklchTests.swift
import XCTest
@testable import OklchCore

final class OklchTests: XCTestCase {

    func testHueWrapsIntoCanonicalRange() {
        XCTAssertEqual(Oklch(lightness: 0.5, chroma: 0.1, hue: 370).hue, 10, accuracy: 1e-12)
        XCTAssertEqual(Oklch(lightness: 0.5, chroma: 0.1, hue: -10).hue, 350, accuracy: 1e-12)
        XCTAssertEqual(Oklch(lightness: 0.5, chroma: 0.1, hue: 360).hue, 0, accuracy: 1e-12)
        XCTAssertEqual(Oklch(lightness: 0.5, chroma: 0.1, hue: -720).hue, 0, accuracy: 1e-12)
    }

    func testPowerlessnessIsDerivedFromChroma() {
        XCTAssertTrue(Oklch(lightness: 1, chroma: 0, hue: 89.9).isPowerless)
        XCTAssertTrue(Oklch(lightness: 1, chroma: 1e-5, hue: 89.9).isPowerless)
        XCTAssertFalse(Oklch(lightness: 1, chroma: 1e-3, hue: 89.9).isPowerless)
    }

    func testAlphaDefaultsToOne() {
        XCTAssertEqual(Oklch(lightness: 0.5, chroma: 0.1, hue: 30).alpha, 1)
    }

    func testHueNormalisesOnAssignment() {
        var c = Oklch(lightness: 0.5, chroma: 0.1, hue: 30)
        c.hue = 720
        XCTAssertEqual(c.hue, 0, accuracy: 1e-12)
        c.hue = -10
        XCTAssertEqual(c.hue, 350, accuracy: 1e-12)
        c.hue = 370
        XCTAssertEqual(c.hue, 10, accuracy: 1e-12)
    }

    func testEqualityRespectsNormalisedHue() {
        var a = Oklch(lightness: 0.5, chroma: 0.1, hue: 10)
        let b = Oklch(lightness: 0.5, chroma: 0.1, hue: 370)
        XCTAssertEqual(a, b)
        a.hue = 730          // 730 mod 360 == 10
        XCTAssertEqual(a, b, "mutated hue should still compare equal after wrapping")
    }
}
