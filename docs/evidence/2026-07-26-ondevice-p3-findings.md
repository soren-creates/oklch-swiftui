# On-device Display P3 evidence — 2026-07-26

ARCHITECTURE.md §5.6 required physical Apple hardware with a genuine Display P3 screen, producing committed
evidence rather than an automated assertion. This device run is that evidence:
`docs/evidence/2026-07-26-ondevice-p3.json`, captured on an iPhone 14 (`iPhone14,7`), iOS 26.6,
Xcode 26.6, Swift 6.3.3, via `Tools/run-ondevice-evidence.sh`.

## Device vs. Simulator

Simulator figures are probe A3 (`docs/evidence/2026-07-25-swiftui-probes.md`,
`docs/pins.md`'s `P-TOL-2`), measured on iOS 26.5 Simulator (iPhone 17 Pro) and iOS 17.0 Simulator
(iPhone 15 Pro), both runtimes agreeing. Device figures are this run's
`docs/evidence/2026-07-26-ondevice-p3.json`. All values are extended-linear sRGB readback of
`displayP3(0, 1, 0)` rendered through each path.

| Path | Simulator r | Device r | Δr | Simulator g | Device g | Δg | Simulator b | Device b | Δb |
|---|---|---|---|---|---|---|---|---|---|
| `solid_fill` | -0.2247314453125 | -0.2247314453125 | 0 | 1.0419921875 | 1.0419921875 | 0 | -0.07861328125 | -0.07861328125 | 0 |
| `foreground` | -0.2247314453125 | -0.2247314453125 | 0 | 1.0419921875 | 1.0419921875 | 0 | -0.07861328125 | -0.07861328125 | 0 |
| `gradient` | -0.2247314453125 | -0.2247314453125 | 0 | 1.0419921875 | 1.0419921875 | 0 | -0.07861328125 | -0.07861328125 | 0 |
| `oklch_style` | (no Simulator baseline — new in this run) | -0.2247314453125 | — | — | 1.0419921875 | — | — | -0.07861328125 | — |
| `canvas` | -0.22314453125 | -0.22314453125 | 0 | 1.044921875 | 1.044921875 | 0 | -0.0791015625 | -0.0791015625 | 0 |

Every device measurement is **bit-for-bit identical** to its Simulator counterpart, on all four
paths A3 originally measured. `oklch_style` did not exist when A3 ran (it exercises `OklchStyle`
itself, not just a raw `Color(.displayP3,…)` fill) and it matches `solid_fill` exactly, both on
device and internally consistent with the other three paths.

`canvas`'s own delta from the other three paths (not a Simulator/device delta — this is the same
divergence measured on both) is `0.0029296875` on the green channel, the worst channel — identical
in both magnitude and direction to the Simulator measurement. This is `P-TOL-2`'s documented
`canvas`-diverges-by-`0.0029` finding, now reproduced on hardware rather than assumed to hold
there.

The device's own internal gradient-vs-solid check (`C2-gradient-agreement` in the evidence file)
reports `worst_delta: 0` — not merely within tolerance, exactly equal.

## What this run does and does not establish

This section scopes all three conclusions below.

`ImageRenderer` rasterises entirely in-process, through deterministic CoreGraphics colour-space
conversion math. It never touches the window server, the compositor, or the physical panel — on
device exactly as much as in the Simulator, which runs the same frameworks and the same ICC
transform matrices. **Bit-for-bit device/Simulator identity is therefore the EXPECTED outcome of
this measurement, not a striking confirmation that a real display was involved.** The harness
measures the framework's colour math, which is hardware-independent by construction — not the
display.

Sharpening this: `paths["oklch_style"]` is captured under
`.environment(\.colorGamut, .displayP3)` (`Tools/DeviceHarness/DeviceHarness/Measurement.swift`),
which *overrides* `\.colorGamut`'s auto-detected default rather than reading it. That default is
computed from `UITraitCollection.current.displayGamut` (`Sources/OklchUI/Environment.swift:63`) —
the one input in this entire exercise that a real Display P3 panel could report differently from a
Simulator. The harness hard-codes past exactly that value, so even `oklch_style`'s result is
independent of whatever gamut the device or Simulator actually reports having. (The raw trait
values are recorded separately — see "Hardware-dependent measurement" below.)

So: this run is a **consistency check**, not a wide-gamut proof. It confirms the framework's colour
math is identical on real hardware to what the Simulator already reported, and it closes Apple
Developer Forums thread 727506 on device (conclusion 2, below). It does **not** establish that
Display P3 data reaches or survives on the physical panel — `ImageRenderer` never reaches that
layer, on device or in the Simulator. If future work needs that claim, the escalation is a genuine
screenshot/pixel-capture comparison against the physical screen — out of scope for this run.

### Hardware-dependent measurement

The evidence file now also records the one measurement in this harness that a real device and a
Simulator could genuinely disagree on: `Gamut.detected()`'s result, the raw
`UITraitCollection.current.displayGamut` trait it reads, and the device's real hardware model
identifier (`UIDevice.current.model` returns only the generic `"iPhone"`; `utsname`'s `machine`
field gives `iPhone14,7`). This both makes the evidence file self-supporting for its own hardware
claim and validates the package's own auto-detection default (`Environment.swift:63`) against a
real P3 panel rather than only against Simulator-reported traits. See the `gamut_detected`,
`display_gamut_trait`, and `device_model_identifier` fields on the `C2-render-paths` measurement in
`docs/evidence/2026-07-26-ondevice-p3.json`.

## Three conclusions

**1. P3 survives the framework's colour math, un-clamped.** `solid_fill`'s red channel measured
`-0.2247314453125` — negative, which is unreachable in sRGB and cannot occur by accident (sRGB's
encoded range is `[0, 1]`; a negative value only arises from a wider gamut's green primary being
genuinely outside sRGB's reproducible range and surviving, un-clamped, through readback). This
reproduces bit-for-bit, on device, what the earlier probes already measured in the Simulator —
expected, per the scoping above. What this run adds is not a new number but where it was measured:
it satisfies ARCHITECTURE.md §5.6's requirement for evidence gathered on physical Apple hardware,
and confirms the framework's colour math holds there too. It does not, on its own, establish that a
real P3 panel received or displayed the value.

**2. Apple Developer Forums thread 727506 does NOT reproduce on device.** The thread reports
`LinearGradient` mishandling P3. `gradient` and `solid_fill` measured bit-for-bit identical on
device (`worst_delta: 0`, all three channels), the same non-reproduction the earlier probes found on both
Simulator runtimes. An open question carried since those probes — whether `P-TOL-2` holds on
device — is now closed. `LinearGradient`
does not lose P3 fidelity relative to a solid fill, on this device, at this measurement precision.

**3. `OklchStyle` itself preserves P3 through its full resolution pipeline, on device.**
`oklch_style` — the actual public type this package ships, not a raw `Color(.displayP3,…)` literal
— matches `solid_fill` exactly on device. The resolution pipeline (`resolve(in:)` -> gamut-mapped
`Color` -> rendered pixel) does not introduce any additional loss beyond what a bare `Color` fill
already shows. As with conclusion 1, this is a claim about the pipeline's colour math, not about
what a physical panel displays — and it is measured under the hard-coded `\.colorGamut` override
noted in the scoping above, not the package's own auto-detected value.

## Structural finding: on-device XCTest is impossible from a pure SPM package

SPM `.testTarget`s are tool-hosted, and iOS device destinations refuse tool-hosted testing
outright (`xcodebuild test` on a device destination fails with "Select a host application for the
test target"). On-device testing needs the test bundle injected into an installed, signed host app
— an `.xcodeproj`, not a package target — which is why `Tools/DeviceHarness/` exists as a small
standalone SwiftUI app rather than a device-run XCTest suite. Full detail:
`docs/survey.md`'s "Known limitations — the on-device harness" section.

## Limitation carried forward

The scoping above is the limitation: this run measures the framework's in-process colour math,
not the physical display path. Proving panel delivery needs a screenshot/pixel-capture comparison
against the physical screen.
