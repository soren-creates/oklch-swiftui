import XCTest
import SwiftUI
@testable import OklchUI
import OklchCore

@available(iOS 17.0, macOS 14.0, *)
@MainActor
final class ResolveTests: XCTestCase {

    private let base = Oklch(lightness: 0.6, chroma: 0.10, hue: 250)
    private let darkVariant = Oklch(lightness: 0.8, chroma: 0.08, hue: 250)
    private let lightHC = Oklch(lightness: 0.3, chroma: 0.14, hue: 250)
    private let darkHC = Oklch(lightness: 0.95, chroma: 0.12, hue: 250)

    private func env(scheme: ColorScheme = .light, gamut: Gamut = .sRGB) -> EnvironmentValues {
        var e = EnvironmentValues()
        e.colorScheme = scheme
        e.colorGamut = gamut
        return e
    }

    /// P-TOL-1: anything through `Color.Resolved` is bounded by Float32.
    /// The literal itself lives in `TestTolerances.swift`'s
    /// `resolvedFloat32Tolerance`, shared with `CharacterizationTests`.
    private let resolvedTolerance = resolvedFloat32Tolerance

    /// A later revision: `Color.resolve(in:)` always reports components in
    /// extended sRGB regardless of a `Color`'s own tag (confirmed against
    /// this repo's probe evidence, probe A3, and directly measured).
    /// OklchCore's matrices and SwiftUI's internal P3->sRGB conversion agree
    /// to within ~5e-4 — real but not exact — so cross-checking `resolve`'s
    /// actual output against OklchCore's own predicted extended-sRGB value
    /// needs a looser bound than `resolvedTolerance`. Still two orders
    /// tighter than the ~0.1 per-channel gap a WRONG tag opens.
    private let crossImplementationTolerance = 2e-3

    private func components(_ color: Color, in environment: EnvironmentValues) -> [Double] {
        let r = color.resolve(in: environment)
        return [Double(r.red), Double(r.green), Double(r.blue)]
    }

    func testLightSchemeUsesBase() {
        let style = OklchStyle(base)
        let expected = oklchToRGB(gamutMap(base, to: .sRGB), in: .sRGB)
        let got = components(style.resolve(in: env()), in: env())
        XCTAssertEqual(got[0], expected.red, accuracy: resolvedTolerance)
        XCTAssertEqual(got[1], expected.green, accuracy: resolvedTolerance)
        XCTAssertEqual(got[2], expected.blue, accuracy: resolvedTolerance)
    }

    func testDarkSchemeUsesDarkVariantWhenPresent() {
        let style = OklchStyle(base).dark(darkVariant)
        let expected = oklchToRGB(gamutMap(darkVariant, to: .sRGB), in: .sRGB)
        let got = components(style.resolve(in: env(scheme: .dark)), in: env(scheme: .dark))
        XCTAssertEqual(got[0], expected.red, accuracy: resolvedTolerance)
        XCTAssertEqual(got[1], expected.green, accuracy: resolvedTolerance)
    }

    func testDarkSchemeFallsBackToBaseWhenNoDarkVariant() {
        let style = OklchStyle(base)
        let light = components(style.resolve(in: env()), in: env())
        let dark = components(style.resolve(in: env(scheme: .dark)), in: env(scheme: .dark))
        XCTAssertEqual(light[0], dark[0], accuracy: resolvedTolerance)
        XCTAssertEqual(light[1], dark[1], accuracy: resolvedTolerance)
    }

    /// The whole point of the package: the same style resolves DIFFERENTLY
    /// against different gamuts, because it gamut-maps late.
    ///
    /// DEVIATION from the original literal fixture: its `wide`
    /// (L=0.87, C=0.28, H=142.5) is measured in-gamut for BOTH sRGB and P3
    /// (`oklchToRGB(wide, in: .sRGB).isInGamut()` is true), so neither
    /// `gamutMap` call actually clips it — the two branches emit the same
    /// physical colour through different primaries, and `Color.resolve(in:)`
    /// (which always reports components in extended sRGB, confirmed against
    /// this repo's own probe evidence, probe A3: "negative red in
    /// extended-linear sRGB") correctly converges them to the same numbers,
    /// measured delta ~7e-4 — under the 1e-3 threshold, so the test doesn't
    /// discriminate. Replaced with a colour verified (see task-2 report) to
    /// be outside sRGB but inside P3, so `gamutMap` actually clips the sRGB
    /// branch and leaves the P3 branch untouched; measured delta ~0.228.
    func testGamutChangesTheResolvedColour() {
        let wide = Oklch(lightness: 0.7, chroma: 0.25, hue: 145)
        let style = OklchStyle(wide)

        let srgb = components(style.resolve(in: env(gamut: .sRGB)), in: env(gamut: .sRGB))
        let p3 = components(style.resolve(in: env(gamut: .displayP3)), in: env(gamut: .displayP3))

        let delta = zip(srgb, p3).map { abs($0 - $1) }.max() ?? 0
        XCTAssertGreaterThan(delta, 1e-3,
            "sRGB and P3 resolution produced the same colour — gamut mapping is not being applied")
    }

    /// DEVIATION from the original literal fixture: it checks
    /// a `[0,1]` bound on `Color.resolve(in:)`'s output, but that always
    /// reports components in extended sRGB (confirmed against this repo's
    /// own probe evidence, probe A3, and directly measured here: a
    /// P3-tagged colour that is legitimately outside sRGB but inside P3
    /// resolves to components >1 or <0 — e.g. measured 1.087 for
    /// `Oklch(0.7, 0.45, 30)` mapped to P3 — because extended sRGB is BY
    /// DESIGN unbounded so it can represent wide-gamut colours; SwiftUI's
    /// own colour management is doing its job correctly here, this is not a
    /// defect in `resolve(in:)`. `[0,1]` boundedness is a property of
    /// `gamutMap`'s contract relative to ITS OWN destination gamut.
    ///
    /// A later revision: the revision above was correct
    /// about the bound being unsatisfiable, but its rewrite discarded
    /// `OklchStyle(wild).resolve(in: e)`'s result with `_ =` and asserted
    /// directly on `oklchToRGB(gamutMap(...))` instead — pure `OklchCore`,
    /// already covered by `GamutMappingTests`, and provably not exercising
    /// `OklchStyle` at all: mutating `resolve(in:)` to `return Color.clear`
    /// left this test green. Rewritten again to assert `resolve(in:)`'s
    /// ACTUAL output against the extended-sRGB value OklchCore predicts for
    /// the mapped colour — `oklchToRGB(gamutMap(wild, to: gamut), in:
    /// .sRGB)` — for BOTH destination gamuts. This exercises the full
    /// map -> tag -> `Color.resolve` pipeline, is correct-by-construction
    /// (not merely bounded) for `.sRGB`, and is simultaneously tag-sensitive
    /// for `.displayP3` (see `testDisplayP3TagIsNotReinterpretedAsSRGB`
    /// below for the isolated version of that check).
    func testResolvedColourIsAlwaysInGamut() {
        let wild = Oklch(lightness: 0.7, chroma: 0.45, hue: 30)
        for gamut in [Gamut.sRGB, .displayP3] {
            let e = env(gamut: gamut)
            let got = components(OklchStyle(wild).resolve(in: e), in: e)

            let expected = oklchToRGB(gamutMap(wild, to: gamut), in: .sRGB)
            XCTAssertEqual(got[0], expected.red, accuracy: crossImplementationTolerance)
            XCTAssertEqual(got[1], expected.green, accuracy: crossImplementationTolerance)
            XCTAssertEqual(got[2], expected.blue, accuracy: crossImplementationTolerance)
        }
    }

    /// A later revision: the gamut TAG itself was asserted by
    /// nothing — replacing `emit`'s whole `if gamut == .displayP3` branch
    /// with the sRGB fall-through left 63/63 passing. Tagging IS observable:
    /// `Color.resolve(in:)` reports genuinely different numbers for the same
    /// underlying RGB components depending on whether the `Color` was
    /// tagged `.displayP3` or `.sRGB` (measured gap ~0.087-0.106 per
    /// channel for this fixture). The correct expectation is computable —
    /// for `gamut == .displayP3`, the extended-sRGB reading should equal
    /// `oklchToRGB(gamutMap(c, to: .displayP3), in: .sRGB)` (see
    /// `crossImplementationTolerance`'s doc comment for why 2e-3, not
    /// `resolvedTolerance`).
    func testDisplayP3TagIsNotReinterpretedAsSRGB() {
        let wild = Oklch(lightness: 0.7, chroma: 0.45, hue: 30)
        let style = OklchStyle(wild)
        let e = env(gamut: .displayP3)

        let got = components(style.resolve(in: e), in: e)
        let expected = oklchToRGB(gamutMap(wild, to: .displayP3), in: .sRGB)

        XCTAssertEqual(got[0], expected.red, accuracy: crossImplementationTolerance)
        XCTAssertEqual(got[1], expected.green, accuracy: crossImplementationTolerance)
        XCTAssertEqual(got[2], expected.blue, accuracy: crossImplementationTolerance)
    }

    // MARK: - colorSchemeContrast / Variants.select
    //
    // A later revision: this area was entirely uncovered — `env()` never set
    // contrast, `increasedContrast(...)` was never called by any test, and
    // `lightHC`/`darkHC` above were declared but unused. Mutating
    // `Variants.select` to ignore its `contrast` argument left 63/63 green
    // before this section existed.
    //
    // WHY THESE TESTS CALL `Variants.select` INSTEAD OF SETTING THE
    // ENVIRONMENT. The obvious shape for these cases would be to vary
    // `colorSchemeContrast` through the `env()` helper. That does not compile:
    // `EnvironmentValues.colorSchemeContrast` is get-only on this SDK
    // ("cannot assign to property: 'colorSchemeContrast' is a get-only
    // property"). That is pin `P-ENV-1` (docs/pins.md) — the setting is not
    // settable via `.environment`; varying it for real requires
    // `xcrun simctl ui <device> increase_contrast enabled|disabled` with the
    // suite run once per setting, which is what `HostedRenderer` and
    // `Tools/run-characterization.sh`'s two-pass runner do.
    //
    // A private, underscored `EnvironmentValues._colorSchemeContrast
    // { get set }` DOES exist, and was confirmed in isolation to make a bare
    // `EnvironmentValues` report an overridden value. It is deliberately NOT
    // used: routing around a documented platform constraint with undocumented
    // SPI would make these tests pass while proving something about Apple's
    // private API rather than about this package.
    //
    // What IS testable here without touching `EnvironmentValues` at all is
    // `Variants.select(scheme:contrast:)` — the internal function
    // `resolve(in:)` delegates to, and where a contrast-ignoring bug would
    // live. `Variants` is `internal`, reachable via `@testable import
    // OklchUI`. That covers the fallback chain and the increased-contrast
    // variants without contradicting P-ENV-1.
    //
    // What remains untested at this level — whether `resolve` correctly reads
    // whatever `colorSchemeContrast` a real host reports — is the tier-5
    // characterization tests' job (ARCHITECTURE.md §5.5: "one test per
    // environment input, proving `resolve(in:)` output actually CHANGES when
    // colorScheme, colorSchemeContrast and colorGamut change").

    func testSelectLightIncreasedUsesLightIncreasedVariant() {
        let variants = OklchStyle.Variants(light: base, dark: darkVariant,
                                           lightIncreased: lightHC, darkIncreased: darkHC)
        XCTAssertEqual(variants.select(scheme: .light, contrast: .increased), lightHC)
    }

    func testSelectDarkIncreasedUsesDarkIncreasedVariant() {
        let variants = OklchStyle.Variants(light: base, dark: darkVariant,
                                           lightIncreased: lightHC, darkIncreased: darkHC)
        XCTAssertEqual(variants.select(scheme: .dark, contrast: .increased), darkHC)
    }

    /// Fallback chain, first link: dark + increased with no `darkIncreased`
    /// supplied falls back to `dark`.
    func testSelectDarkIncreasedFallsBackToDarkWhenNoDarkIncreased() {
        let variants = OklchStyle.Variants(light: base, dark: darkVariant,
                                           lightIncreased: lightHC, darkIncreased: nil)
        XCTAssertEqual(variants.select(scheme: .dark, contrast: .increased), darkVariant)
    }

    /// Fallback chain, second link: dark + increased with NEITHER
    /// `darkIncreased` nor `dark` supplied falls all the way back to `light`.
    func testSelectDarkIncreasedFallsBackToLightWhenNeitherDarkNorDarkIncreased() {
        let variants = OklchStyle.Variants(light: base, dark: nil,
                                           lightIncreased: nil, darkIncreased: nil)
        XCTAssertEqual(variants.select(scheme: .dark, contrast: .increased), base)
    }

    /// The public `increasedContrast(light:dark:)` builder is itself never
    /// exercised by the four `select` tests above (they construct `Variants`
    /// directly) — this confirms it actually wires its arguments into
    /// `source`'s `Variants` rather than, say, silently discarding them.
    func testIncreasedContrastBuilderPopulatesVariants() {
        let style = OklchStyle(base).increasedContrast(light: lightHC, dark: darkHC)
        guard case .fixed(let variants) = style.source else {
            return XCTFail("expected .fixed source")
        }
        XCTAssertEqual(variants.light, base)
        XCTAssertEqual(variants.lightIncreased, lightHC)
        XCTAssertEqual(variants.darkIncreased, darkHC)
    }

    func testStyleIsHashableAndSendable() {
        let a = OklchStyle(base).dark(darkVariant)
        let b = OklchStyle(base).dark(darkVariant)
        XCTAssertEqual(a, b)
        XCTAssertEqual(a.hashValue, b.hashValue)
    }
}
