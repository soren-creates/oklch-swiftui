import XCTest
import SwiftUI
@testable import OklchUI
import OklchCore

@available(iOS 17.0, macOS 14.0, *)
@MainActor
final class EnvironmentTests: XCTestCase {

    func testColorGamutDefaultsToDetected() {
        XCTAssertEqual(EnvironmentValues().colorGamut, Gamut.detected())
    }

    func testColorGamutIsSettable() {
        var env = EnvironmentValues()
        env.colorGamut = .sRGB
        XCTAssertEqual(env.colorGamut, .sRGB)
        env.colorGamut = .displayP3
        XCTAssertEqual(env.colorGamut, .displayP3)
    }

    func testThemeBackgroundDefaultsToNil() {
        XCTAssertNil(EnvironmentValues().themeBackground)
    }

    func testDiagnosticsDefaultsToNilAndIsInvocable() {
        XCTAssertNil(EnvironmentValues().oklchDiagnostics)

        final class Box: @unchecked Sendable { var seen: ContrastResolution? }
        let box = Box()
        var env = EnvironmentValues()
        env.oklchDiagnostics = { box.seen = $0 }
        env.oklchDiagnostics?(ContrastResolution(requested: 7, achieved: 4.5))

        XCTAssertEqual(box.seen?.requested, 7)
        XCTAssertEqual(box.seen?.achieved, 4.5)
    }
}
