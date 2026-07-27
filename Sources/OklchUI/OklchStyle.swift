import SwiftUI
import OklchCore

/// A colour that stays in OKLCH until SwiftUI asks for it.
///
/// `resolve(in:)` reads exactly three environment values — `colorScheme`,
/// `colorSchemeContrast` and `colorGamut` — selects the matching variant,
/// gamut-maps it, and emits a `Color` tagged in the destination space.
///
/// That "exactly three" claim holds fully for `Source.fixed`. `Source
/// .contrasting` reads two more: `ContrastRequest.solve` (see
/// `OklchStyle+Contrasting.swift`) also reads `\.themeBackground` (to
/// resolve `.environment` backdrops) and writes to `\.oklchDiagnostics` (to
/// report unreachable targets).
///
/// Every existing OKLCH library for Swift converts eagerly, at construction
/// time, when none of those three values is knowable yet. That is the gap this
/// type exists to close.
@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, visionOS 1.0, *)
public struct OklchStyle: ShapeStyle, Sendable, Hashable {

    /// The four scheme/contrast combinations a caller may supply.
    /// Only `light` is required; the rest fall back to it.
    struct Variants: Sendable, Hashable {
        var light: Oklch
        var dark: Oklch?
        var lightIncreased: Oklch?
        var darkIncreased: Oklch?

        func select(scheme: ColorScheme, contrast: ColorSchemeContrast) -> Oklch {
            switch (scheme, contrast) {
            case (.dark, .increased):  return darkIncreased ?? dark ?? light
            case (.dark, _):           return dark ?? light
            case (_, .increased):      return lightIncreased ?? light
            default:                   return light
            }
        }
    }

    enum Source: Sendable, Hashable {
        case fixed(Variants)
        case contrasting(ContrastRequest)
    }

    var source: Source

    public init(_ base: Oklch) {
        source = .fixed(Variants(light: base))
    }

    init(source: Source) { self.source = source }

    /// Supplies the colour used when `colorScheme` is `.dark`.
    ///
    /// No-op on a style created by `contrasting(_:hue:chroma:preferring:against:)`,
    /// which adapts by solving against the backdrop rather than by variant
    /// selection: it returns `self` unchanged rather than reporting an error.
    public func dark(_ dark: Oklch) -> OklchStyle {
        guard case .fixed(var v) = source else { return self }
        v.dark = dark
        return OklchStyle(source: .fixed(v))
    }

    /// Supplies the colours used when Increase Contrast is on.
    ///
    /// Zero of the twenty libraries surveyed read `colorSchemeContrast` at all.
    ///
    /// No-op on a style created by `contrasting(_:hue:chroma:preferring:against:)`,
    /// which adapts by solving against the backdrop rather than by variant
    /// selection: it returns `self` unchanged rather than reporting an error.
    public func increasedContrast(light: Oklch? = nil, dark: Oklch? = nil) -> OklchStyle {
        guard case .fixed(var v) = source else { return self }
        v.lightIncreased = light
        v.darkIncreased = dark
        return OklchStyle(source: .fixed(v))
    }

    public func resolve(in environment: EnvironmentValues) -> Color {
        let gamut = environment.colorGamut

        let chosen: Oklch
        switch source {
        case .fixed(let variants):
            chosen = variants.select(scheme: environment.colorScheme,
                                     contrast: environment.colorSchemeContrast)
        case .contrasting(let request):
            chosen = request.solve(in: environment)
        }

        return Self.emit(gamutMap(chosen, to: gamut), in: gamut)
    }

    /// Maps to `gamut` and emits a `Color` tagged in the matching space.
    ///
    /// Tagging matters: handing P3 components to an sRGB-tagged `Color` would
    /// silently reinterpret them.
    static func emit(_ colour: Oklch, in gamut: Gamut) -> Color {
        let rgb = oklchToRGB(colour, in: gamut)
        if gamut == .displayP3 {
            return Color(.displayP3, red: rgb.red, green: rgb.green,
                         blue: rgb.blue, opacity: rgb.alpha)
        }
        return Color(.sRGB, red: rgb.red, green: rgb.green,
                     blue: rgb.blue, opacity: rgb.alpha)
    }
}
