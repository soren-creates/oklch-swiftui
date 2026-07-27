# Pins

Single source of truth for every tolerance and behavioural constant. A pin moves
only on recorded trial evidence — never for convenience, and never to make a
failing test pass.

| Pin | Value | Source | Evidence |
|---|---|---|---|
| `P-TOL-1` | Color.Resolved round-trip error <= `5.9604644775390625e-08` | probe A5 | `docs/evidence/2026-07-25-app-probes.json` |
| `P-TOL-2` | Render-path agreement <= `0.01` per channel (extended-linear sRGB) | probe A3 | `docs/evidence/2026-07-25-app-probes.json` |
| `P-ENV-1` | Environment traits require a hosted hierarchy; contrast requires an out-of-process toggle | probes A2b/A2c/A2d | `docs/evidence/2026-07-25-swiftui-probes.md` |
| `P-TOL-3` | OKLCH->RGB agreement with Color.js <= `1e-13` | OklchCore conversions | `Fixtures/colorjs/conversions.json` |
| `P-TOL-4` | CSS Color 4 gamut-map agreement with Color.js <= `1e-13` | OklchCore gamut mapping | `Fixtures/colorjs/conversions.json` |
| `P-TOL-5` | Contrast agreement with Color.js: WCAG <= `1e-14` (measured `3.552713678800501e-15`), APCA <= `1e-13` (measured `2.4868995751603507e-14`, 6-case fixture sweep) | OklchCore contrast | `Fixtures/colorjs/conversions.json` |
| `P-SEED-1` | Property-test LCG seed `20260725` | OklchCore property tests | `Tests/OklchCoreTests/PropertyTests.swift` |
| `P-TOL-6` | Post-map deltaEOK vs fixed-hue/lightness proxy <= `0.05` | OklchCore property tests | `Tests/OklchCoreTests/PropertyTests.swift` |
| `P-TOL-7` | In-gamut round-trip identity (OKLCH -> RGB -> OKLCH) error <= `3e-15` (measured `8.916478666520788e-16`) | OklchCore property tests | `Tests/OklchCoreTests/PropertyTests.swift` |
| `P-APCA-1` | APCA G-4g constants: normBG 0.56, normTXT 0.57, revTXT 0.62, revBG 0.65, blkThrs 0.022, blkClmp 1.414, loClip 0.1, deltaYmin 0.0005, scale 1.14, loOffset 0.027 | OklchCore contrast | `Tools/gen-fixtures/node_modules/colorjs.io/src/contrast/APCA.js` |
| `P-DIR-1` | `Direction.automatic` picks more headroom; ties break toward `darker` | OklchCore contrast solver | `Sources/OklchCore/ContrastSolver.swift` |
| `P-CHAR-1` | Light-mode Increase Contrast shift for the `CharacterizationTests` fixture style: worst channel (blue) `0.35134539008140564` | OklchUI characterization (`Tools/run-characterization.sh`) | run captured below |

## P-TOL-1 — SwiftUI precision floor

`Color.Resolved` stores components as `Float32`. This bounds the achievable
accuracy of any OKLCH -> Color -> OKLCH round trip regardless of our own maths
— but only on paths that actually touch `Color.Resolved`. `OklchCore` has
none: it is pure `Double` from `Oklch` through every conversion, gamut-map,
interpolation and contrast function. `P-TOL-1` is therefore the floor for any
tolerance on a path through `Color.Resolved` — the characterization tests and
the on-device harness, where this maths actually gets rendered through SwiftUI
— and it does NOT bound `OklchCore`'s own fixture agreement with Color.js,
which is pinned five to six orders of magnitude tighter against measured
oracle agreement: `P-TOL-3` and `P-TOL-4` at `1e-13`, `P-TOL-5` at
`1e-14`/`1e-13`.

Measured value: `5.9604644775390625e-08`, worst case at `v=0.015625` over a
65-point deterministic grid (`steps = 64`, no RNG, no wall clock).

This is exactly `2^-24`, the half-ULP rounding bound for `Float32` in `[0,1)`.
The agreement is the finding: SwiftUI imposes no quantisation beyond `Float32`
storage itself. Had the measured value exceeded `2^-24`, SwiftUI would have
been rounding more aggressively than its storage requires and OklchCore
tolerances would have had to widen to the measured number instead.

Measured on: Xcode 26.6, Swift 6.3.3, on BOTH installed runtimes with
identical results — iOS 26.5 Simulator (iPhone 17 Pro) and iOS 17.0
Simulator (iPhone 15 Pro), the floor declared in ARCHITECTURE.md §3.3.

Only `OklchUI` tests bind against this pin — `OklchCore`'s fixture and
property tests never touch `Color`/`Color.Resolved`. The exact literal
(`5.9604644775390625e-08`) is hoisted into one shared constant,
`Tests/OklchUITests/TestTolerances.swift`'s `resolvedFloat32Tolerance`, used
as the accuracy/tolerance by:

- `Tests/OklchUITests/ResolveTests.swift`'s `resolvedTolerance` (an alias for
  the shared constant), used by
  `testLightSchemeUsesBase`, `testDarkSchemeUsesDarkVariantWhenPresent` and
  `testDarkSchemeFallsBackToBaseWhenNoDarkVariant`. The first two compare
  `Color.resolve(in:)`'s actual `Float32` components against `OklchCore`'s
  predicted `Double` value; the third compares the light-scheme
  `Color.resolve(in:)` output against the dark-scheme output of the SAME
  style (no dark variant supplied, so both should fall back to `light`), and
  needs the identical `Float32` slack to avoid a false failure from
  quantisation alone.
- `Tests/OklchUITests/CharacterizationTests.swift`'s `tolerance` (also an
  alias for the shared constant), used by `differs(_:_:)` to decide whether
  two `Color.Resolved` readings (e.g. light vs dark scheme, sRGB vs Display
  P3) are the same colour or a real change — a sub-tolerance nudge must not
  register as "differs".

`Tools/run-characterization.sh`'s `rgb_differs` uses the identical literal
for the same reason, out-of-process. It is deliberately NOT unified with the
Swift constant above: a bash script cannot import Swift test code, and the
runner's "changed" verdict must use the same predicate as the suite's, or the
two could disagree about the same underlying delta.

## P-TOL-2 — render-path agreement

Display P3 pure green rendered through four SwiftUI paths and read back in
extended-linear sRGB. Measured values:

| Path | r | g | b |
|---|---|---|---|
| `solid_fill` | -0.2247314453125 | 1.0419921875 | -0.07861328125 |
| `foreground` | -0.2247314453125 | 1.0419921875 | -0.07861328125 |
| `gradient` | -0.2247314453125 | 1.0419921875 | -0.07861328125 |
| `canvas` | -0.22314453125 | 1.044921875 | -0.0791015625 |

Three paths are byte-identical. `canvas` diverges by at most `0.0029`, which is
why the pin sits at `0.01` rather than at zero — a pin of zero would fail on a
path that is in fact correct. The negative red channel is the finding: it is
unreachable in sRGB, so P3 demonstrably survives to the rendered buffer.

The forum-reported `LinearGradient` P3 defect (Apple Developer Forums 727506)
does **not** reproduce on either tested runtime.

Measured on: Xcode 26.6, Swift 6.3.3, on BOTH installed runtimes with
identical results — iOS 26.5 Simulator (iPhone 17 Pro) and iOS 17.0
Simulator (iPhone 15 Pro), the floor declared in ARCHITECTURE.md §3.3.

**Confirmed on hardware** (`docs/evidence/2026-07-26-ondevice-p3.json`: iPhone 14 (`iPhone14,7`),
iOS 26.6, Xcode 26.6, Swift 6.3.3). Every device value is bit-for-bit identical to its Simulator
counterpart on all four paths above; a new `oklch_style` path (exercising `OklchStyle` itself
rather than a raw `Color(.displayP3,…)` literal) matches `solid_fill` exactly; `canvas` shows the
identical `0.0029296875` (green channel, worst) deviation; and the device's own gradient-vs-solid
check reports `worst_delta: 0`, so forum 727506 does not reproduce on device either. The pin's
VALUE is unchanged at `0.01` — the device run confirms it rather than moves it, and the headroom
exists for `canvas`'s legitimate ~0.0029 deviation. Device table and full findings:
`docs/evidence/2026-07-26-ondevice-p3-findings.md`.

## P-TOL-3 — agreement with the Color.js oracle

Worst absolute per-channel error between `oklchToRGB` and Color.js 0.7.1 across
every committed fixture case.

Measured: `3.46947470752923e-14` (sRGB, at `srgb-corner-green`),
`2.3314683517128287e-15` (Display P3, at `srgb-corner-green`).

This bounds our conversion chain against an independent implementation. It is
NOT a claim about absolute correctness — Color.js could be wrong too, which is
why the generator asserts its own intent before trusting the oracle (ARCHITECTURE.md §5.1).

`conversionTolerance` was seeded at `1e-6` as a starting guess; the measured
agreement is roughly eight orders of magnitude tighter — consistent with the
full-precision matrix correction, which pinned the sRGB round-trip error at
`3.40e-14`. The pin was tightened to `1e-13`, about 2.9x the worst measured
value, giving headroom only for legitimate cross-platform `libm` differences
(this repo must also build and test on Linux) — not for slack. A pin left at
`1e-6` would not catch a regression of six-plus orders of magnitude.

Measured on: Swift 6.3.3, macOS. Node v26.4.0, colorjs.io 0.7.1.

## P-TOL-4 — gamut-mapping agreement with the Color.js oracle

Worst absolute per-channel error between `oklchToRGB(gamutMap(_, to: .sRGB,
using: .cssColor4), in: .sRGB)` and Color.js's `mapped_css_srgb` across every
fixture case that carries that field (the four `oog-*` out-of-gamut cases).

Measured: `2.8329560919360118e-14`, at `oog-green`.

This pin rests on only 4 fixture cases, all sRGB, all `.cssColor4` — there is
no P3 gamut-map oracle in the fixture set and no case exercising `.clip`.
Widening that coverage would need new fixture generation (see
`docs/survey.md`'s Known limitations).

This pin was expected to be **looser** than `P-TOL-3`'s `1e-13`: gamut mapping
is a search with an early-exit JND rule, so implementation step-order
differences could produce real, sub-JND divergence from Color.js. It measured
as tight as `P-TOL-3` instead, and is pinned to the same `1e-13`. Here is why.

The reference implementation this work started from returns, for `.cssColor4`, as
soon as it finds *any* out-of-gamut candidate whose clipped form is within one
JND (`deltaEOK < 0.02`) of that candidate. Measured against the fixtures, that
gave a worst-case error of `0.10632177866993311` at `oog-green` — five times
over one JND. That is a real algorithmic gap, not measurement noise:
the returned colour was legitimately in-gamut (chroma 0.290 at L=0.868, hue
142.5) but far from the true boundary (max chroma is 0.284 at the input's
lightness), because the search accepted the first JND-satisfying candidate
instead of continuing to narrow.

The CSS Color 4 spec's own pseudocode (§14.2.2, "Sample Pseudocode for the
Binary Search Gamut Mapping with Local MINDE",
<https://www.w3.org/TR/css-color-4/#binsearch>) contains a refinement step
that reference version had dropped: once a candidate's clip is within JND but
not within `epsilon` (`0.0001`) of the JND edge itself, the spec sets a
`min_inGamut = false` flag and keeps narrowing upward (`min = chroma`),
searching for the *largest* chroma whose clip is still within JND, rather
than returning on the first hit. `Sources/OklchCore/GamutMapping.swift`
implements this `min_inGamut` refinement loop verbatim from the spec text.
That fix alone took the `oog-green` error from `0.106` to `2.83e-14`: both
implementations now run the literal same deterministic algorithm (identical
epsilon, identical midpoint arithmetic) over conversion maths that already
agree to `P-TOL-3`'s precision, so there is no longer a structural reason for
the two to diverge above floating-point noise.

Measured on: Swift 6.3.3, macOS. Node v26.4.0, colorjs.io 0.7.1.

## P-ENV-1 — how environment inputs must be exercised

Two behavioural constants, both measured, both binding on §5.5
characterization tests:

1. **`ImageRenderer` does not carry environment traits.** With Increase Contrast
   enabled, UIKit reported `accessibilityContrast = high` while `resolve(in:)`
   under `ImageRenderer` reported `standard` in the same process on the same
   run. A hosted hierarchy (`UIHostingController` in `UIWindow`) reported
   `increased` correctly. Characterization tests must therefore render through a
   hosted hierarchy.

2. **`colorSchemeContrast` is not settable in-process.** It is a read-only
   `KeyPath`, not a `WritableKeyPath` (compile probe A2a). Varying it requires
   `xcrun simctl ui <device> increase_contrast enabled|disabled` with the suite
   run once per setting. `colorScheme` and `colorGamut` remain settable via
   `.environment` and do not need this treatment.

Measured on: Xcode 26.6, Swift 6.3.3, on BOTH installed runtimes with
identical results — iOS 26.5 Simulator (iPhone 17 Pro) and iOS 17.0
Simulator (iPhone 15 Pro), the floor declared in ARCHITECTURE.md §3.3.

## P-SEED-1 — property-test LCG seed

`Tests/OklchCoreTests/PropertyTests.swift` (ARCHITECTURE.md §5.2, tier 2) samples its
sweeps from a linear congruential generator seeded with the literal
`20260725`, defined once as `PropertyTests.seed` and reused as the inline
seed in every property test so the constant and the seeds cannot drift out
of agreement.

The generator (`state = state &* 1664525 &+ 1013904223`, reading out
`state >> 11`) uses the Numerical Recipes multiplier/increment pair over a
64-bit state. It satisfies the Hull-Dobell theorem for full period: modulus
`2^64`, increment `1013904223` is odd, and `multiplier - 1 = 1664524` is
divisible by 4 (`1664524 = 4 * 416131`). Full period means the sequence does
not degenerate into short repeating cycles across the sample counts these
tests use (1000-2000 draws per test).

Changing the seed changes which colours are sampled and is a material change
to the suite, not a cosmetic one — every `MEASURED` line printed by
`PropertyTests.swift`, and both pinned tolerances derived from it
(`P-TOL-6` below, and any future ones), are worst-case values over THIS
specific seed's sweep, not universal bounds. A different seed could measure
a different worst case, larger or smaller. Re-pin on evidence if the seed
ever changes.

## P-TOL-6 — post-map deltaEOK vs fixed-hue/lightness proxy

`testHueAndLightnessSurviveChromaReduction` in `PropertyTests.swift` sweeps
1000 `(lightness, hue)` pairs at a fixed chroma of `0.35` (deliberately far
out of gamut for most inputs) through `gamutMap(_, to: .sRGB, using:
.cssColor4)`, under the `P-SEED-1` seed.

The algorithm's TRUE internal guarantee (CSS Color 4 §14.2.2) is that its
returned, clipped colour satisfies `deltaEOK(clipped, searchCandidate) <
jndThreshold` (`0.02`) EXACTLY, where `searchCandidate` is the internal,
fixed-hue/lightness binary-search candidate at the point of return. That
candidate is not part of `gamutMap`'s public return value, so a black-box
property test cannot compute this exact quantity. Instrumenting the
algorithm's internals directly (rather than through the public API) to
measure it anyway, over the same seed and sweep, found 0/1000 violations of
that exact bound, worst measured internal value `0.019999841195447562` —
consistent with the bound holding by construction, as the algorithm's own
code structure implies.

The test instead measures a PROXY: `deltaEOK(mapped, Oklch(lightness: l,
chroma: mapped.chroma, hue: h))` — i.e. it substitutes the search
candidate's unknown chroma with the *returned, post-clip* chroma instead.
This is a weaker, genuinely different quantity from the true internal
guarantee (it compares against a candidate built after the search already
converged, not the one the search was actually bounding against at each
step), which is exactly why it needs a looser bound than `jndThreshold`
itself: measured worst value for this proxy, same seed and sweep, is
`0.01944706978379128`.

Pin: `0.05`, roughly 2.6x the measured proxy value (`0.0194`). Sized the same
way `P-TOL-3` was — headroom over the measurement, not a round multiple of an
unrelated constant. The headroom covers cross-platform `libm` differences (as
under `P-TOL-3`) while staying roughly half the distance from the measured
value to one that would actually indicate the search losing its
fixed-hue/lightness discipline (e.g. exceeding `jndThreshold` by a large
margin, or drifting by multiple JNDs).

This pin, like the proxy it bounds, is seed-dependent: it is the worst value
measured over the `P-SEED-1` sweep of 1000 samples, not a universal bound
proven for all possible inputs. It is a regression detector for tier 2, not
a correctness proof — see `GamutMappingTests.swift`'s
`testCSSMappingMatchesOracleForOutOfGamutRed` comment, which already
established that a similar deltaEOK-vs-JND-style check could not by itself
discriminate a correct implementation from the pre-fix, spec-noncompliant
one. Correctness is pinned by tier 1's oracle agreement (`P-TOL-3`/
`P-TOL-4`), not by this pin.

Measured on: Swift 6.3.3, macOS.

## P-TOL-7 — round-trip identity tolerance

`testRoundTripIdentityForInGamutColours` in `PropertyTests.swift` (tier 2,
ARCHITECTURE.md §5.2) sweeps 2000 `(lightness, hue, chroma)` triples under the
`P-SEED-1` seed, each already confirmed in-gamut, through `oklchToRGB` then
back through `rgbToOklch`, and asserts the round trip is the identity (within
tolerance) on lightness and, where chroma is above
`Oklch.powerlessChromaThreshold`, chroma too.

Measured worst error: `8.916478666520788e-16`. Pinned at `3e-15`, roughly
3.4x the measured value — the same 2.6-4x headroom band `P-TOL-3` (2.9x) and
`P-TOL-5` (3-4x) use, sized for legitimate cross-platform `libm` differences
rather than for slack. This bounds `OklchCore`'s pure-`Double` round trip and
has no relationship to `P-TOL-1`'s `Float32` floor — see `P-TOL-1`'s scope
above.

Measured on: Swift 6.3.3, macOS.

## P-APCA-1 — why constants, not a version number

The APCA revision is pinned by its numeric constants because the ecosystem
labels the same constant set inconsistently. Color.js 0.7.1's source header
reads `// APCA 0.0.98G`, while the identical constants are published as
`0.1.9` in the apca-w3 repository. A version string in this pin would
therefore be ambiguous and unverifiable; the constants are neither.

Cross-check: BLACK text on a WHITE background gives `Lc 106.04067321268862`
in Color.js 0.7.1 (white text on black is the reverse polarity and gives
`-107.88473318309848`). `contrast-black-on-white` in the
generated fixture set reproduces `106.04067321268862` exactly (foreground
black, background white — `apcaContrast`'s `text` argument is Color.js's
`foreground`, its `background` argument is Color.js's `background`;
`Color.contrast` takes `(background, foreground, algorithm)`, background
first — getting this order backwards flips the sign). Any implementation
reproducing that value with these constants is the revision we mean.

Two places where reference APCA code (not just its constants) diverged from
the vendored source, both corrected by reading
`Tools/gen-fixtures/node_modules/colorjs.io/src/contrast/APCA.js` directly
rather than trusting a second-hand transcription:

1. **Sign handling in the luminance power curve.** The reference used
   `pow(max(rgb.red, 0), 2.4)`, clamping negative RGB components to zero
   before raising to the exponent. The vendored `linearize()` instead
   preserves sign: `sign * pow(abs(val), 2.4)`. `RGB.red/green/blue` here are
   ENCODED and sign-symmetric by construction (`Gamut.encode`/`decode` are
   both explicitly sign-symmetric, per `Gamut.swift`'s comment about defect
   `B3`), and go negative exactly when a colour is out of the target gamut —
   which `oklchToRGB` does not clamp.

   Measured, this is worth real magnitude on real out-of-gamut input. For
   `oklch(0.05 0.4 300)` text on white — sRGB coords `[0.1744059121505189,
   -0.21355193213548834, 0.4709713370036112]`, note the negative green —
   the sign-preserving version gives `Lc 107.33628154891362`, matching
   Color.js's oracle (`Color.contrast(white, text, "APCA")`) exactly. The
   clamp-to-zero version gives `100.52385297907891` instead: **6.8 Lc off**,
   nowhere near float noise. The original 5-case fixture set was all
   in-gamut sRGB and could not catch this; `contrast-oog-green-on-white` was
   added for exactly this reason (see `P-TOL-5`).
2. **Clip/offset branching.** The reference tied the low-contrast clip
   check and the offset's sign to which polarity branch was taken (`output <
   apcaLoClip` in the dark-on-light branch, `output > -apcaLoClip` in the
   light-on-dark branch). The vendored source instead checks `abs(C) <
   loClip` uniformly, then separately chooses the offset sign by `C > 0`,
   independent of which branch computed `C`.

   The discrepancy is not merely rare: it is findable once either post-clamp
   luminance exceeds `1`, which is reachable for sufficiently saturated
   out-of-gamut colours (`linearize` grows as `v^2.4`, so a handful of RGB
   components near or above `2` easily pushes the weighted sum past `1`). A
   synthetic luminance sweep (bypassing `oklch` to isolate just this branch)
   found real (yBg, yTxt) pairs both above `1` — e.g. `yBg=4.45, yTxt=4.50`
   — where `C` computed in the WoB (light-on-dark) branch comes out
   **positive** (`C=0.1118`, `Lc=8.4769` after clip/offset under the
   vendored source's unified `C > 0` check), but the branch-tied reference
   version incorrectly assumes WoB always yields non-positive `C` and clips
   it to `0`. Reproduced across ~22 such pairs in the swept range.

Neither divergence affects the original 5-case fixture set's measured
agreement (both contribute exactly `0` to that set's worst case). Both are
corrected: the vendored file wins on any disagreement, constants or
structure.

## P-TOL-5 — contrast agreement with the Color.js oracle

Worst absolute error between this package's `wcagContrast`/`apcaContrast`
and Color.js's `Color.contrast(background, foreground, "WCAG21" | "APCA")`,
across the fixture's `contrast-*` cases.

On the original 5-case set (all in-gamut sRGB): WCAG
`3.552713678800501e-15`, APCA `1.4210854715202004e-14`.

On the current 6-case set (adding `contrast-oog-green-on-white`, an
out-of-gamut pair, `oklch(0.87 0.30 142.5)` text on white, reusing Group 3's
`oog-green` triple): WCAG unchanged at `3.552713678800501e-15`; APCA
worst rose to `2.4868995751603507e-14`, entirely from the new out-of-gamut
case (still float64 noise floor, just a different noise floor once a
sign-preserving-`linearize` case is actually exercised). Pin: WCAG `<=
1e-14`, APCA `<= 1e-13`, replacing initial guesses of `1e-6`/`1e-4` — nine
to ten orders of magnitude looser than the measurement, which as pinned
would not have caught the class of constant-transcription error `P-APCA-1`
exists to catch. Sized the same way `P-TOL-3` was: roughly 3-4x the
measurement, headroom for cross-platform `libm` differences without hiding
a real regression.

**The WCAG side did NOT start at noise floor.** `relativeLuminance`
originally used WCAG 2.1's officially published, rounded coefficients
(`0.2126, 0.7152, 0.0722`). Measured against the fixtures, this produced a
worst error of `5.4e-4` — four orders of magnitude over even the loose
`1e-6` tolerance, on grey/blue/red-mixed cases (a pure achromatic case
cannot distinguish the two coefficient sets, since both sum to `1`). WCAG is
a closed-form formula with no search in it; error at that scale is a genuine
defect, not a tolerance to widen, so it was investigated.

The cause: Color.js's `luminance` getter does not use the rounded published
constants at all — it converts the colour to XYZ D65 and reads the `Y`
component, using its own full-precision sRGB->XYZ matrix row:
`0.21263900587151027, 0.715168678767756, 0.07219231536073371`
(`node_modules/colorjs.io/src/spaces/srgb-linear.js:20`). This codebase's
own `Gamut.sRGB.toXYZ` middle row is *extremely* close but not bit-identical:
`0.21263900587151036, 0.7151686787677559, 0.07219231536073371` — the R and G
coefficients differ from Color.js's by 1-2 ULP, only B is bit-identical.
That ULP-level gap between
`Gamut.sRGB.toXYZ` and Color.js's own matrix is now the entire residual:
it is why the measured WCAG error is `3.55e-15` rather than exactly `0`,
not a coincidence.

`relativeLuminance` was corrected to read the matrix row instead of
hardcoding the rounded constants, which took the measured error from
`5.4e-4` to `3.55e-15` in one change — using `Gamut.sRGB.toXYZ` (this
codebase's own matrix, not Color.js's file directly) is what leaves the
small ULP residual rather than reaching exact float64 equality. Note these
are NOT the same "precise" coefficients APCA.js uses (`0.2126729,
0.7151522, 0.072175`, sourced from Lindbloom via Myndex, per that file's
own comment "weights should be from CSS Color 4, not the ones here"); WCAG
luminance and APCA luminance use two different, both non-rounded,
coefficient sets, and conflating them would have reintroduced a smaller but
still real error.

**A second, more serious WCAG defect: `relativeLuminance` ignored its
`gamut` argument**, always
using `Gamut.sRGB.toXYZ`'s row regardless of whether `.sRGB` or
`.displayP3` was passed. Relative luminance is intrinsic to a colour — the
two paths must agree for any colour representable in both gamuts, since it
is the same physical light either way. Measured before the fix: for an
in-gamut pair (`oklch(0.5 0.1 30)` vs `oklch(0.8 0.05 200)`), `.sRGB` gave
`3.4347591924746714` (correct) and `.displayP3` gave `3.511974377896717` —
2.2% off, not float noise. Isolating just P3 pure blue's luminance showed
the fingerprint precisely: ours came back as `0.07219231536073385`, which
*is* sRGB blue's Y coefficient (not P3's true `0.079286914093745`) — proof
the P3 path was silently reusing the sRGB matrix row. This was not caught by
any fixture, because the fixture set is `.sRGB`-only. Fixed by changing
`relativeLuminance`'s signature to `(_ rgb: RGB, in gamut: Gamut) -> Double`
and reading `gamut.toXYZ`'s row instead of always `Gamut.sRGB.toXYZ`'s;
`wcagContrast` now threads its own `gamut` argument through. Covered by
`testWCAGAgreesAcrossGamutsForInGamutColours` (agreement to `1e-12`), not by
a Color.js fixture — there is no Display P3 contrast fixture case, so this
property is asserted directly rather than measured against the oracle.

**The WCAG ratio could also exceed its documented `1...21` range.**
Color.js's `WCAG21.js` clamps each luminance to `max(Y, 0)` before forming
the ratio; `wcagContrast` initially did not.
For `oklch(0.05 0.4 300)` against white — an out-of-gamut colour whose raw
luminance goes negative under the sign-preserving `Gamut.decode` — the
unclamped ratio measured `24.860440877119924`, 18% over `21`, against
Color.js's `21.000000000000007`. Fixed by clamping each side to `max(Y, 0)`
before forming the ratio, matching `WCAG21.js:18-19` exactly. Covered by
`testWCAGStaysWithinDocumentedRangeForOutOfGamutColour`, asserting the
result stays at or under `21` for that exact colour.

**APCA's `gamut` argument is deliberately NOT threaded the same way.**
APCA.js unconditionally converts both inputs `to(color, "srgb")`
(`APCA.js:58,68`) before computing luminance, regardless of what space they
started in — APCA is defined on sRGB, full stop. `apcaContrast`'s `gamut`
parameter therefore does not select the luminance-computation space (it
always runs in `.sRGB`); before this fix, passing `.displayP3` changed the
result for the same colour pair (`44.505499167000146` for `.sRGB` vs
`45.36268484544796` for `.displayP3` on one measured pair), which is not
oracle-faithful. This is exactly why the sign-preserving `linearize` from
`P-APCA-1` matters in practice: an out-of-gamut Display P3 colour lands as
negative sRGB components, and those must keep their sign through the
luminance sum rather than get clamped to zero.

This pin covers 6 fixture cases (5 in-gamut sRGB, 1 out-of-gamut sRGB) —
still no Display P3 contrast fixture case exists, so the P3-vs-sRGB WCAG
agreement property above is verified by direct test assertion, not by
fixture comparison against the oracle.

Measured on: Swift 6.3.3, macOS. Node v26.4.0, colorjs.io 0.7.1.

## P-DIR-1 — automatic direction tie-break

`Direction.automatic` measures contrast at both lightness extremes and searches
toward whichever offers more. When the two are exactly equal it chooses
`darker`.

The requirement was only that a tie-break be picked and documented, not that
it be optimal. Darker is chosen because dark-on-light is the more common reading
orientation and APCA scores it slightly higher at equal luminance difference.
Exact ties are vanishingly rare in practice; the pin exists so the behaviour is
deterministic rather than incidental.

Implementation (`Sources/OklchCore/ContrastSolver.swift`): `searchDarker =
darkest >= lightest`, where `darkest`/`lightest` are the (gamut-mapped,
measured) contrast values at lightness `0` and `1`. Using `>=` rather than
`>` is what makes an exact tie resolve to `darker`.

**The "more headroom wins" half is tested**
(`testAutomaticDirectionFollowsMoreHeadroom` in `ContrastSolverTests.swift`):
against a near-black backdrop (`lightness 0.05`), `.automatic` matches
`.lighter`; against a near-white backdrop (`lightness 0.95`), `.automatic`
matches `.darker`. Both assertions are discriminating — a solver that ignored
headroom and always searched one direction would fail one of them.

**The exact-tie half is verified by code inspection, not by test, and that
was a deliberate, measured choice.** Probing for a real backdrop where
`darkest` and `lightest` are bit-identical (bisecting on backdrop lightness
for `wcagContrast(black, backdrop) == wcagContrast(white, backdrop)`, hue 0,
chroma 0) found the closest approach at `lightness = 0.5637092048666653`:
`darkC = 4.582575694955837` vs `lightC = 4.58257569495584` — a difference of
`~3e-15`, i.e. float noise, not a true tie, and at that scale the `>=`
comparison could plausibly land either way depending on platform `libm`
behaviour (see the `libm` headroom under `P-TOL-3` and `P-TOL-6`). Encoding
that specific value as a fixture would pin platform noise, not the
tie-break behaviour itself, so it was rejected in favour of the direct code
check above.

Measured on: Swift 6.3.3, macOS.

## P-CHAR-1 — light-mode Increase Contrast shift, characterization fixture

`Tools/run-characterization.sh` runs `CharacterizationTests` once with
Increase Contrast disabled and once enabled (`xcrun simctl ui <device>
increase_contrast enabled|disabled`), against the fixed style
`CharacterizationTests.swift` defines:

```swift
OklchStyle(Oklch(lightness: 0.55, chroma: 0.12, hue: 250))
    .dark(Oklch(lightness: 0.85, chroma: 0.09, hue: 250))
    .increasedContrast(light: Oklch(lightness: 0.25, chroma: 0.16, hue: 250),
                       dark: Oklch(lightness: 0.97, chroma: 0.10, hue: 250))
```

The simulator boots in light mode (the coverage gap documented in the
script's header and in `docs/survey.md`'s Known limitations), so both passes
exercise `light` -> `lightIncreased`, never the
dark variants. This pin is therefore explicitly a **light-mode-only**
measurement of one specific fixture's swing, not a general characterization
of what Increase Contrast does to an arbitrary `OklchStyle` — the fixture's
`lightIncreased` variant (`L=0.25`) is deliberately far from its `light`
variant (`L=0.55`), so the shift is large by construction, the same way
`ResolveTests`' fixtures are chosen to discriminate rather than to be
representative.

Measured (`oklch-probe` simulator, iOS runtime, Xcode 26.6, Swift 6.3.3):

| Setting | red | green | blue |
|---|---|---|---|
| standard | `0.19716647267341614` | `0.45856809616088867` | `0.7074742317199707` |
| increased | `-0.03433903306722641` | `0.11393941193819046` | `0.35612884163856506` |

Per-channel delta: red `0.23150550574064255`, green `0.3446286842226982`,
blue `0.35134539008140564`. Worst channel (blue) is the pinned value:
`0.35134539008140564`. All three channels move together — the negative red
under `increased` is the same "reachable-only-outside-sRGB, correctly
extended" signature `P-TOL-2` already documents, here appearing because the
increased-contrast variant is far enough from sRGB white/black that its
gamut-mapped result pushes slightly outside sRGB's extended-linear
representation too.

This is not a tolerance — nothing asserts `>= P-CHAR-1`. It exists so a
future re-run's magnitude has something concrete to compare against: if a
future measurement on the same fixture and same toolchain came back
drastically smaller (e.g. because a mutation silently weakened
`increasedContrast`'s effect while still nominally "differing"), that would
be worth investigating even though `run-characterization.sh`'s own pass/fail
check (`> P-TOL-1`'s tolerance) would still report PASS.

Measured on: Xcode 26.6, Swift 6.3.3, iOS Simulator (`oklch-probe`).

## Linux build verification

`OklchCore` must build on Linux. Two independent routes were run,
both succeeding, and both are recorded here because they exercise different things.

**Route 1 — Swift Static Linux SDK, cross-compiled from macOS.** URL and checksum were taken
from `https://www.swift.org/install/linux/` and independently verified:

- URL: `https://download.swift.org/swift-6.3.3-release/static-sdk/swift-6.3.3-RELEASE/swift-6.3.3-RELEASE_static-linux-0.1.0.artifactbundle.tar.gz`
- Published SHA-256 (from the swift.org install page): `87c3eaf908e67c0e13a84367119e12273cec1d2cd3d81f7d74bb36722d6b607b`
- Independently recomputed SHA-256 (`shasum -a 256` on the downloaded 304,974,043-byte file,
  before installing): `87c3eaf908e67c0e13a84367119e12273cec1d2cd3d81f7d74bb36722d6b607b` — bit-for-bit
  identical to the published value.
- `swift sdk install <url> --checksum <hash>` → installed and reports as `swift sdk list` identifier:
  `swift-6.3.3-RELEASE_static-linux-0.1.0`.
- Build command: `swift build --swift-sdk x86_64-swift-linux-musl --target OklchCore`.

**This route surfaced a real build failure on first attempt**, distinct from the
architectural violations ARCHITECTURE.md §4.1 warns about (`SwiftUI`, `UIKit`, `CoreGraphics`, `Foundation`).
`Sources/OklchCore/{Gamut,Contrast,Conversions}.swift` each had `#if canImport(Darwin) import
Darwin #else import Glibc #endif`. The Static Linux SDK targets musl libc, not glibc, and Swift's
musl targets expose a `Musl` module, not `Glibc` — `import Glibc` therefore failed with "no such
module 'Glibc'" under `x86_64-swift-linux-musl`. This is a legitimate three-way platform split
(Darwin / glibc-Linux / musl-Linux), not a forbidden import, so it was fixed rather than routed
around: all three files now read
`#if canImport(Darwin) import Darwin #elseif canImport(Glibc) import Glibc #elseif canImport(Musl)
import Musl #endif`. After the fix, the cross-compile succeeds cleanly with no warnings, and the
macOS `swift test` suite (52 tests) was re-run afterward and still passes, confirming the edit is
additive rather than a behavioural change on Darwin.

Cross-compilation cannot run tests (no execution target), so this route proves the build only.

**Route 2 — Docker, real Linux (glibc).** A real Linux build rather than a
cross-compile, and therefore the stronger check:

```
docker run --rm -v "$PWD:/w" -w /w swift:6.0 swift build --target OklchCore
docker run --rm -v "$PWD:/w" -w /w swift:6.0 swift test
```

- Image: `swift:6.0`, resolved digest `sha256:7aaea8cfbebc90f34aeacaabbfb51a905dbef9839fcd2f528621dd515f228128`.
- Build: clean, no warnings, using the unmodified `Glibc` branch of the same import guard (this
  image is glibc-based, unlike the musl SDK above, so it takes a different branch of the same
  three-way `#if` and confirms all three branches are live code, not dead code for one platform).
- Test: all 52 tests pass, 0 failures, 0 skipped — identical count to macOS. Every `MEASURED` line
  printed by `PropertyTests.swift` and `FixtureTests.swift` matched the macOS-measured values
  exactly (e.g. `MEASURED oklch->srgb worst error: 3.46947470752923e-14 at srgb-corner-green`,
  `MEASURED worst deltaEOK vs fixed-hue/lightness proxy: 0.01944706978379128`), i.e. no libm
  divergence was observed between Linux/glibc and macOS/Darwin for any pinned tolerance in this
  run — the cross-platform headroom built into `P-TOL-3`, `P-TOL-4` and `P-TOL-6` was not needed
  this time.
- `RegressionTests.test_B4_clipGuardUsesTargetGamut_danielcr12OKLCHKit`'s underlying hue-drift
  measurement (the value the 2.5° tolerance is fixture-specific to — see `docs/survey.md`'s
  Known limitations) was independently reproduced on this Linux route via a throwaway executable
  target depending on the built `OklchCore` product (not committed to this repo): **Linux-measured
  1.7833092065677931 degrees**, bit-for-bit identical to the same measurement run natively on
  macOS. The flagged branch-flip risk near the threshold did not materialize on this run;
  both platforms agree to full `Double` precision on this fixture.

Both routes succeeding, independently, using two different libc implementations under the same
`#if` guard, is stronger evidence for ARCHITECTURE.md §4.1's "compiles on Linux" than either alone.

