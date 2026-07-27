import Foundation
import XCTest

struct FixtureCase: Decodable {
    let id: String
    let oklch: [Double]
    let srgb: [Double]
    let p3: [Double]
    let in_srgb_gamut: Bool
    let in_p3_gamut: Bool
    let mapped_css_srgb: [Double]?
    let mapped_css_oklch: [Double]?
    let mapped_clip_srgb: [Double]?
}

struct HueArcCase: Decodable {
    let id: String
    let from: Double
    let to: Double
    let shortest_arc: Double
}

struct ContrastCase: Decodable {
    let id: String
    let fg_oklch: [Double]
    let bg_oklch: [Double]
    let fg_srgb: [Double]
    let bg_srgb: [Double]
    let wcag21: Double
    let apca: Double
}

struct FixtureFile: Decodable {
    struct Generator: Decodable { let colorjs: String; let node: String }
    let generator: Generator
    let cases: [FixtureCase]
    let hue_arcs: [HueArcCase]
    let contrast: [ContrastCase]
}

/// A missing or unusable fixture file is a broken checkout, not an acceptable
/// test environment — it must fail the suite, not skip it. Skipping is how
/// the ENTIRE Color.js oracle (ARCHITECTURE.md §5.1, "the package's principal
/// differentiator") could silently vanish from a run while `swift test`
/// still exits zero. See docs/pins.md's Linux build verification section.
struct FixtureLoadError: Error, CustomStringConvertible {
    let description: String
}

enum FixtureLoader {
    static func load(file: StaticString = #filePath) throws -> FixtureFile {
        // Walk up from this source file to the repo root, so the fixtures are
        // found identically on macOS and Linux without relying on Bundle.module.
        var dir = URL(fileURLWithPath: "\(file)").deletingLastPathComponent()
        for _ in 0..<6 {
            let candidate = dir
                .appendingPathComponent("Fixtures/colorjs/conversions.json")
            if FileManager.default.fileExists(atPath: candidate.path) {
                let data = try Data(contentsOf: candidate)
                return try JSONDecoder().decode(FixtureFile.self, from: data)
            }
            dir = dir.deletingLastPathComponent()
        }
        let message = "Fixtures not found — run `npm run generate` in Tools/gen-fixtures. " +
            "A missing fixture file is a broken checkout, not a skippable environment: " +
            "this FAILS the test rather than skipping it."
        XCTFail(message)
        throw FixtureLoadError(description: message)
    }
}
