import SwiftUI
import OklchCore

#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif

// MARK: - Display gamut

private struct ColorGamutKey: EnvironmentKey {
    static let defaultValue: Gamut = .detected()
}

public extension EnvironmentValues {
    /// The gamut `OklchStyle` maps into before emitting a `Color`.
    ///
    /// SwiftUI exposes no display gamut, so this is ours. It defaults to a value
    /// detected once, at first use (see `Gamut.detected()`), and is overridable
    /// — chiefly so tests are deterministic, and so an external sRGB display can
    /// be told the truth rather than handed colours it cannot show. That
    /// override is also the mitigation for the staleness this caching implies:
    /// see `Gamut.detected()`'s doc comment.
    var colorGamut: Gamut {
        get { self[ColorGamutKey.self] }
        set { self[ColorGamutKey.self] = newValue }
    }
}

public extension View {
    /// Overrides the gamut `OklchStyle` maps into for this subtree.
    func colorGamut(_ gamut: Gamut) -> some View {
        environment(\.colorGamut, gamut)
    }
}

public extension Gamut {
    /// The display gamut detected once, at first use, and cached for the rest
    /// of the process.
    ///
    /// Probe `A4` measured `UITraitCollection.current` as meaningful
    /// inside `resolve(in:)`, so reading the trait directly on every resolve
    /// would also work. We cache a single value instead, computed lazily the
    /// first time anything reads it, for determinism in tests.
    ///
    /// **Failure mode this caching creates:** if an external display is
    /// attached, detached, or swapped for one with a different gamut mid-session
    /// (e.g. AirPlay to an sRGB TV, or docking to a wide-gamut monitor), this
    /// cached value goes STALE — it keeps reporting whatever gamut was detected
    /// at first use, not the display currently in front of the user. Nothing in
    /// this package re-detects automatically. The mitigation is `colorGamut(_:)`
    /// (`View`) / `\.colorGamut` (`EnvironmentValues`): a caller that observes a
    /// display change (e.g. via `UIScreen` notifications) must re-assert the
    /// correct gamut explicitly, or resolved colours will keep gamut-mapping
    /// against the wrong target.
    static func detected() -> Gamut { detectedGamut }
}

private let detectedGamut: Gamut = {
    #if canImport(UIKit)
    return UITraitCollection.current.displayGamut == .P3 ? .displayP3 : .sRGB
    #elseif canImport(AppKit)
    return (NSScreen.main?.canRepresent(.p3) ?? false) ? .displayP3 : .sRGB
    #else
    return .sRGB
    #endif
}()

// MARK: - Ambient background

private struct ThemeBackgroundKey: EnvironmentKey {
    static let defaultValue: Oklch? = nil
}

public extension EnvironmentValues {
    /// The background most recently drawn by `oklchBackground(_:)`.
    ///
    /// Deliberately has no public setter modifier: it is published only by the
    /// modifier that also draws it, so the environment cannot disagree with the
    /// pixels (ARCHITECTURE.md §4.4).
    internal(set) var themeBackground: Oklch? {
        get { self[ThemeBackgroundKey.self] }
        set { self[ThemeBackgroundKey.self] = newValue }
    }
}

// MARK: - Diagnostics

private struct OklchDiagnosticsKey: EnvironmentKey {
    static let defaultValue: (@Sendable (ContrastResolution) -> Void)? = nil
}

public extension EnvironmentValues {
    /// Called whenever a contrast solve falls short of its target.
    ///
    /// Renders never break on an unreachable target (ARCHITECTURE.md §4.6); this is how the
    /// shortfall becomes observable. Install it in DEBUG to log, or in tests to
    /// fail.
    var oklchDiagnostics: (@Sendable (ContrastResolution) -> Void)? {
        get { self[OklchDiagnosticsKey.self] }
        set { self[OklchDiagnosticsKey.self] = newValue }
    }
}

public extension View {
    /// Installs a handler called when a contrast target cannot be met.
    func oklchDiagnostics(
        _ handler: @escaping @Sendable (ContrastResolution) -> Void
    ) -> some View {
        environment(\.oklchDiagnostics, handler)
    }
}
