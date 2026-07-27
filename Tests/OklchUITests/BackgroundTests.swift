import XCTest
import SwiftUI
@testable import OklchUI
import OklchCore

@available(iOS 17.0, macOS 14.0, *)
@MainActor
final class BackgroundTests: XCTestCase {

    /// ARCHITECTURE.md §4.4: drawing and publishing are ONE modifier, so the environment
    /// cannot disagree with the pixels.
    func testBackgroundPublishesWhatItDraws() throws {
        let backdrop = Oklch(lightness: 0.92, chroma: 0.03, hue: 90)
        let style = OklchStyle(backdrop)

        final class Box: @unchecked Sendable { var seen: Oklch? }
        let box = Box()

        struct Probe: View {
            @Environment(\.themeBackground) var published: Oklch?
            let report: (Oklch?) -> Void
            var body: some View {
                Color.clear.onAppear { report(published) }
            }
        }

        let view = Probe(report: { box.seen = $0 })
            .oklchBackground(style)

        _ = try HostedRenderer.hostAndDraw(AnyView(view))

        XCTAssertEqual(box.seen, backdrop,
            "oklchBackground drew a colour it did not publish")
    }

    func testNoBackgroundMeansNilThemeBackground() {
        XCTAssertNil(EnvironmentValues().themeBackground)
    }

    /// `publishedColour` selects the variant the same way `resolve` does
    /// (ARCHITECTURE.md §4.4) — this was hand-verified correct during review via
    /// a scratch test that was then deleted, leaving the selection untested.
    /// That is exactly the "lying backdrop" case the one-writer design exists
    /// to prevent: if `oklchBackground` ever drew the dark variant but
    /// published the light one (or vice versa), `contrasting` would solve
    /// against a backdrop that does not match what is on screen. Asserts the
    /// DARK variant specifically, in a hosted `.dark` colour scheme, so a
    /// regression that always publishes `light` regardless of scheme fails
    /// this test.
    func testDarkSchemePublishesDarkVariantNotLight() throws {
        let base = Oklch(lightness: 0.92, chroma: 0.03, hue: 90)
        let darkVariant = Oklch(lightness: 0.18, chroma: 0.04, hue: 90)
        let style = OklchStyle(base).dark(darkVariant)

        final class Box: @unchecked Sendable {
            var called = false
            var seen: Oklch?
        }
        let box = Box()

        struct Probe: View {
            @Environment(\.themeBackground) var published: Oklch?
            let report: (Oklch?) -> Void
            var body: some View {
                Color.clear.onAppear { report(published) }
            }
        }

        let view = Probe(report: { box.called = true; box.seen = $0 })
            .oklchBackground(style)
            .environment(\.colorScheme, .dark)

        _ = try HostedRenderer.hostAndDraw(AnyView(view))

        XCTAssertTrue(box.called, "probe never observed \\.themeBackground")
        XCTAssertEqual(box.seen, darkVariant,
            "dark colour scheme published the light variant instead of the dark one")
    }

    /// A `.contrasting` background would be circular — it would need a
    /// backdrop to solve against — so `publishedColour` deliberately publishes
    /// `nil` rather than the solved colour (`Modifiers.swift`'s `guard case
    /// .fixed`). Previously untested; a regression that instead published the
    /// solved colour would go unnoticed.
    func testContrastingBackgroundPublishesNilThemeBackground() throws {
        let style = OklchStyle.contrasting(.wcag(4.5), hue: 250, chroma: 0.1)

        final class Box: @unchecked Sendable {
            var called = false
            var seen: Oklch?
        }
        let box = Box()

        struct Probe: View {
            @Environment(\.themeBackground) var published: Oklch?
            let report: (Oklch?) -> Void
            var body: some View {
                Color.clear.onAppear { report(published) }
            }
        }

        let view = Probe(report: { box.called = true; box.seen = $0 })
            .oklchBackground(style)

        _ = try HostedRenderer.hostAndDraw(AnyView(view))

        XCTAssertTrue(box.called, "probe never observed \\.themeBackground")
        XCTAssertNil(box.seen,
            "a .contrasting background published a themeBackground value instead of nil")
    }
}
