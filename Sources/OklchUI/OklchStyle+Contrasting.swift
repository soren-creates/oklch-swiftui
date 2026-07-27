import SwiftUI
import OklchCore

/// Where a contrast solve gets its backdrop.
@available(iOS 17.0, macOS 14.0, *)
public enum Backdrop: Sendable, Hashable {
    /// Use whatever `oklchBackground(_:)` most recently published.
    case environment
    /// Use this colour regardless of the environment.
    case explicit(Oklch)
}

/// A deferred contrast solve. Stored, not computed, so `OklchStyle` stays
/// `Hashable` and the solve happens at resolve time against the real backdrop.
@available(iOS 17.0, macOS 14.0, *)
struct ContrastRequest: Sendable, Hashable {
    var target: ContrastTarget
    var hue: Double
    var chroma: Double
    var direction: Direction
    var backdrop: Backdrop

    /// Fallback when `.environment` is requested but nothing was published.
    /// White is chosen because an unstyled SwiftUI surface is light; the
    /// alternative — refusing to draw — is forbidden by ARCHITECTURE.md §4.6.
    static let fallbackBackdrop = Oklch(lightness: 1, chroma: 0, hue: 0)

    func solve(in environment: EnvironmentValues) -> Oklch {
        let resolvedBackdrop: Oklch
        switch backdrop {
        case .explicit(let colour): resolvedBackdrop = colour
        case .environment:          resolvedBackdrop = environment.themeBackground
                                                       ?? Self.fallbackBackdrop
        }

        // Measure against the backdrop as DRAWN, not as requested. resolve(in:)
        // draws gamutMap(chosen, to: gamut). An .environment backdrop arrives
        // already mapped — Modifiers.swift publishes the drawn variant — so this
        // re-map is idempotent for it; for an .explicit backdrop it is the only
        // mapping, without which an out-of-gamut backdrop would be measured
        // against a colour the screen never shows — the same ordering defect
        // solveContrast prevents on the candidate side (ARCHITECTURE.md §4.5).
        let drawn = gamutMap(resolvedBackdrop, to: environment.colorGamut)

        // Delegates to OklchCore, which gamut-maps each candidate BEFORE
        // measuring contrast (ARCHITECTURE.md §4.5). Never measure here.
        let (colour, resolution) = solveContrast(
            target: target,
            hue: hue,
            chroma: chroma,
            against: drawn,
            in: environment.colorGamut,
            preferring: direction)

        if !resolution.isSatisfied {
            environment.oklchDiagnostics?(resolution)
        }
        return colour
    }
}

@available(iOS 17.0, macOS 14.0, *)
public extension OklchStyle {
    /// A colour that meets `target` against the ambient background, solved at
    /// resolve time so it adapts to scheme, contrast setting and gamut.
    ///
    /// Unreachable targets return the best achievable colour and report the
    /// shortfall through `\.oklchDiagnostics` — renders never break
    /// (ARCHITECTURE.md §4.6).
    static func contrasting(
        _ target: ContrastTarget,
        hue: Double,
        chroma: Double,
        preferring direction: Direction = .automatic,
        against backdrop: Backdrop = .environment
    ) -> OklchStyle {
        OklchStyle(source: .contrasting(ContrastRequest(
            target: target, hue: hue, chroma: chroma,
            direction: direction, backdrop: backdrop)))
    }
}
