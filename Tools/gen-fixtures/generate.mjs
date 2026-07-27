// Tools/gen-fixtures/generate.mjs
//
// Generates Color.js reference fixtures for OklchCore (ARCHITECTURE.md §5.1).
//
// THE RULE, lifted from a prior benchmark-authoring process's fixture generator:
//
//   The generator states what each fixture SHOULD be, then asks Color.js.
//   On disagreement it writes NOTHING and reports. That is a STOP-and-report
//   signal, never a silent adjustment of the oracle or the pins.
//
// Without this rule the generator degenerates into "whatever Color.js says is
// correct", and a misreading of the spec would be silently enshrined as the
// reference. This is the difference between a fixture suite and a tautology.

import Color from "colorjs.io";
import { writeFileSync, readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const HERE = dirname(fileURLToPath(import.meta.url));
const REPO = join(HERE, "..", "..");
const OUT = join(REPO, "Fixtures", "colorjs", "conversions.json");

const failures = [];

/**
 * Records a disagreement between what this script intends and what the oracle
 * reports. Never throws immediately: we want the FULL list of disagreements in
 * one run, not just the first.
 */
function assertIntent(id, what, expected, actual, tolerance = 1e-4) {
    const ok = Array.isArray(expected)
        ? expected.length === actual.length &&
          expected.every((e, i) => Math.abs(e - actual[i]) <= tolerance)
        : Math.abs(expected - actual) <= tolerance;
    if (!ok) {
        failures.push({ id, what, expected, actual, tolerance });
    }
    return ok;
}

/** Colours whose sRGB values this script knows independently of Color.js. */
const KNOWN_SRGB = [
    { id: "srgb-corner-black",   css: "rgb(0 0 0)",       srgb: [0, 0, 0] },
    { id: "srgb-corner-white",   css: "rgb(255 255 255)", srgb: [1, 1, 1] },
    { id: "srgb-corner-red",     css: "rgb(255 0 0)",     srgb: [1, 0, 0] },
    { id: "srgb-corner-green",   css: "rgb(0 255 0)",     srgb: [0, 1, 0] },
    { id: "srgb-corner-blue",    css: "rgb(0 0 255)",     srgb: [0, 0, 1] },
    { id: "srgb-corner-cyan",    css: "rgb(0 255 255)",   srgb: [0, 1, 1] },
    { id: "srgb-corner-magenta", css: "rgb(255 0 255)",   srgb: [1, 0, 1] },
    { id: "srgb-corner-yellow",  css: "rgb(255 255 0)",   srgb: [1, 1, 0] },
    { id: "srgb-mid-grey",       css: "rgb(128 128 128)", srgb: [128 / 255, 128 / 255, 128 / 255] },
];

const cases = [];

// --- Group 1: sRGB corners, round-tripped through OKLCH -------------------
//
// INTENT: converting a known sRGB colour to OKLCH and back must return the
// same sRGB colour. If it does not, either Color.js or our understanding of
// the round trip is wrong, and we must not write fixtures either way.
for (const { id, css, srgb } of KNOWN_SRGB) {
    const c = new Color(css);
    const backToSrgb = c.to("oklch").to("srgb").coords;

    assertIntent(id, "srgb round-trip through oklch", srgb, backToSrgb, 1e-9);

    cases.push({
        id,
        oklch: c.to("oklch").coords.map(nz),
        srgb: c.to("srgb").coords,
        p3: c.to("p3").coords,
        in_srgb_gamut: c.inGamut("srgb"),
        in_p3_gamut: c.inGamut("p3"),
    });
}

// --- Group 2: achromatic edges -------------------------------------------
//
// INTENT: a pure grey has chroma 0. Its hue is meaningless, and Color.js may
// report NaN. We assert chroma is 0 and normalise hue to 0 ourselves rather
// than letting NaN leak into a fixture.
for (let i = 0; i <= 10; i++) {
    const v = i / 10;
    const c = new Color("srgb", [v, v, v]);
    const [L, C] = c.to("oklch").coords;

    assertIntent(`achromatic-${i}`, "grey has zero chroma", 0, C, 1e-7);

    cases.push({
        id: `achromatic-${i}`,
        oklch: [L, C, 0],
        srgb: [v, v, v],
        p3: c.to("p3").coords,
        in_srgb_gamut: true,
        in_p3_gamut: true,
    });
}

// --- Group 3: out-of-sRGB OKLCH ------------------------------------------
//
// INTENT: these are chosen to be OUTSIDE sRGB. If Color.js reports one of
// them as in-gamut, our chosen chroma is too low and the fixture would not
// exercise gamut mapping at all — a silently useless test.
//
// CORRECTION (found by running this generator, 2026-07-25): the original
// pins [0.45, 0.31, 264.1] (blue) and [0.70, 0.32, 328.4] (magenta) tripped
// assertIntent — Color.js reported both as IN gamut. Scanning chroma at
// fixed L/H showed why: OKLCH->sRGB is not monotonic in chroma, so the blue
// hue has a narrow in-gamut "island" right at C=0.31 (C=0.30 and C=0.32 are
// both out), and the magenta hue simply hadn't crossed the boundary yet at
// C=0.32 (it crosses between 0.32 and 0.33). Neither is a Color.js bug or a
// misunderstanding of toGamut/inGamut; the pins themselves were too close to
// (or inside) the boundary. Fixed by raising chroma to 0.34 / 0.36, each
// verified out-of-gamut with a fine (0.001) chroma scan on both sides so
// this fixture isn't sitting on another accidental boundary.
const OUT_OF_SRGB = [
    { id: "oog-red",     oklch: [0.70, 0.30,  29.2] },
    { id: "oog-green",   oklch: [0.87, 0.30, 142.5] },
    { id: "oog-blue",    oklch: [0.45, 0.34, 264.1] },
    { id: "oog-magenta", oklch: [0.70, 0.36, 328.4] },
];
for (const { id, oklch } of OUT_OF_SRGB) {
    const c = new Color("oklch", oklch);
    const inSrgb = c.inGamut("srgb");

    if (inSrgb !== false) {
        failures.push({
            id, what: "expected OUT of sRGB gamut", expected: false, actual: inSrgb,
        });
    }

    // toGamut returns coords in the colour's OWN space (oklch), verified 2026-07-25.
    const mappedCss = c.clone().toGamut({ space: "srgb", method: "css" });
    const mappedClip = c.clone().toGamut({ space: "srgb", method: "clip" });

    cases.push({
        id,
        oklch,
        srgb: c.to("srgb").coords,              // may be out of [0,1]; that is the point
        p3: c.to("p3").coords,
        in_srgb_gamut: inSrgb,
        in_p3_gamut: c.inGamut("p3"),
        mapped_css_srgb: mappedCss.to("srgb").coords,
        mapped_css_oklch: mappedCss.to("oklch").coords.map(nz),
        mapped_clip_srgb: mappedClip.to("srgb").coords,
    });
}

// --- Group 4: hue-wraparound pairs, for defect B1 ------------------------
//
// INTENT: the shortest arc from 28.5 to 328.4 degrees is 60 degrees going
// DOWNWARD through 0, not 300 degrees going upward. We assert our own arc
// arithmetic here; Color.js is not consulted, because this is our rule to
// get right.
const HUE_PAIRS = [
    { id: "wrap-red-magenta", from: 28.5, to: 328.4, shortestArc: -60.1 },
    { id: "wrap-magenta-red", from: 328.4, to: 28.5, shortestArc: 60.1 },
    { id: "wrap-none",        from: 30.0, to: 90.0,  shortestArc: 60.0 },
    { id: "wrap-antipodal",   from: 0.0,  to: 180.0, shortestArc: 180.0 },
];
const hueCases = [];
for (const { id, from, to, shortestArc } of HUE_PAIRS) {
    let d = (to - from) % 360;
    if (d > 180) d -= 360;
    if (d < -180) d += 360;
    assertIntent(id, "shortest hue arc", shortestArc, d, 1e-9);
    hueCases.push({ id, from, to, shortest_arc: d });
}

// --- Group 5: contrast pairs ---------------------------------------------
//
// INTENT: white on black is the maximum-contrast pair. WCAG 2.1 defines it as
// exactly 21. If Color.js disagrees, our understanding of the API is wrong.
//
// The out-of-gamut pair (a later revision) reuses `oog-green`'s exact OKLCH triple
// from Group 3, which already established it is out of sRGB gamut. Without a
// case like this, the two hardest-won correctness properties in this
// generator's Swift counterpart — sign-preserving luminance linearization,
// and the unclamped WCAG luminance's `1...21` violation — have zero fixture
// coverage, because every other pair here is comfortably in-gamut.
const CONTRAST_PAIRS = [
    { id: "contrast-white-on-black", fg: "white", bg: "black" },
    { id: "contrast-black-on-white", fg: "black", bg: "white" },
    { id: "contrast-grey-on-white",  fg: "rgb(119 119 119)", bg: "white" },
    { id: "contrast-blue-on-white",  fg: "rgb(0 0 255)", bg: "white" },
    { id: "contrast-same",           fg: "rgb(128 128 128)", bg: "rgb(128 128 128)" },
    { id: "contrast-oog-green-on-white", fg: "oklch(0.87 0.30 142.5)", bg: "white" },
];

const contrastCases = [];
for (const { id, fg, bg } of CONTRAST_PAIRS) {
    const f = new Color(fg), b = new Color(bg);
    const wcag = Color.contrast(b, f, "WCAG21");
    const apca = Color.contrast(b, f, "APCA");

    if (id === "contrast-white-on-black") {
        assertIntent(id, "WCAG21 white-on-black is exactly 21", 21, wcag, 1e-9);
    }
    if (id === "contrast-same") {
        assertIntent(id, "identical colours have WCAG contrast 1", 1, wcag, 1e-9);
        assertIntent(id, "identical colours have APCA contrast 0", 0, apca, 1e-9);
    }
    if (id === "contrast-oog-green-on-white") {
        // INTENT: this is the same OKLCH triple as Group 3's `oog-green`,
        // already established out of sRGB gamut. If Color.js now reports it
        // as in-gamut, either that fact changed underneath us or this case
        // was mistyped — either way, do not silently record a fixture whose
        // premise (exercising out-of-gamut luminance) does not hold.
        const inSrgb = f.inGamut("srgb");
        if (inSrgb !== false) {
            failures.push({
                id, what: "expected OUT of sRGB gamut (reused from oog-green)",
                expected: false, actual: inSrgb,
            });
        }
    }

    contrastCases.push({
        id,
        fg_oklch: f.to("oklch").coords.map(nz),
        bg_oklch: b.to("oklch").coords.map(nz),
        fg_srgb: f.to("srgb").coords,
        bg_srgb: b.to("srgb").coords,
        wcag21: wcag,
        apca: apca,
    });
}

// --- STOP-and-report ------------------------------------------------------
if (failures.length > 0) {
    console.error("INTENT DISAGREEMENT — nothing written.\n");
    for (const f of failures) {
        console.error(`  [${f.id}] ${f.what}`);
        console.error(`      intended: ${JSON.stringify(f.expected)}`);
        console.error(`      oracle:   ${JSON.stringify(f.actual)}`);
    }
    console.error(
        "\nThis is a STOP signal. Do NOT loosen the tolerance or edit the " +
        "expectation to match the oracle. Work out which side is wrong first."
    );
    process.exit(1);
}

/**
 * Normalises Color.js's powerless hue to 0 so fixtures stay valid JSON with a
 * consistent numeric type. Color.js 0.7.1 does not use one consistent sentinel
 * for "hue is meaningless here": achromatic corners produced by new Color(css)
 * (srgb-corner-black/white, srgb-mid-grey) come back as `null`, not `NaN`
 * (verified 2026-07-25 by inspecting c.to("oklch").coords directly). Handle
 * both so neither leaks into the fixture.
 */
function nz(x) { return (x === null || Number.isNaN(x)) ? 0 : x; }

const payload = {
    generator: {
        colorjs: JSON.parse(
            readFileSync(join(HERE, "node_modules", "colorjs.io", "package.json"))
        ).version,
        node: process.version,
        generated_from: "generate.mjs",
    },
    cases,
    hue_arcs: hueCases,
    contrast: contrastCases,
};

writeFileSync(OUT, JSON.stringify(payload, null, 2) + "\n");
console.log(`wrote ${OUT}`);
console.log(`  ${cases.length} conversion cases, ${hueCases.length} hue-arc cases, ${contrastCases.length} contrast cases`);
