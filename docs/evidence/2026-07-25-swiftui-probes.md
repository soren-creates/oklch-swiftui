# SwiftUI behaviour probes — 2026-07-25

What SwiftUI actually does, measured rather than assumed, before the package was written. Probe
IDs (`A1`–`A5`) are cited from `docs/pins.md` and from test comments throughout the repo.
Bare `§N.N` references below are sections of [`../ARCHITECTURE.md`](../ARCHITECTURE.md).

Environment: Xcode 26.6 (17F113) · Swift 6.3.3

Measured on two runtimes, with identical results on both:

- iOS 26.5 (23F77) Simulator · iPhone 17 Pro
- iOS 17.0 (21A328) Simulator · iPhone 15 Pro — the deployment floor declared in §3.3

| Probe | Question | Answer | Consequence |
|---|---|---|---|
| A1 | `Color.Resolved: ShapeStyle`? | **Yes.** Typechecks clean; empty compile log. | The optimisation in §4.2 is available. Not adopted in v1 — `Color` remains the specified return type — but it is no longer an open question. |
| A2a | `\.colorSchemeContrast` settable? | **No.** It is a read-only `KeyPath`, not a `WritableKeyPath`. | Contrast cannot be overridden in-process. Has a real cost for §5.5 — see "Consequence for the SwiftUI layer" below. |
| A2b | Does contrast change reach `resolve(in:)`? | **Yes, in a real view hierarchy.** Hosted (`UIHostingController` in `UIWindow`): `standard` → `increased` tracking the system setting exactly. Under `ImageRenderer`: `standard` under both settings. | **§4.2 stands unamended.** The architecture's load-bearing assumption holds. `ImageRenderer` is the limitation, not SwiftUI. |
| A3 | Does P3 reach pixels, and do paths agree? | **Yes to both.** All four paths return negative red in extended-linear sRGB. `solid_fill`/`foreground`/`gradient` identical at `[-0.2247314453125, 1.0419921875, -0.07861328125]`; `canvas` at `[-0.22314453125, 1.044921875, -0.0791015625]`, agreeing within 0.01. | **§3.1's wide-gamut claim is supported.** The forum-reported `LinearGradient` P3 defect does not reproduce on either tested runtime. |
| A4 | Is `UITraitCollection.current` meaningful in `resolve`? | **Yes.** `P3` both inside and outside `resolve(in:)`; `resolve` invoked exactly once. | Injected `\.colorGamut` is convenience plus testability, not strict necessity. This disproves §4.3's stated premise, which has been corrected — see "Amendment applied" below. |
| A5 | Precision floor | `5.9604644775390625e-08`, worst case at `v=0.015625` over a 65-point deterministic grid. | Exactly `2^-24`. SwiftUI imposes no quantisation beyond `Float32` storage. Pinned as `P-TOL-1`. |

---

## A2 in detail — why the first measurement was not the answer

A2b first rendered through `ImageRenderer` and reported `standard` under both
simctl contrast settings. Read naively that is an architecture failure: it
would mean §4.2's table is wrong and the Increase Contrast feature is dead.

Two probes were added to distinguish the possible causes before drawing any
conclusion:

**A2c — did the setting reach the process at all?** Yes. With contrast enabled,
UIKit reported `isDarkerSystemColorsEnabled = true` and
`accessibilityContrast = high`, while `resolve(in:)` in the same process on the
same run reported `standard`. So the setting was present and SwiftUI's
off-screen renderer did not carry it.

**A2d — does a real hierarchy behave differently?** Yes, decisively. Rendering
through `UIHostingController` inside a `UIWindow`:

| Simulator setting | `window.traitCollection` | Seen by `resolve(in:)` |
|---|---|---|
| `increase_contrast disabled` | `normal` | `standard` |
| `increase_contrast enabled` | `high` | `increased` |

Both directions were measured. The control run matters: had the disabled case
also reported `increased`, the probe would have been constant rather than
sensitive, and would have proved nothing.

**Conclusion: A2 holds.** SwiftUI delivers `colorSchemeContrast` to
`resolve(in:)` in the render path an actual app uses. `ImageRenderer` builds its
own environment and is not trait-aware.

### Consequence for the SwiftUI layer

Two constraints follow, and neither is optional:

1. **§5.5 characterization tests cannot use `ImageRenderer`** to vary
   environment inputs. It does not carry them. They must render through a
   hosted hierarchy.
2. **Contrast cannot be varied in-process** (A2a: the key is read-only). The
   contrast characterization test therefore requires an out-of-process toggle —
   `xcrun simctl ui <device> increase_contrast enabled|disabled` — with the
   suite run once per setting, exactly as `run-app-probes.sh` does. This makes
   the contrast test structurally different from the `colorScheme` and
   `colorGamut` tests, both of which remain settable via `.environment`.

Recorded as pin `P-ENV-1`.

---

## Amendment applied: §4.3's premise was factually wrong

§4.3 justified the injected `\.colorGamut` partly on the premise that
"`UITraitCollection.current` is not dependably meaningful inside
`resolve(in:)`". **A4 disproves that premise** — it was meaningful, reporting
`P3` both inside and outside `resolve`, in agreement.

§4.3 was corrected rather than merely annotated here: a spec is read by
people who assume it is true, and a known-false premise left standing
propagates into everything built on it.

The §4.3 *decision* survives on its other two stated justifications, which A4
does not touch: fully deterministic tests, and correct behaviour on an external
sRGB display. What changed is its status — it is a convenience-and-testability
choice, not a workaround for a missing platform capability.

---

## Harness findings

Three facts about the probe harness itself, none of which are properties of
SwiftUI's colour behaviour but all of which cost time to rediscover:

- **Scheme name is `OklchProbe-Package`**, not `OklchProbe`. SPM generates the
  `-Package` suffix; `xcodebuild -list` is the authority.
- **Test classes must be `@MainActor`.** `ImageRenderer.init(content:)` and
  `.cgImage` are main-actor isolated; the nonisolated form fails to build under
  this toolchain.
- **`CGContext` with `floatComponents` also requires `byteOrder32Little`** on
  little-endian. Without it, context creation returns nil and no pixel can be
  read.

---

## Deployment floor: RESOLVED

The first run of this suite covered iOS 26.5 only, which was the sole runtime
installed, leaving ARCHITECTURE.md §3.3's iOS 17 floor unverified. An iOS 17.0 runtime
(21A328) was installed the same day and the full suite re-run on an iPhone 15
Pro.

**Every probe returns identical results on both runtimes**, under both contrast
settings — including the two load-bearing ones:

| Probe | iOS 17.0 | iOS 26.5 |
|---|---|---|
| A2d hosted, contrast off | `standard` | `standard` |
| A2d hosted, contrast on | `increased` | `increased` |
| A2c `ImageRenderer` blind spot | `uikit=high, resolve=standard` | `uikit=high, resolve=standard` |
| A3 solid-fill red | `-0.2247314453125` | `-0.2247314453125` |
| A4 gamut inside `resolve` | `P3` | `P3` |
| A5 precision floor | `5.9604644775390625e-08` | `5.9604644775390625e-08` |

Evidence: `docs/evidence/2026-07-25-app-probes-ios17.0.json` alongside the 26.5
file. §3.3's floor is therefore supported by measurement at the floor version
itself, not extrapolated down from a newer runtime.

Note that A5 is byte-identical across runtimes, as it must be — `2^-24` is a
property of `Float32`, not of any OS version. Agreement there is a check on the
probe, not a finding about iOS.

## Remaining limitations

iOS 17.0 is the floor version; iOS 17.1–17.6 and 18.x were not tested. The two
tested runtimes bracket that range and agree exactly, which makes divergence in
between unlikely, but it is untested rather than proven.

macOS 14, tvOS 17 and visionOS 1 are declared in §3.3 and remain unmeasured at
runtime: those SDK runtimes are not installed on this machine. The compile
probes did target macOS, so A1 and A2a hold there; no runtime probe does.

`ImageRenderer` renders in-process and is not proof of the on-device display
path. ARCHITECTURE.md §5.6's harness remains required for A3 regardless of the result here.
A3's positive result is strong — a negative red channel cannot be produced by
accident — but it demonstrates that P3 survives *to a rendered buffer*, not that
it survives *to a physical wide-gamut display*.

A2d rendered a real hierarchy but still inside the Simulator. The Simulator's
trait plumbing is the same code path as device, so this is a weaker caveat than
A3's, but it is not a device measurement either.
