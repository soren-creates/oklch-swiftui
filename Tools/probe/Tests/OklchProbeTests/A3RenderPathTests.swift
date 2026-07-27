// Tools/probe/Tests/OklchProbeTests/A3RenderPathTests.swift
import XCTest
import SwiftUI
import CoreGraphics
@testable import OklchProbe

@available(iOS 17.0, macOS 14.0, *)
@MainActor
final class A3RenderPathTests: XCTestCase {

    /// Display P3 pure green — outside the sRGB gamut.
    static let p3Green = Color(.displayP3, red: 0, green: 1, blue: 0, opacity: 1)

    /// Reads the centre pixel as extended-range float sRGB.
    private func centrePixel<V: View>(of view: V) -> [Double]? {
        let renderer = ImageRenderer(content: view.frame(width: 16, height: 16))
        renderer.colorMode = .extendedLinear
        guard let cg = renderer.cgImage else { return nil }

        let space = CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!
        var px = [Float](repeating: 0, count: 4)
        guard let ctx = CGContext(
            data: &px, width: 1, height: 1,
            bitsPerComponent: 32, bytesPerRow: 16, space: space,
            bitmapInfo: CGBitmapInfo.floatComponents.rawValue
                | CGBitmapInfo.byteOrder32Little.rawValue
                | CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        ctx.draw(cg, in: CGRect(x: -8, y: -8, width: 16, height: 16))
        return [Double(px[0]), Double(px[1]), Double(px[2])]
    }

    func testP3SurvivesEachRenderPath() throws {
        let g = Self.p3Green

        var paths: [String: [Double]] = [:]
        paths["solid_fill"]   = centrePixel(of: Rectangle().fill(g))
        paths["foreground"]   = centrePixel(of: Rectangle().foregroundStyle(g))
        paths["gradient"]     = centrePixel(of: Rectangle().fill(
            LinearGradient(colors: [g, g], startPoint: .top, endPoint: .bottom)))
        paths["canvas"]       = centrePixel(of: Canvas { ctx, size in
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(g))
        })

        Evidence.record("A3", [
            "paths": paths.mapValues { $0 },
            "test_color": "displayP3(0,1,0)",
            "readback_space": "extendedLinearSRGB",
        ])

        let solid = try XCTUnwrap(paths["solid_fill"], "solid fill produced no pixel")

        // If P3 reached the buffer at all, red is negative in extended sRGB.
        XCTAssertLessThan(solid[0], 0,
            "P3 green clamped to sRGB on the solid-fill path — wide gamut is not reaching pixels")

        // Every path must agree with solid fill; disagreement is the forum-reported bug.
        for (name, value) in paths {
            let v = try XCTUnwrap(value, "\(name) produced no pixel")
            for i in 0..<3 {
                XCTAssertEqual(v[i], solid[i], accuracy: 0.01,
                    "render path '\(name)' disagrees with solid fill on channel \(i)")
            }
        }
    }
}
