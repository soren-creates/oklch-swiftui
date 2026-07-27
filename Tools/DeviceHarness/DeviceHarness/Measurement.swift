// Tools/DeviceHarness/DeviceHarness/Measurement.swift
//
// ARCHITECTURE.md §5.6. Renders known out-of-sRGB swatches on REAL hardware, reads the
// pixels back, and reports what it measured. Nothing here asserts a
// hand-written expectation — the point is to LEARN what the device does.
import SwiftUI
import UIKit
import CoreGraphics
import Darwin
import OklchCore
import OklchUI

enum Measurement {

    /// `UIDevice.current.model` returns the generic `"iPhone"` on every iPhone
    /// — not useful for evidence that claims to be self-supporting. `utsname`'s
    /// `machine` field gives the real hardware identifier (e.g. `iPhone14,7`),
    /// which is what the findings prose actually cites.
    static func hardwareModelIdentifier() -> String {
        var info = utsname()
        uname(&info)
        let machineMirror = Mirror(reflecting: info.machine)
        return machineMirror.children.reduce(into: "") { identifier, element in
            guard let value = element.value as? Int8, value != 0 else { return }
            identifier += String(UnicodeScalar(UInt8(value)))
        }
    }

    /// String form of `UITraitCollection.current.displayGamut` — the raw
    /// system trait `Gamut.detected()` (`Sources/OklchUI/Environment.swift:63`)
    /// reads to compute its default. It is the ONE input in this entire
    /// harness that a real Display P3 panel could report differently from a
    /// Simulator; every other measurement here is deterministic CoreGraphics
    /// colour math that runs identically on both. Recording it lets this run
    /// validate the package's own auto-detection default on real hardware,
    /// rather than only re-confirming framework determinism.
    static func displayGamutTraitDescription(_ gamut: UIDisplayGamut) -> String {
        switch gamut {
        case .unspecified: return "unspecified"
        case .SRGB: return "SRGB"
        case .P3: return "P3"
        @unknown default: return "unknown(\(gamut.rawValue))"
        }
    }

    /// Display P3 pure green — outside sRGB. Identical to probe A3's swatch so
    /// device and Simulator numbers are directly comparable.
    static let p3Green = Color(.displayP3, red: 0, green: 1, blue: 0, opacity: 1)

    /// Reads the centre pixel as extended-range float sRGB.
    ///
    /// `byteOrder32Little` is required alongside `floatComponents`; without it
    /// `CGContext` returns nil. Learned during the SwiftUI probes — do not drop it.
    @MainActor
    static func centrePixel<V: View>(of view: V) -> [Double]? {
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

    @discardableResult
    static func emit(_ payload: [String: Any]) -> String? {
        guard let data = try? JSONSerialization.data(withJSONObject: payload,
                                                     options: [.sortedKeys]) else { return nil }
        let line = String(decoding: data, as: UTF8.self)
        print("DEVICE-EVIDENCE \(line)")
        return line
    }

    @MainActor
    static func runAll() -> String {
        let g = p3Green
        var paths: [String: [Double]] = [:]

        paths["solid_fill"] = centrePixel(of: Rectangle().fill(g))
        paths["foreground"] = centrePixel(of: Rectangle().foregroundStyle(g))
        paths["gradient"]   = centrePixel(of: Rectangle().fill(
            LinearGradient(colors: [g, g], startPoint: .top, endPoint: .bottom)))
        paths["canvas"]     = centrePixel(of: Canvas { ctx, size in
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(g))
        })

        // The path that did not exist when probe A3 ran.
        let style = OklchStyle(rgbToOklch(RGB(red: 0, green: 1, blue: 0), in: .displayP3))
        paths["oklch_style"] = centrePixel(
            of: Rectangle().fill(style).environment(\.colorGamut, .displayP3))

        var lines: [String] = []

        if let l = emit([
            "probe": "C2-render-paths",
            "test_color": "displayP3(0,1,0)",
            "readback_space": "extendedLinearSRGB",
            "device_model": UIDevice.current.model,
            "device_model_identifier": hardwareModelIdentifier(),
            "system_version": UIDevice.current.systemVersion,
            // The one hardware-dependent measurement in this harness: see the
            // doc comments on `hardwareModelIdentifier()` and
            // `displayGamutTraitDescription(_:)` above.
            "display_gamut_trait": displayGamutTraitDescription(UITraitCollection.current.displayGamut),
            "gamut_detected": Gamut.detected().name,
            "paths": paths,
        ]) { lines.append(l) }

        // Gradient-vs-solid agreement: Forums 727506 did NOT reproduce on either
        // Simulator runtime. This is the real test.
        if let solid = paths["solid_fill"], let grad = paths["gradient"] {
            let worst = zip(solid, grad).map { abs($0 - $1) }.max() ?? 0
            if let l = emit([
                "probe": "C2-gradient-agreement",
                "solid_fill": solid, "gradient": grad, "worst_delta": worst,
            ]) { lines.append(l) }
        }

        // Also write to the container, per ARCHITECTURE.md §5.6's "writes the measured
        // values to a file". The console capture is the primary route; this is
        // a second, independently pullable copy.
        let payload = "{\"measurements\":[\(lines.joined(separator: ","))]}"
        if let docs = FileManager.default.urls(for: .documentDirectory,
                                               in: .userDomainMask).first {
            try? payload.write(to: docs.appendingPathComponent("ondevice-p3.json"),
                               atomically: true, encoding: .utf8)
        }

        return paths["solid_fill"].map { "red=\($0[0])" } ?? "no pixel"
    }
}
