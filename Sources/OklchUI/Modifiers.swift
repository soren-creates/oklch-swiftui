import SwiftUI
import OklchCore

@available(iOS 17.0, macOS 14.0, *)
public extension View {
    /// Fills the background with `style` AND publishes it to
    /// `\.themeBackground`, so `OklchStyle.contrasting` can solve against it.
    ///
    /// Drawing and publishing are deliberately one call. A `\.themeBackground`
    /// any caller could set independently would drift out of sync with what is
    /// actually drawn, and a lying backdrop is worse than no backdrop
    /// (ARCHITECTURE.md §4.4).
    func oklchBackground(_ style: OklchStyle) -> some View {
        modifier(OklchBackgroundModifier(style: style))
    }
}

@available(iOS 17.0, macOS 14.0, *)
struct OklchBackgroundModifier: ViewModifier {
    let style: OklchStyle
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.colorGamut) private var gamut

    func body(content: Content) -> some View {
        content
            .background(style)
            .environment(\.themeBackground, publishedColour)
    }

    /// The OKLCH value actually drawn, selected the same way `resolve` selects
    /// it AND gamut-mapped the same way `resolve` maps it — `resolve(in:)`
    /// draws `gamutMap(chosen, to: gamut)`, so publishing the unmapped variant
    /// would let the environment disagree with the pixels for any out-of-gamut
    /// background, exactly the drift the one-writer design in this file's
    /// doc comment exists to prevent. Only `.fixed` styles publish; a
    /// `.contrasting` background would be circular (it would need a backdrop
    /// to solve against).
    private var publishedColour: Oklch? {
        guard case .fixed(let variants) = style.source else { return nil }
        let selected = variants.select(scheme: scheme, contrast: contrast)
        return gamutMap(selected, to: gamut)
    }
}
