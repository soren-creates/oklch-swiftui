# Architecture

Why this package is shaped the way it is. Section numbers are stable: source and test comments
cite them (`// ARCHITECTURE.md §4.5`-style references in `Sources/` and `Tests/` point here), so
numbering is preserved even when the prose around it is revised.

For the decision *record* — what was chosen, what was rejected, and what would have to change to
revisit it — see [`adr/`](adr/). This document describes the design; the ADRs justify it.

---

## 1. Problem

SwiftUI has no perceptual colour model. Theme and palette work therefore happens in sRGB or HSL,
where changing hue or saturation silently changes perceived lightness — the exact thing a theming
system must not do.

OKLCH solves the perceptual part, and roughly twenty Swift packages already expose it. None of
them solve the *integration* part, and the gap is architectural rather than mathematical.

**Every existing library resolves OKLCH → RGB eagerly, at construction time.** The destination
gamut is not knowable at construction time — it is a runtime property of the display. Neither is
the user's Increase Contrast setting, nor which background the colour will sit on. A library that
converts eagerly has thrown away the information it needs to be correct.

SwiftUI has exposed the necessary hook since iOS 17: `ShapeStyle.resolve(in: EnvironmentValues)`.
Nothing in the ecosystem uses it to make colour decisions.

### 1.1 What this package is

A thin package providing OKLCH primitives that stay in OKLCH until SwiftUI asks for a colour, and
at that moment resolve against the real display gamut, the real colour scheme, the real contrast
setting, and the real background.

### 1.2 What this package is not

Not a colour-science library, not a design system, not a palette generator. Those exist, and are
the reason the existing packages are large and still do not close this gap.

---

## 2. Prior art

Twenty-plus Swift colour packages were read at source level before any code was written. Full
findings, including licence status and the reason each was rejected as a fork base, are in
[`survey.md`](survey.md).

Two conclusions shape everything below.

**Nobody validates against a reference implementation.** Not one surveyed package tests its
conversions against an independent oracle. That is why §5.1 exists.

**Five real defects were found in shipping packages**, and each became a named regression test
(`B1`–`B5`, `Tests/OklchCoreTests/RegressionTests.swift`) — linear hue interpolation with no
shortest-arc wrap, no powerless-hue rule, a gamma encoder that is not sign-symmetric, a ΔE_OK
guard that misreads P3 components as sRGB, and a hard per-channel clip that shifts hue exactly
where a ramp is most saturated. Details and attribution: [`survey.md`](survey.md).

Zero of the twenty read `colorSchemeContrast`. Zero contain any Helmholtz–Kohlrausch or
Okhsl/Okhsv handling.

---

## 3. Scope

### 3.1 What ships

- `Oklch` value type; sRGB and Display P3 gamuts
- CSS Color 4 [§14.2.2](https://www.w3.org/TR/css-color-4/#binsearch) gamut mapping (binary chroma
  search + ΔE_OK JND guard) and per-channel clip
- `Oklch.maxChroma(lightness:hue:in:)`
- Interpolation with shortest hue arc and CSS powerless-component rules
- APCA and WCAG contrast measurement
- `OklchStyle: ShapeStyle` resolving against `colorScheme`, `colorSchemeContrast`, `colorGamut`
- `\.themeBackground` plumbing and contrast-solved foreground styles
- Fixture, property, regression, contrast, and characterization test tiers

### 3.2 What is excluded, deliberately

JSON theming · ramps and palettes · gradients (iOS 18's `Gradient.colorSpace(.perceptual)` covers
the common case) · image extraction · CIELab/LCh · CAM16/HCT · Rec.2020 · Helmholtz–Kohlrausch
correction.

H-K correction is the most interesting unclaimed ground in the ecosystem, and is deferred behind a
future opt-in flag rather than shipped: the correction models disagree with one another, and
shipping a contested default would undermine the package's central claim.

Fusing `maxChroma` with the contrast solve (a 2-D solve) awaits a concrete use case.

### 3.3 Platform floor

iOS 17 / macOS 14 / tvOS 17 / visionOS 1. `ShapeStyle.resolve(in:)` is the hinge of the design and
is unavailable earlier. watchOS is supported by `OklchCore` only.

**What is actually measured.** iOS 17.0 (21A328) is measured directly: the full probe suite ran on
the floor version and returned results identical to iOS 26.5, including both load-bearing probes.
iOS 17.1–17.6 and 18.x are untested but bracketed by two agreeing runtimes. macOS 14 is covered
for the compile-time probes only. tvOS 17 and visionOS 1 are unmeasured — those runtimes were not
installed. Evidence: [`evidence/2026-07-25-swiftui-probes.md`](evidence/2026-07-25-swiftui-probes.md).

---

## 4. Architecture

### 4.1 `OklchCore` — pure values, no platform dependencies

```swift
public struct Oklch: Hashable, Sendable {
    public var lightness: Double   // 0...1
    public var chroma: Double      // 0...~0.4, formally unbounded
    public var hue: Double         // degrees, wrapped to 0..<360
    public var alpha: Double = 1
}
```

`hue` is a computed property over private storage: it normalises to `0..<360` on assignment as
well as on construction, so the documented range is an invariant rather than a constructor
convention.

Hue is `Double` degrees, not `Angle`. It matches CSS and every OKLCH tool on the web, and avoids
the radians/degrees ambiguity an `Angle`-based API invites.

Powerlessness is **derived** from chroma (`chroma < 1e-4`), not modelled as `Optional`. CSS's
powerless rules only alter behaviour during interpolation, so they are applied there. This keeps
`Optional` out of the ergonomic path at no cost in correctness.

```swift
public struct Gamut: Hashable, Sendable {
    public static let sRGB: Gamut
    public static let displayP3: Gamut
}

public enum GamutMap: Sendable {
    case cssColor4   // binary chroma search + ΔE_OK JND guard (default)
    case clip        // per-channel; for parity with GPU/shader paths
}
```

sRGB and Display P3 share a transfer curve, so `Gamut` is effectively a matrix pair. Rec.2020 is
omitted deliberately: no Apple display requires it, and it would introduce a second transfer
function.

`OklchCore` imports no SwiftUI and no UIKit, and compiles on Linux. That keeps the fixture suite
simulator-free, and leaves the maths reusable by a CLI or token exporter later. Every surveyed
library conflates these layers. See [ADR-0002](adr/0002-split-core-from-swiftui-layer.md).

### 4.2 `OklchUI` — the resolution pipeline

```swift
public struct OklchStyle: ShapeStyle, Sendable {
    public func resolve(in environment: EnvironmentValues) -> Color
}
```

A fixed-variant style reads exactly three environment values:

| Value | Purpose | Ecosystem status |
|---|---|---|
| `colorScheme` | light/dark variant selection | one surveyed package does this |
| `colorSchemeContrast` | Increase Contrast accessibility setting | **zero of twenty** read this |
| `colorGamut` | gamut-mapping target | ours; SwiftUI exposes no equivalent |

Pipeline: select variant → gamut-map → emit a `Color` tagged in the matching space. Gamut mapping
happens at `resolve(in:)` time, not at construction. See
[ADR-0001](adr/0001-resolve-late-not-at-construction.md).

A `.contrasting` style reads two more: `\.themeBackground`, to resolve an `.environment` backdrop,
and `\.oklchDiagnostics`, to report a target it could not reach.

`resolve` returns `Color`. `Color.Resolved` also conforms to `ShapeStyle` (measured, probe `A1`)
and would save one conversion; that is an optimisation, not an architectural dependency.

**This table is measured, not assumed.** `colorSchemeContrast` was confirmed reaching
`resolve(in:)` in a hosted view hierarchy, tracking the system setting in both directions. Two
constraints follow from the same measurements — `ImageRenderer` does not carry environment traits,
and `colorSchemeContrast` is not settable in-process — both recorded as pin `P-ENV-1` in
[`pins.md`](pins.md).

### 4.3 Why `\.colorGamut` is our own environment key

SwiftUI exposes no display gamut. We declare our own environment key, defaulting to a value
detected once at first use (`UITraitCollection.current.displayGamut` on iOS,
`NSScreen.canRepresent(.p3)` on macOS), overridable via `.colorGamut(.sRGB)`.

Reading the trait directly would also work — it was measured reporting `P3` both inside and
outside `resolve(in:)`, in agreement. The injected key earns its place on two other grounds:
fully deterministic tests, and correct behaviour on an external sRGB display, where
auto-detection alone hands back unreachable colours. It is a testability-and-correctness choice,
not a workaround for a missing platform capability. See
[ADR-0003](adr/0003-own-colorgamut-environment-key.md).

### 4.4 Background plumbing

A `\.themeBackground` that any caller may set independently will drift out of sync with what is
actually drawn, and a lying backdrop is worse than no backdrop. Drawing and publishing are
therefore a single modifier:

```swift
extension View {
    /// Fills the background AND publishes it to \.themeBackground.
    public func oklchBackground(_ style: OklchStyle) -> some View
}
```

One call site, so the environment cannot disagree with the pixels. That coupling is the design,
not an implementation detail. See
[ADR-0004](adr/0004-couple-background-drawing-to-publication.md).

### 4.5 Contrast solving

```swift
public extension OklchStyle {
    static func contrasting(
        _ target: ContrastTarget,
        hue: Double,
        chroma: Double,
        preferring direction: Direction = .automatic,
        against backdrop: Backdrop = .environment
    ) -> OklchStyle
}

public enum ContrastTarget: Sendable {
    case apca(Double)   // Lc
    case wcag(Double)   // ratio, 1...21
}
```

The solve itself — resolve the backdrop, bisect on lightness, gamut-map each candidate — is pure
maths and lives in `OklchCore` (`ContrastSolver.swift`). `OklchStyle.contrasting` is a thin
`OklchUI` wrapper over it, so the invariant `achieved >= requested` is testable without a
simulator.

At resolve time: resolve the backdrop to a concrete in-gamut colour, then bisect on `lightness`.

**Ordering requirement.** Each candidate is gamut-mapped *first*, then contrast is measured on the
mapped colour. Measuring before mapping yields a colour that fails its target the moment it is
displayed — precisely the bug class this package exists to prevent. See
[ADR-0005](adr/0005-gamut-map-before-measuring-contrast.md).

**Monotonicity, stated honestly.** Contrast is monotone in luminance on each side of the backdrop,
so bisection is stable. But chroma reduction during gamut mapping perturbs luminance, so the
*composed* function is not strictly monotone. The perturbation is not negligible: CSS Color 4's
own guarantee bounds it at one JND (ΔE_OK < 0.02), and `P-TOL-6` measured a worst-case proxy of
`0.01944706978379128` — essentially *at* the JND, not comfortably under it. Non-strict
monotonicity is accepted, with a hard iteration cap rather than a claim of exactness.

### 4.6 Unreachable contrast targets

APCA Lc 90 against a mid-grey backdrop at high chroma has no solution at any lightness. A view
body must never crash or refuse to draw; equally, silently returning a colour that misses its
target is the failure mode this package exists to eliminate.

Resolution therefore always returns the best achievable colour, and the shortfall is
**observable**:

```swift
public struct ContrastResolution: Sendable {
    public let requested: Double
    public let achieved: Double
}
```

A `\.oklchDiagnostics` handler may be installed to log or to fail tests. Renders never break;
contrast regressions are still caught. Tests assert on `achieved`. See
[ADR-0006](adr/0006-report-unreachable-targets-rather-than-throw.md).

### 4.7 Package layout

```
Sources/
  OklchCore/          no SwiftUI, no UIKit; compiles on Linux
    Oklch.swift  Gamut.swift  Conversions.swift        (Ottosson's matrices, attributed in-file)
    GamutMapping.swift                                 (CSS Color 4 §14.2.2)
    Interpolation.swift                                (shortest arc + powerless rules)
    Contrast.swift                                     (APCA + WCAG)
    ContrastSolver.swift                               (bisection; see §4.5)
  OklchUI/            SwiftUI only
    OklchStyle.swift  Environment.swift  Modifiers.swift
    OklchStyle+Contrasting.swift
    OklchUI.docc/                                      overview + Getting Started
Tests/
  OklchCoreTests/  OklchUITests/
Fixtures/
  colorjs/            generated, committed, byte-reproducible
Tools/
  gen-fixtures/       node + Color.js generator
  probe/              the throwaway probes that measured SwiftUI's actual behaviour
  DeviceHarness/      standalone app for on-device P3 measurement (§5.6)
docs/
  ARCHITECTURE.md  adr/  survey.md  pins.md
  evidence/           probe and on-device measurements
  api-baseline/       recorded public API surface, diffed by check.sh
```

---

## 5. Testing

Not one surveyed package validates against a reference implementation. That is this package's
principal differentiator, and it is why the tiers below exist.

### 5.1 Tier 1 — Color.js fixtures

A node generator runs [Color.js](https://colorjs.io) once to produce a few hundred cases: sRGB and
P3 corners, out-of-gamut OKLCH, achromatic edges, hue-wraparound pairs. The output JSON is
committed; Swift asserts equality within pinned tolerances.

**The generator asserts its own intent before writing, and stops on disagreement.** It states what
each fixture should be, then asks Color.js. On disagreement it writes nothing and reports.

Without that rule the generator degenerates into "whatever Color.js says is correct", and a
misreading of the spec is silently enshrined as the reference. This is the difference between a
fixture suite and a tautology. It has already paid for itself: the rule is what surfaced the
divergence recorded as `P-TOL-4` in [`pins.md`](pins.md).

Regeneration is reproducible — pinned node and Color.js versions, recorded in
`Tools/gen-fixtures/package-lock.json` and asserted by a fixture-integrity test. A missing or
corrupted fixture file **fails** the suite rather than silently skipping the oracle.

### 5.2 Tier 2 — property tests

Round-trip identity for in-gamut colours; gamut mapping is idempotent; mapped colours are always
in gamut; hue and lightness survive chroma reduction within pinned tolerance. Pinned RNG seed
(`P-SEED-1`), no wall-clock or entropy sources.

### 5.3 Tier 3 — regression tests

`B1`–`B5` from §2, each named for the defect and the package it was found in.

### 5.4 Tier 4 — contrast tests

`achieved >= requested` across a grid of backdrops and hues; automatic-direction behaviour; and
the diagnostic firing when a target is unreachable.

### 5.5 Tier 5 — characterization tests

One test per environment input, proving `resolve(in:)` output actually changes when `colorScheme`,
`colorSchemeContrast`, and `colorGamut` change. This is the central architectural claim, so it is
asserted directly rather than assumed.

These run through a real `UIWindow`: `ImageRenderer` does not carry environment traits (`P-ENV-1`),
so a renderer-based test would pass while proving nothing.

### 5.6 On-device evidence

Whether `Color(.displayP3,…)` reaches wide-gamut pixels through SwiftUI's render paths cannot be
settled in CI, and there was an unresolved report of `LinearGradient` mishandling P3 (Apple
Developer Forums thread 727506).

`Tools/DeviceHarness/` renders known out-of-sRGB swatches, reads its own pixels back, and **writes
the measured values to a file**. It ran on a physical iPhone 14 (iOS 26.6) via `xcrun devicectl`;
the file is the evidence, committed under `docs/evidence/`. No human transcribes or eyeballs
colour values.

Results, and their limits, are in
[`evidence/2026-07-26-ondevice-p3-findings.md`](evidence/2026-07-26-ondevice-p3-findings.md).
In brief: P3 survives the framework's colour math un-clamped on device, `OklchStyle`'s own
resolution path preserves it, and Forums 727506 does not reproduce. What the run does **not**
establish is that P3 reaches a physical panel — `ImageRenderer` rasterises in-process through
deterministic CoreGraphics maths and never touches the compositor, so device/Simulator identity is
the expected outcome, not proof of panel delivery. Proving that needs a framebuffer screenshot or
an external colorimeter.

An SPM `.testTarget` cannot run on a device destination at all — device destinations reject
tool-hosted testing — which is why the harness is a standalone app rather than a device XCTest
run. See [`survey.md`](survey.md)'s known limitations.

### 5.7 Test discipline by layer

| Layer | Discipline |
|---|---|
| `OklchCore` logic; defects `B1`–`B5` | Strict TDD, red before green |
| Conversion accuracy, gamut-map tolerances | Spike → measure → pin in `pins.md` |
| Contrast solver (`achieved >= requested`) | Strict TDD — the invariant is knowable upfront |
| `OklchUI` / `resolve(in:)` | Characterization tests against measured behaviour |

Tolerances are the one place TDD does not apply: achievable accuracy is unknowable before the
conversion chain exists, and guessing a tolerance then relaxing it until green is the same
tautology in TDD costume. Those are spiked, measured, and pinned with the measured value recorded.

The SwiftUI layer asserts Apple's behaviour, not ours, so it cannot be specified in advance. Green
there means "SwiftUI still does what we measured in July 2026" — a useful regression signal, but
the opposite of a specification.

---

## 6. Discipline

Four rules carry most of the weight, and each is enforced by something that runs rather than by
good intentions:

| Rule | Enforced by |
|---|---|
| Fixtures assert their own intent, then STOP | `Tools/gen-fixtures/generate.mjs`; §5.1 |
| One pins file is the single source of truth | [`pins.md`](pins.md); every test names its pin |
| Generation is deterministic | pinned RNG seed, pinned node + Color.js, no wall-clock |
| Doc examples are verified, not asserted | `Tests/OklchUITests/DocExampleTests.swift` |
| Tolerances move only on recorded evidence | a pin change requires a measurement in `pins.md` |
| One all-green gate | `./check.sh`; §6.1 |

Containerisation is deliberately absent: SwiftUI requires Apple hardware and a simulator, so it
buys nothing here. The reproducibility equivalent is a pinned toolchain plus pinned node +
Color.js for fixture regeneration.

### 6.1 `./check.sh` — the all-green gate

Runs in order, failing fast:

1. Regenerate fixtures, assert byte-identical to committed
2. Build
3. `OklchCoreTests`
4. `OklchUITests` — host, then simulator (where tier 5 actually executes), then the two-pass
   Increase Contrast probe
5. DocC build with `--warnings-as-errors`
6. Public API surface diff against `docs/api-baseline/`

Plus one **optional** step, which needs Apple hardware attached and is therefore never a gate:
re-capture the on-device P3 evidence and **verify** it against the committed file. It captures into
a scratch path and diffs; it never overwrites committed evidence. A gate verifies evidence, it does
not mutate it. When no device is reachable it prints a visible skip line rather than being silently
absent.

Green is required before any release tag.
