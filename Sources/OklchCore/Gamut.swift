#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#else
#error("OklchCore requires Darwin, Glibc, or Musl")
#endif

/// A 3x3 matrix in row-major order.
public struct Matrix3: Hashable, Sendable {
    public let m: (Double, Double, Double,
                   Double, Double, Double,
                   Double, Double, Double)

    public init(_ a: Double, _ b: Double, _ c: Double,
                _ d: Double, _ e: Double, _ f: Double,
                _ g: Double, _ h: Double, _ i: Double) {
        m = (a, b, c, d, e, f, g, h, i)
    }

    public func apply(_ v: (Double, Double, Double)) -> (Double, Double, Double) {
        (m.0 * v.0 + m.1 * v.1 + m.2 * v.2,
         m.3 * v.0 + m.4 * v.1 + m.5 * v.2,
         m.6 * v.0 + m.7 * v.1 + m.8 * v.2)
    }

    public static func == (l: Matrix3, r: Matrix3) -> Bool {
        l.m.0 == r.m.0 && l.m.1 == r.m.1 && l.m.2 == r.m.2 &&
        l.m.3 == r.m.3 && l.m.4 == r.m.4 && l.m.5 == r.m.5 &&
        l.m.6 == r.m.6 && l.m.7 == r.m.7 && l.m.8 == r.m.8
    }
    public func hash(into h: inout Hasher) {
        h.combine(m.0); h.combine(m.1); h.combine(m.2)
        h.combine(m.3); h.combine(m.4); h.combine(m.5)
        h.combine(m.6); h.combine(m.7); h.combine(m.8)
    }
}

/// An RGB colour in a specific gamut. Components are **encoded** (transfer curve
/// applied) and may fall outside `0...1` when the colour is out of gamut.
public struct RGB: Hashable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red; self.green = green; self.blue = blue; self.alpha = alpha
    }

    /// True when every component lies within `0...1`, within `epsilon`.
    public func isInGamut(epsilon: Double = 1e-9) -> Bool {
        let lo = -epsilon, hi = 1 + epsilon
        return red >= lo && red <= hi
            && green >= lo && green <= hi
            && blue >= lo && blue <= hi
    }
}

/// A destination RGB gamut, expressed as its matrix pair to and from XYZ D65.
///
/// sRGB and Display P3 share the sRGB transfer curve, so a gamut is exactly a
/// matrix pair (ARCHITECTURE.md §4.1). Rec.2020 is deliberately excluded: no Apple display
/// requires it and it would introduce a second transfer function.
public struct Gamut: Hashable, Sendable {
    public let name: String
    public let toXYZ: Matrix3
    public let fromXYZ: Matrix3

    public init(name: String, toXYZ: Matrix3, fromXYZ: Matrix3) {
        self.name = name; self.toXYZ = toXYZ; self.fromXYZ = fromXYZ
    }

    public static let sRGB = Gamut(
        name: "sRGB",
        toXYZ: Matrix3(
            0.4123907992659595,   0.35758433938387796, 0.1804807884018343,
            0.21263900587151036,  0.7151686787677559,  0.07219231536073371,
            0.019330818715591598, 0.11919477979462599, 0.9505321522496606),
        fromXYZ: Matrix3(
             3.2409699419045226,  -1.5373831775700939, -0.4986107602930034,
            -0.9692436362808796,   1.8759675015077202,  0.04155505740717559,
             0.05563007969699366, -0.20397695888897652, 1.0569715142428786))

    public static let displayP3 = Gamut(
        name: "displayP3",
        toXYZ: Matrix3(
            0.4865709486482162,  0.26566769316909306, 0.1982172852343625,
            0.2289745640697488,  0.6917385218365064,  0.079286914093745,
            0.0,                 0.04511338185890264, 1.043944368900976),
        fromXYZ: Matrix3(
             2.493496911941425,   -0.9313836179191239, -0.40271078445071684,
            -0.8294889695615747,   1.7626640603183463,  0.023624685841943577,
             0.03584583024378447, -0.07617238926804182, 0.9568845240076872))

    /// The sRGB transfer curve, linear -> encoded.
    ///
    /// Sign-symmetric by construction. Defect `B3` (nikstar/swift-oklch) is
    /// exactly the omission of this symmetry: negative linear values took the
    /// `12.92 * c` branch and every out-of-gamut colour was mis-encoded.
    public static func encode(_ linear: Double) -> Double {
        let sign: Double = linear < 0 ? -1 : 1
        let a = abs(linear)
        return a <= 0.0031308
            ? sign * (12.92 * a)
            : sign * (1.055 * pow(a, 1.0 / 2.4) - 0.055)
    }

    /// The sRGB transfer curve, encoded -> linear. Sign-symmetric.
    public static func decode(_ encoded: Double) -> Double {
        let sign: Double = encoded < 0 ? -1 : 1
        let a = abs(encoded)
        return a <= 0.04045
            ? sign * (a / 12.92)
            : sign * pow((a + 0.055) / 1.055, 2.4)
    }
}
