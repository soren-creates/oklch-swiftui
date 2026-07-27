/// A colour in the OKLCH cylindrical form of Ottosson's OKLab.
///
/// Hue is plain `Double` degrees rather than an `Angle`: it matches CSS and every
/// OKLCH tool on the web, and avoids the radians/degrees ambiguity an `Angle`-based
/// API invites (ARCHITECTURE.md §4.1).
public struct Oklch: Hashable, Sendable {

    /// Perceptual lightness, nominally `0...1`.
    public var lightness: Double

    /// Chroma, `0...~0.4` in practice but formally unbounded.
    public var chroma: Double

    /// Hue in degrees, always normalised to `0..<360` — on construction AND on
    /// assignment. Backed by private storage so the invariant cannot be bypassed.
    public var hue: Double {
        get { storedHue }
        set { storedHue = Self.wrapHue(newValue) }
    }

    private var storedHue: Double

    /// Alpha, `0...1`.
    public var alpha: Double

    /// Below this chroma a colour's hue carries no information and is treated as
    /// powerless during interpolation (CSS Color 4). Derived, never stored as
    /// `Optional` — see ARCHITECTURE.md §4.1.
    public static let powerlessChromaThreshold: Double = 1e-4

    public init(lightness: Double, chroma: Double, hue: Double, alpha: Double = 1) {
        self.lightness = lightness
        self.chroma = chroma
        self.storedHue = Self.wrapHue(hue)
        self.alpha = alpha
    }

    /// True when chroma is low enough that hue is numerically meaningless.
    ///
    /// This is the guard against defect `B2`: `.white` carries a garbage hue of
    /// 89.9 degrees, and interpolating it as if it were real produces a green cast.
    public var isPowerless: Bool {
        chroma < Self.powerlessChromaThreshold
    }

    /// Normalises any finite degree value into `0..<360`.
    static func wrapHue(_ degrees: Double) -> Double {
        guard degrees.isFinite else { return 0 }
        let r = degrees.truncatingRemainder(dividingBy: 360)
        return r < 0 ? r + 360 : r
    }
}
