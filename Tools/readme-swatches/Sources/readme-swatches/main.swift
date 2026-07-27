// Generates the README's eager-vs-late comparison SVG. Every colour is
// computed through OklchCore's real pipeline — nothing is hand-picked RGB.
// Deterministic: byte-identical on every run, so drift shows up in git.
//
// Two static images, so the README can set each argument up in prose:
//  1. contrast-solve.svg — one hard-coded foreground (correctly solved
//     ONCE, for the light surface) reused across four backdrops, versus one
//     `.contrasting` declaration solved per backdrop at resolve time. Both
//     columns print measured WCAG ratios. Authored variants are deliberately
//     NOT the subject: a diligent eager author can hard-code per-context
//     values (asset catalogs have the slots); what eager code cannot do is
//     solve against a backdrop it doesn't know yet — and for backdrops
//     spanning light, dark and a mid-tone, NO single value passes 4.5:1
//     everywhere (asserted below, and pinned by DocExampleTests).
//  2. gamut-ramp.svg — chroma ramps at one declared hue (see rampHue below)
//     plus a rendered-hue line graph: the clipped line visibly drifts away
//     from the declared hue, the mapped line holds it.
import Foundation
import OklchCore

// MARK: - The demo colours (mirror README "The difference, measured")

let base = Oklch(lightness: 0.55, chroma: 0.18, hue: 250)

// Backdrops the solver runs against — computed like everything else.
let lightSurface = Oklch(lightness: 0.985, chroma: 0.002, hue: 250)
let midPanel = Oklch(lightness: 0.62, chroma: 0.06, hue: 250)
let darkSurface = Oklch(lightness: 0.18, chroma: 0.01, hue: 250)

// The solve family the README's snippet declares.
let solveHue = 250.0
let solveChroma = 0.1
let solveTarget = ContrastTarget.wcag(4.5)

func solved(against backdrop: Oklch) -> (colour: Oklch, resolution: ContrastResolution) {
    solveContrast(target: solveTarget, hue: solveHue, chroma: solveChroma,
                  against: gamutMap(backdrop, to: .sRGB), in: .sRGB)
}

/// The best a single hard-coded value can be: correctly solved, once,
/// against the light surface — then reused everywhere.
let fixedForeground = solved(against: lightSurface).colour

// The ramp: rising chroma at one declared hue, put through each strategy.
// A lone clipped swatch looks MORE saturated than a mapped one (clip lands on
// the gamut boundary — the most saturated displayable point), which reads as
// if clipping won; clipping's real failure is unfaithfulness along a ramp
// (defect B5). Hue 210 at L=0.5 was chosen by measured sweep as the most
// legible case: the clipped ramp bends 210° toward ~250° (sky blue turns
// violet) and lightens 0.50 -> 0.60, while the mapped ramp holds ~213°.
let rampL = 0.5
let rampHue = 210.0
let rampChroma = stride(from: 0.0, through: 0.40, by: 0.04).map { $0 }
func rampChip(_ chroma: Double) -> Oklch {
    Oklch(lightness: rampL, chroma: chroma, hue: rampHue)
}

// MARK: - Colour helpers

func hex(_ rgb: RGB) -> String {
    func channel(_ v: Double) -> Int { Int((min(max(v, 0), 1) * 255).rounded()) }
    return String(format: "#%02X%02X%02X",
                  channel(rgb.red), channel(rgb.green), channel(rgb.blue))
}

/// The late path: CSS Color 4 gamut map, then convert — resolve(in:)'s maths.
func late(_ colour: Oklch) -> RGB { oklchToRGB(gamutMap(colour, to: .sRGB), in: .sRGB) }

/// The eager path for out-of-gamut chroma: convert, then hard-clip each
/// channel — defect B5's behaviour, shipped by the surveyed packages.
func eagerClip(_ colour: Oklch) -> RGB {
    let raw = oklchToRGB(colour, in: .sRGB)
    return RGB(red: min(max(raw.red, 0), 1),
               green: min(max(raw.green, 0), 1),
               blue: min(max(raw.blue, 0), 1),
               alpha: raw.alpha)
}

func contrast(_ text: Oklch, on surface: Oklch) -> Double {
    wcagContrast(gamutMap(text, to: .sRGB), gamutMap(surface, to: .sRGB), in: .sRGB)
}

// Premise checks — the same ones DocExampleTests pins.
precondition(!oklchToRGB(base, in: .sRGB).isInGamut(), "base must exceed sRGB")
precondition(oklchToRGB(base, in: .displayP3).isInGamut(), "base must fit P3")
for (name, v) in [("lightSurface", lightSurface), ("midPanel", midPanel),
                  ("darkSurface", darkSurface)] {
    precondition(oklchToRGB(v, in: .sRGB).isInGamut(), "\(name) must be in sRGB")
}
// The demo's central claim, proven not asserted: at this hue and chroma,
// NO single lightness passes 4.5:1 on all four backdrops.
let allBackdrops = [lightSurface, midPanel, darkSurface, base]
let noSingleValuePasses = !stride(from: 0.0, through: 1.0, by: 0.002).contains { l in
    let candidate = gamutMap(Oklch(lightness: l, chroma: solveChroma, hue: solveHue), to: .sRGB)
    return allBackdrops.allSatisfy { backdrop in
        wcagContrast(candidate, gamutMap(backdrop, to: .sRGB), in: .sRGB) >= 4.5
    }
}
precondition(noSingleValuePasses, "a single value passes every backdrop — the demo's claim is false")
// The ramp's premise: visible hue drift under clip, hue held under map.
let lastChip = rampChip(rampChroma.last!)
let clipEndHue = rgbToOklch(eagerClip(lastChip), in: .sRGB).hue
let mapEndHue = rgbToOklch(late(lastChip), in: .sRGB).hue
precondition(abs(clipEndHue - rampHue) > 30, "clip hue drift no longer visible")
precondition(abs(mapEndHue - rampHue) < 5, "map no longer holds the declared hue")

// MARK: - SVG assembly

// Labels use a mid-grey legible on both GitHub themes; sample text sits on
// its own computed surface, where contrast is measured, not assumed.
let canvasText = "#848D97"

struct Row {
    var label: String
    var backdrop: Oklch
}

let rows = [
    Row(label: "ON THE LIGHT SURFACE", backdrop: lightSurface),
    Row(label: "ON A MID-TONE PANEL", backdrop: midPanel),
    Row(label: "ON THE DARK SURFACE", backdrop: darkSurface),
    Row(label: "ON THE BRAND COLOUR", backdrop: base),
]

/// Label/value colour that reads on the row's backdrop.
func labelOn(_ backdrop: Oklch) -> String { backdrop.lightness > 0.6 ? "#57606A" : "#C9D1D9" }

func card(_ row: Row, foreground: Oklch, value: String, x: Int, y: Int) -> String {
    """
      <rect x="\(x)" y="\(y)" width="340" height="70" rx="10" fill="\(hex(late(row.backdrop)))" \
    stroke="\(canvasText)" stroke-opacity="0.4"/>
      <text x="\(x + 16)" y="\(y + 22)" font-size="11" font-weight="600" \
    fill="\(labelOn(row.backdrop))">\(row.label)</text>
      <text x="\(x + 16)" y="\(y + 44)" font-size="17" \
    fill="\(hex(late(foreground)))">The quick brown fox — Aa</text>
      <text x="\(x + 16)" y="\(y + 60)" font-size="10" font-family="monospace" \
    fill="\(labelOn(row.backdrop))">\(value)</text>
    """
}

func panel(title: String, x: Int, hardCoded: Bool) -> String {
    var out = """
      <text x="\(x)" y="18" font-size="13" font-weight="700" fill="\(canvasText)">\(title)</text>
    """
    for (i, row) in rows.enumerated() {
        let foreground = hardCoded ? fixedForeground : solved(against: row.backdrop).colour
        let ratio = contrast(foreground, on: row.backdrop)
        let mark = ratio >= 4.5 ? "PASS" : "FAIL"
        let value = hardCoded
            ? String(format: "%@ — %.1f:1 %@", i == 0 ? "solved for this surface" : "reused",
                     ratio, mark)
            : String(format: "solved L=%.2f — %.1f:1 %@", foreground.lightness, ratio, mark)
        out += "\n" + card(row, foreground: foreground, value: value, x: x, y: 32 + i * 82)
    }
    return out
}

func rampCard(label: String, value: String, strategy: (Oklch) -> RGB,
              x: Int, y: Int) -> String {
    var out = """
      <text x="\(x + 2)" y="\(y + 14)" font-size="11" font-weight="600" \
    fill="\(canvasText)">\(label)</text>
    """
    for (i, chroma) in rampChroma.enumerated() {
        out += """

      <rect x="\(x + 2 + i * 31)" y="\(y + 22)" width="29" height="28" rx="4" \
    fill="\(hex(strategy(rampChip(chroma))))"/>
    """
    }
    out += """

      <text x="\(x + 2)" y="\(y + 64)" font-size="10" font-family="monospace" \
    fill="\(canvasText)">\(value)</text>
    """
    return out
}

/// Rendered hue along the ramp, as lines: the clipped line drifts away from
/// the declared hue, the mapped line stays on it.
func hueGraph(x: Int, y: Int, w: Int, h: Int) -> String {
    let plotX = x + 44, plotW = w - 180
    let plotY = y + 24, plotH = h - 44
    let hueMin = 200.0, hueMax = 260.0

    func px(_ chroma: Double) -> Double { Double(plotX) + chroma / 0.40 * Double(plotW) }
    func py(_ hue: Double) -> Double {
        Double(plotY) + (hueMax - hue) / (hueMax - hueMin) * Double(plotH)
    }
    func points(_ strategy: (Oklch) -> RGB) -> String {
        rampChroma.dropFirst().map { c in
            let hue = rgbToOklch(strategy(rampChip(c)), in: .sRGB).hue
            return String(format: "%.1f,%.1f", px(c), py(hue))
        }.joined(separator: " ")
    }

    var out = """
      <text x="\(x)" y="\(y + 6)" font-size="11" font-weight="600" fill="\(canvasText)">\
    RENDERED HUE ALONG THE RAMP — declared \(Int(rampHue))°</text>
    """
    for tick in [200, 220, 240, 260] {
        out += """

      <line x1="\(plotX)" y1="\(py(Double(tick)))" x2="\(plotX + plotW)" \
    y2="\(py(Double(tick)))" stroke="\(canvasText)" stroke-opacity="0.25" \
    \(tick == Int(rampHue + 10) ? "" : "stroke-dasharray=\"2,3\" ")stroke-width="1"/>
      <text x="\(x)" y="\(py(Double(tick)) + 4)" font-size="10" \
    font-family="monospace" fill="\(canvasText)">\(tick)°</text>
    """
    }
    out += """

      <polyline fill="none" stroke="#E8590C" stroke-width="2.5" \
    stroke-linejoin="round" points="\(points(eagerClip))"/>
      <polyline fill="none" stroke="#0969DA" stroke-width="2.5" \
    stroke-linejoin="round" points="\(points(late))"/>
      <text x="\(plotX + plotW + 10)" y="\(py(clipEndHue) + 4)" font-size="11" \
    font-family="monospace" fill="#E8590C">hard-clip → \(Int(clipEndHue.rounded()))°</text>
      <text x="\(plotX + plotW + 10)" y="\(py(mapEndHue) + 4)" font-size="11" \
    font-family="monospace" fill="#0969DA">gamut-map → \(Int(mapEndHue.rounded()))°</text>
      <text x="\(plotX)" y="\(y + h - 2)" font-size="10" font-family="monospace" \
    fill="\(canvasText)">declared chroma 0 → 0.40</text>
    """
    return out
}

/// Image 1: the contrast-solve demo — one hard-coded value reused across
/// four backdrops vs one declaration solved per backdrop.
func contrastSvg() -> String {
    let height = 32 + 4 * 82 + 8
    return """
    <svg xmlns="http://www.w3.org/2000/svg" width="760" height="\(height)" \
    viewBox="0 0 760 \(height)" font-family="-apple-system, 'Segoe UI', sans-serif">
    \(panel(title: "HARD-CODED — one value, reused", x: 10, hardCoded: true))
    \(panel(title: "LATE — contrasting(.wcag(4.5)), solved per backdrop", x: 410, hardCoded: false))
    </svg>
    """
}

/// Image 2: the gamut demo — chroma ramps under each strategy, and the
/// rendered-hue graph. The README's prose explains the negative-red cause.
func gamutSvg() -> String {
    let rampY = 8
    let graphY = rampY + 84
    let height = graphY + 150
    return """
    <svg xmlns="http://www.w3.org/2000/svg" width="760" height="\(height)" \
    viewBox="0 0 760 \(height)" font-family="-apple-system, 'Segoe UI', sans-serif">
    \(rampCard(label: "CHROMA RAMP, DECLARED HUE \(Int(rampHue))° — hard-clipped",
               value: "hue drifts \(Int(rampHue))° → \(Int(clipEndHue.rounded()))°",
               strategy: eagerClip, x: 10, y: rampY))
    \(rampCard(label: "CHROMA RAMP, DECLARED HUE \(Int(rampHue))° — gamut-mapped",
               value: "hue held near \(Int(mapEndHue.rounded()))°",
               strategy: late, x: 410, y: rampY))
    \(hueGraph(x: 10, y: graphY, w: 740, h: 140))
    </svg>
    """
}

// MARK: - Write (repo-root-relative, resolved from this source file)

let repoRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()  // main.swift -> readme-swatches (sources)
    .deletingLastPathComponent()  // Sources
    .deletingLastPathComponent()  // readme-swatches (package)
    .deletingLastPathComponent()  // Tools
    .deletingLastPathComponent()  // repo root
let assets = repoRoot.appendingPathComponent("docs/assets")
try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)

for (name, content) in [("contrast-solve.svg", contrastSvg()),
                        ("gamut-ramp.svg", gamutSvg())] {
    let url = assets.appendingPathComponent(name)
    try content.write(to: url, atomically: true, encoding: .utf8)
    print("wrote \(url.path)")
}
