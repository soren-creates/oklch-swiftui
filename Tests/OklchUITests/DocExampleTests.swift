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

    /// Every `verified-by:` marker in the catalog must name a test that exists
    /// in this file. Catches a doc example whose test was renamed or deleted.
    func testEveryVerifiedByMarkerNamesARealTest() throws {
        let docc = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()      // OklchUITests
            .deletingLastPathComponent()      // Tests
            .deletingLastPathComponent()      // repo root
            .appendingPathComponent("Sources/OklchUI/OklchUI.docc")

        let files = try FileManager.default.contentsOfDirectory(at: docc,
            includingPropertiesForKeys: nil)
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
            XCTAssertTrue(Self.instancesRespond(to: Selector(marker)),
                "DocC claims verification by '\(marker)', which is not a test in this file")
        }
    }
}
