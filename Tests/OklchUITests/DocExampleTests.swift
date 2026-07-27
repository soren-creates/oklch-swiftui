// ARCHITECTURE.md §6 requires DocC examples be verified programmatically: they must
// compile AND produce the values they claim. Each test here mirrors one
// value-claiming example in the DocC catalog, and each example carries a
// `verified-by:` comment naming its test. If you change a claimed value in the
// docs, the paired test must change with it.
import XCTest
import SwiftUI
@testable import OklchUI
import OklchCore

@available(iOS 17.0, macOS 14.0, *)
@MainActor
final class DocExampleTests: XCTestCase {

    /// Mirrors GettingStarted.md, "Text that meets a contrast target":
    /// "Against white, `.wcag(4.5)` at hue 250 and chroma 0.1 resolves to a
    /// lightness of approximately `0.57`."
    func testGettingStartedContrastingLightnessClaim() {
        var e = EnvironmentValues()
        e.colorGamut = .sRGB
        e.themeBackground = Oklch(lightness: 1, chroma: 0, hue: 0)

        let request = ContrastRequest(target: .wcag(4.5), hue: 250, chroma: 0.1,
                                      direction: .automatic, backdrop: .environment)
        let solved = request.solve(in: e)

        print("MEASURED doc getting-started lightness: \(solved.lightness)")
        XCTAssertEqual(solved.lightness, 0.57, accuracy: 0.02,
            "the documented lightness no longer matches — update BOTH the doc and this test")
    }

    /// Mirrors GettingStarted.md, "When a target cannot be met": APCA Lc 120
    /// against mid-grey is unreachable and reports a shortfall.
    func testGettingStartedUnreachableClaim() {
        final class Box: @unchecked Sendable { var seen: ContrastResolution? }
        let box = Box()

        var e = EnvironmentValues()
        e.colorGamut = .sRGB
        e.themeBackground = Oklch(lightness: 0.5, chroma: 0, hue: 0)
        e.oklchDiagnostics = { box.seen = $0 }

        _ = ContrastRequest(target: .apca(120), hue: 200, chroma: 0.2,
                            direction: .automatic, backdrop: .environment).solve(in: e)

        XCTAssertNotNil(box.seen)
        XCTAssertLessThan(box.seen!.achieved, 120)
    }

    /// Mirrors README.md, "The solution": the `late` declaration resolves
    /// differently in four environments — the claim the section's demos rest
    /// on. The values asserted here are in each environment's destination
    /// space, exactly as `OklchStyle.emit` hands them to `Color`.
    ///
    /// The Increase Contrast row cannot go through `resolve(in:)` in this
    /// host: `EnvironmentValues.colorSchemeContrast` is get-only (P-ENV-1,
    /// docs/pins.md). That row exercises `Variants.select` — the function
    /// `resolve(in:)` delegates to — followed by the same map-and-convert
    /// every other row gets. Whether a real host's contrast setting reaches
    /// `resolve` is the tier-5 characterization suite's job.
    func testReadmeWhyThisExistsTable() {
        let base = Oklch(lightness: 0.55, chroma: 0.18, hue: 250)
        let dark = Oklch(lightness: 0.85, chroma: 0.06, hue: 250)
        let lightHC = Oklch(lightness: 0.38, chroma: 0.09, hue: 250)
        let style = OklchStyle(base).dark(dark).increasedContrast(light: lightHC)

        // The premise of the sRGB-vs-P3 rows: base genuinely exceeds sRGB and
        // genuinely fits P3, so the sRGB row is mapped and the P3 row is not.
        XCTAssertFalse(oklchToRGB(base, in: .sRGB).isInGamut(),
            "base no longer exceeds sRGB — the README's P3 row proves nothing")
        XCTAssertTrue(oklchToRGB(base, in: .displayP3).isInGamut(),
            "base no longer fits P3 — the README's P3 row would be mapped too")
        XCTAssertEqual(gamutMap(base, to: .displayP3), base,
            "P3 should leave an in-P3-gamut colour untouched")

        // Row values in each row's destination space (what emit passes to
        // Color). Row 4 via select — see the doc comment above.
        let row1 = oklchToRGB(gamutMap(base, to: .sRGB), in: .sRGB)
        let row2 = oklchToRGB(gamutMap(dark, to: .sRGB), in: .sRGB)
        let row3 = oklchToRGB(base, in: .displayP3)
        guard case .fixed(let variants) = style.source else {
            return XCTFail("expected .fixed source")
        }
        let chosen4 = variants.select(scheme: .light, contrast: .increased)
        XCTAssertEqual(chosen4, lightHC)
        let row4 = oklchToRGB(gamutMap(chosen4, to: .sRGB), in: .sRGB)

        for (label, row) in [("1 light-sRGB", row1), ("2 dark-sRGB", row2),
                             ("3 light-P3", row3), ("4 lightHC-sRGB", row4)] {
            print("MEASURED README table row \(label): " +
                  "(\(row.red), \(row.green), \(row.blue))")
        }

        // Rows 1-3 cross-checked against resolve(in:)'s ACTUAL output.
        // Color.resolve(in:) always reports extended sRGB regardless of tag
        // (probe A3), so the prediction converts through .sRGB; 2e-3 is
        // ResolveTests.crossImplementationTolerance's bound and rationale.
        let crossTolerance = 2e-3
        let cases: [(ColorScheme, Gamut, Oklch)] =
            [(.light, .sRGB, base), (.dark, .sRGB, dark), (.light, .displayP3, base)]
        for (scheme, gamut, chosen) in cases {
            var e = EnvironmentValues()
            e.colorScheme = scheme
            e.colorGamut = gamut
            let got = style.resolve(in: e).resolve(in: e)
            let predicted = oklchToRGB(gamutMap(chosen, to: gamut), in: .sRGB)
            XCTAssertEqual(Double(got.red), predicted.red, accuracy: crossTolerance)
            XCTAssertEqual(Double(got.green), predicted.green, accuracy: crossTolerance)
            XCTAssertEqual(Double(got.blue), predicted.blue, accuracy: crossTolerance)
        }

        // The README literals (3 dp; 6e-4 covers rounding). If any of these
        // fail, update BOTH the README table and these literals.
        func assertRow(_ row: RGB, _ literals: [Double], line: UInt = #line) {
            XCTAssertEqual(row.red, literals[0], accuracy: 6e-4, line: line)
            XCTAssertEqual(row.green, literals[1], accuracy: 6e-4, line: line)
            XCTAssertEqual(row.blue, literals[2], accuracy: 6e-4, line: line)
        }
        assertRow(row1, [0.000, 0.449, 0.834])
        assertRow(row2, [0.693, 0.822, 0.958])
        assertRow(row3, [0.122, 0.441, 0.807])
        assertRow(row4, [0.082, 0.268, 0.439])
    }

    /// Mirrors README.md's eager-vs-late comparison images: the committed
    /// SVGs in docs/assets/ must carry exactly the colours OklchCore's
    /// pipeline produces for the declared OKLCH values. Regenerate with
    /// `swift run` in Tools/readme-swatches/ if this fails.
    func testReadmeComparisonSvgsMatchPipeline() throws {
        // The same declarations Tools/readme-swatches/ generates from.
        let base = Oklch(lightness: 0.55, chroma: 0.18, hue: 250)
        let lightSurface = Oklch(lightness: 0.985, chroma: 0.002, hue: 250)
        let midPanel = Oklch(lightness: 0.62, chroma: 0.06, hue: 250)
        let darkSurface = Oklch(lightness: 0.18, chroma: 0.01, hue: 250)
        let rampHue = 210.0

        func lateRGB(_ c: Oklch) -> RGB { oklchToRGB(gamutMap(c, to: .sRGB), in: .sRGB) }
        func clipRGB(_ c: Oklch) -> RGB {
            let raw = oklchToRGB(c, in: .sRGB)
            return RGB(red: min(max(raw.red, 0), 1),
                       green: min(max(raw.green, 0), 1),
                       blue: min(max(raw.blue, 0), 1),
                       alpha: raw.alpha)
        }
        func hex(_ rgb: RGB) -> String {
            func channel(_ v: Double) -> Int { Int((min(max(v, 0), 1) * 255).rounded()) }
            return String(format: "#%02X%02X%02X",
                          channel(rgb.red), channel(rgb.green), channel(rgb.blue))
        }
        func late(_ c: Oklch) -> String { hex(lateRGB(c)) }
        func clip(_ c: Oklch) -> String { hex(clipRGB(c)) }

        let chips = stride(from: 0.0, through: 0.40, by: 0.04).map {
            Oklch(lightness: 0.5, chroma: $0, hue: rampHue)
        }

        // The ramp's premises: strategies agree chip-for-chip while in gamut;
        // past the boundary the clipped hue drifts visibly (>30°) while the
        // mapped hue holds (<5°) — the claim the graph and captions make.
        XCTAssertEqual(clip(chips[1]), late(chips[1]),
            "in-gamut chips should be identical under both strategies")
        XCTAssertNotEqual(clip(chips[10]), late(chips[10]),
            "clip and map agree at max chroma — the ramp shows nothing")
        // The README's "just past C≈0.09" claim, bracketed: 0.08 still fits
        // sRGB, 0.12 already needs negative red — which the clip snaps to 0.
        XCTAssertTrue(oklchToRGB(chips[2], in: .sRGB).isInGamut())
        XCTAssertLessThan(oklchToRGB(chips[3], in: .sRGB).red, 0)
        XCTAssertLessThan(oklchToRGB(chips[10], in: .sRGB).red, 0)
        let clipHue = rgbToOklch(clipRGB(chips[10]), in: .sRGB).hue
        let mapHue = rgbToOklch(lateRGB(chips[10]), in: .sRGB).hue
        XCTAssertGreaterThan(abs(clipHue - rampHue), 30,
            "clip hue drift is no longer visible — re-choose the ramp hue")
        XCTAssertLessThan(abs(mapHue - rampHue), 5,
            "the map no longer holds the declared hue")

        // The contrast demo's premises, measured not rhetorical. The fixed
        // foreground is the BEST a single value can be — correctly solved
        // for the light surface — and must still fail on the other three
        // backdrops, while the per-backdrop solve passes on all four.
        let backdrops = [lightSurface, midPanel, darkSurface, base]
        func solved(against backdrop: Oklch) -> (colour: Oklch, resolution: ContrastResolution) {
            solveContrast(target: .wcag(4.5), hue: 250, chroma: 0.1,
                          against: gamutMap(backdrop, to: .sRGB), in: .sRGB)
        }
        let fixedForeground = solved(against: lightSurface).colour
        func ratio(_ fg: Oklch, on backdrop: Oklch) -> Double {
            wcagContrast(gamutMap(fg, to: .sRGB), gamutMap(backdrop, to: .sRGB), in: .sRGB)
        }
        XCTAssertGreaterThanOrEqual(ratio(fixedForeground, on: lightSurface), 4.5)
        for backdrop in backdrops.dropFirst() {
            XCTAssertLessThan(ratio(fixedForeground, on: backdrop), 4.5,
                "the fixed value passes here — the hard-coded column's FAIL is wrong")
        }
        var solvedForegrounds: [Oklch] = []
        for backdrop in backdrops {
            let (colour, resolution) = solved(against: backdrop)
            XCTAssertTrue(resolution.isSatisfied)
            XCTAssertGreaterThanOrEqual(ratio(colour, on: backdrop), 4.5)
            solvedForegrounds.append(colour)
        }
        // The central claim, proven: at this hue and chroma NO single
        // lightness passes 4.5:1 on all four backdrops.
        let anySinglePasses = stride(from: 0.0, through: 1.0, by: 0.002).contains { l in
            let candidate = Oklch(lightness: l, chroma: 0.1, hue: 250)
            return backdrops.allSatisfy { ratio(candidate, on: $0) >= 4.5 }
        }
        XCTAssertFalse(anySinglePasses,
            "a single value passes every backdrop — the demo's claim is false")

        let assets = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()      // OklchUITests
            .deletingLastPathComponent()      // Tests
            .deletingLastPathComponent()      // repo root
            .appendingPathComponent("docs/assets")
        let expectations: [(file: String, hexes: [String])] = [
            ("contrast-solve.svg", backdrops.map(late) + [late(fixedForeground)]
                + solvedForegrounds.map(late)),
            ("gamut-ramp.svg", chips.map(clip) + chips.map(late)),
        ]
        for (file, hexes) in expectations {
            let svg = try String(contentsOf: assets.appendingPathComponent(file),
                                 encoding: .utf8)
            for hexValue in hexes {
                XCTAssertTrue(svg.contains("fill=\"\(hexValue)\""),
                    "\(file) is missing \(hexValue) — regenerate via Tools/readme-swatches")
            }
        }
    }

    /// Every `verified-by:` marker in the DocC catalog AND the README must
    /// name a test that exists in this file. Catches a doc example whose test
    /// was renamed or deleted.
    func testEveryVerifiedByMarkerNamesARealTest() throws {
        let docc = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()      // OklchUITests
            .deletingLastPathComponent()      // Tests
            .deletingLastPathComponent()      // repo root
            .appendingPathComponent("Sources/OklchUI/OklchUI.docc")

        let readme = docc
            .deletingLastPathComponent()      // OklchUI
            .deletingLastPathComponent()      // Sources
            .deletingLastPathComponent()      // repo root
            .appendingPathComponent("README.md")
        let files = try FileManager.default.contentsOfDirectory(at: docc,
            includingPropertiesForKeys: nil) + [readme]
        var markers: [String] = []
        for file in files where file.pathExtension == "md" {
            let text = try String(contentsOf: file, encoding: .utf8)
            for line in text.split(separator: "\n") where line.contains("verified-by:") {
                if let name = line.split(separator: ":").last?
                    .replacingOccurrences(of: "-->", with: "")
                    .trimmingCharacters(in: .whitespaces) {
                    markers.append(name)
                }
            }
        }

        XCTAssertFalse(markers.isEmpty, "no verified-by markers found — did the catalog move?")

        // A REAL existence check via the Objective-C runtime, not a hardcoded
        // array. A later revision: the array-based version
        // checked markers against a list maintained BY HAND in this same
        // file, so renaming a test (e.g.
        // `testGettingStartedUnreachableClaim` -> `testRenamedByMistake`)
        // while leaving both the DocC marker and the array untouched kept
        // this check green — it could never detect the exact drift its own
        // doc comment claimed to catch. `instancesRespond(to:)` asks the
        // runtime directly whether this test case class actually implements
        // a method with that selector, so a renamed or deleted test method
        // fails here regardless of what any list says.
        for marker in markers {
            // A Swift `throws` test's ObjC selector is `name + "AndReturnError:"`.
            let exists = Self.instancesRespond(to: Selector(marker))
                || Self.instancesRespond(to: Selector(marker + "AndReturnError:"))
            XCTAssertTrue(exists,
                "docs claim verification by '\(marker)', which is not a test in this file")
        }
    }
}
