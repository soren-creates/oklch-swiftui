// OKLab maths from Björn Ottosson's public-domain reference implementation,
// https://bottosson.github.io/posts/oklab/ — vendored with attribution per
// ARCHITECTURE.md §2. The LMS<->XYZ matrices are Ottosson's; the RGB<->XYZ matrices
// live on `Gamut`.
//
// Every conversion routes OKLab <-> LMS <-> XYZ <-> linear RGB <-> encoded RGB,
// so adding a gamut means adding a matrix pair and nothing else.

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#else
#error("OklchCore requires Darwin, Glibc, or Musl")
#endif

/// Non-linear LMS (the cube-rooted cone responses) -> OKLab.
let lmsToOklab = Matrix3(
    0.2104542683093140,  0.7936177747023054, -0.0040720430116193,
    1.9779985324311684, -2.4285922420485799,  0.4505937096174110,
    0.0259040424655478,  0.7827717124575296, -0.8086757549230774)

/// Inverse of `lmsToOklab`. Full precision from colorjs.io's `LabtoLMS`;
/// the widely-quoted 10-digit rounding of these values caps the pair's
/// inverse residual at ~7e-11 and is not good enough for our 1e-12 gate.
let oklabToLms = Matrix3(
    1.0000000000000000,  0.3963377773761749,  0.2158037573099136,
    1.0000000000000000, -0.1055613458156586, -0.0638541728258133,
    1.0000000000000000, -0.0894841775298119, -1.2914855480194092)

/// Linear LMS -> XYZ D65.
let lmsToXYZ = Matrix3(
     1.2268798758459243, -0.5578149944602171,  0.2813910456659647,
    -0.0405757452148008, 1.1122868032803170, -0.0717110580655164,
    -0.0763729366746601, -0.4214933324022432,  1.5869240198367816)

/// XYZ D65 -> linear LMS.
let xyzToLMS = Matrix3(
    0.8190224379967030,  0.3619062600528904, -0.1288737815209879,
    0.0329836539323885,  0.9292868615863434,  0.0361446663506424,
    0.0481771893596242,  0.2642395317527308,  0.6335478284694309)

/// Cube root that preserves sign, so out-of-gamut negatives survive intact.
@inline(__always)
func signedCbrt(_ x: Double) -> Double {
    x < 0 ? -pow(-x, 1.0 / 3.0) : pow(x, 1.0 / 3.0)
}

// MARK: - OKLab (rectangular)

/// OKLab in rectangular form. Internal: the public surface is OKLCH.
struct Oklab {
    var lightness: Double
    var a: Double
    var b: Double
}

func oklchToOklab(_ c: Oklch) -> Oklab {
    let radians = c.hue * .pi / 180
    return Oklab(lightness: c.lightness,
                 a: c.chroma * cos(radians),
                 b: c.chroma * sin(radians))
}

func oklabToOklch(_ lab: Oklab, alpha: Double = 1) -> Oklch {
    let chroma = (lab.a * lab.a + lab.b * lab.b).squareRoot()
    // Hue is meaningless below the powerless threshold; report 0 rather than
    // the numerical noise atan2 returns near the achromatic axis. This is the
    // guard against defect B2.
    let hue = chroma < Oklch.powerlessChromaThreshold
        ? 0
        : atan2(lab.b, lab.a) * 180 / .pi
    return Oklch(lightness: lab.lightness, chroma: chroma, hue: hue, alpha: alpha)
}

// MARK: - Public conversions

/// OKLCH -> encoded RGB in `gamut`. Components may fall outside `0...1`
/// when the colour is out of that gamut; that is intentional and is what
/// gamut mapping later consumes.
public func oklchToRGB(_ c: Oklch, in gamut: Gamut) -> RGB {
    let lab = oklchToOklab(c)
    let lms_ = oklabToLms.apply((lab.lightness, lab.a, lab.b))
    let lms = (lms_.0 * lms_.0 * lms_.0,
               lms_.1 * lms_.1 * lms_.1,
               lms_.2 * lms_.2 * lms_.2)
    let xyz = lmsToXYZ.apply(lms)
    let linear = gamut.fromXYZ.apply(xyz)
    return RGB(red: Gamut.encode(linear.0),
               green: Gamut.encode(linear.1),
               blue: Gamut.encode(linear.2),
               alpha: c.alpha)
}

/// Encoded RGB in `gamut` -> OKLCH.
public func rgbToOklch(_ rgb: RGB, in gamut: Gamut) -> Oklch {
    let linear = (Gamut.decode(rgb.red),
                  Gamut.decode(rgb.green),
                  Gamut.decode(rgb.blue))
    let xyz = gamut.toXYZ.apply(linear)
    let lms = xyzToLMS.apply(xyz)
    let lms_ = (signedCbrt(lms.0), signedCbrt(lms.1), signedCbrt(lms.2))
    let labTuple = lmsToOklab.apply(lms_)
    return oklabToOklch(Oklab(lightness: labTuple.0, a: labTuple.1, b: labTuple.2),
                        alpha: rgb.alpha)
}
