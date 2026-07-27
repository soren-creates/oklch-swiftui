# Survey

Twenty-plus Swift colour packages were read at source level on 2026-07-24/25, before any code in
this package was written. This file records what was found: why none of them was forked, the five
defects that became the regression suite, and the limitations this package knowingly carries.

It is the long form of [`ARCHITECTURE.md`](ARCHITECTURE.md) §2.

## Why not fork

| Candidate | Stars | License | Verdict |
|---|---|---|---|
| `metasidd/ColorTokensKit-Swift` | 212 | **none** | Unusable as dependency or fork. Core is structurally sRGB: hard per-channel clip, `Color(red:green:blue:)`, zero P3. Palette source of truth is hand-tuned CIELCh, not OKLCH. |
| `danielcr12/OKLCHKit` | 0 | MIT | Closest existing work; best gamut mapping in the ecosystem. Still eager-resolving, and carries 3,351 LOC of unrelated scope plus a confirmed P3 correctness bug. |
| `HarshilShah/ChromaKit` | 46 | MIT | Four constructors, no gamut mapping, no read-back. Test suite is four round-trips of one swatch. |
| `nikstar/swift-oklch` | 26 | **none** | Unusable as fork. Gamma encoder is not sign-symmetric. |
| `geonu1109/swift-color` | 0 | **none** | Unusable as fork. Has a real CSS Color 4 map, sRGB target only. |
| `material-foundation/material-color-utilities` (swift/) | — | Apache-2.0 | Ships HCT + `ContrastCurve` + `DynamicColor`: contrast-solved tokens already exist in Swift. But HCT/CAM16, sRGB-locked, and Google's design opinions are baked into the token layer. |

The licence column carries as much weight as the code column: three of the six candidates
carry **no licence at all**, which by itself rules them out as a fork or dependency regardless
of code quality — `nikstar/swift-oklch` and `geonu1109/swift-color` both have real, usable-looking
code, but an unlicensed repository cannot legally be forked or vendored from.

**Decision: build new.** The maths that already exists is small (~100 LOC: Ottosson's matrices
and the CSS Color 4 gamut map, both published specs with reference fixtures). The architecture
that is missing is the entire point and has nothing to fork. Acquiring ~100 LOC of well-specified
matrices by inheriting 3,351 LOC of someone else's theme engine is a net loss.

Vendored maths carries attribution in-file. `OKLCHKit` (MIT) may be consulted; if any code is
copied, its MIT notice ships in `THIRD-PARTY-NOTICES.md`. No code has been copied from it —
`OklchCore`'s gamut-map implementation was derived directly from the CSS Color 4
spec text (§14.2.2), not from `OKLCHKit`'s source, once `P-TOL-4`'s measurement showed the
reference pseudocode diverging from the CSS Color 4 spec text (see `docs/pins.md`).

## Defects found in the survey (`B1`–`B5`, the regression suite)

| ID | Defect | Source |
|---|---|---|
| `B1` | Hue interpolated linearly with no shortest-arc wrap: red (h=28.5°) → magenta (h=328.4°) traverses 300° through yellow/green/cyan/blue instead of the 60° arc. | `fwrs/OKLCHGradient` shader |
| `B2` | No powerless-hue rule: `.white` has chroma ≈ 0 and numerically garbage hue (89.9°), so white → blue lerps 89.9° → 264.1° and shows a green/cyan cast mid-gradient. | `fwrs/OKLCHGradient` shader |
| `B3` | Gamma encoder not sign-symmetric — negative linear channels take the `12.92 * c` branch, mis-encoding every out-of-gamut colour. | `nikstar/swift-oklch` |
| `B4` | ΔE_OK clip guard round-trips the clipped candidate through `srgbToOKLCH`, misreading P3 components as sRGB whenever the target gamut is P3. | `danielcr12/OKLCHKit` |
| `B5` | Hard per-channel clip to `[0,1]` shifts hue and lightness precisely where a ramp is most saturated. | `metasidd/ColorTokensKit-Swift` |

Each defect is covered by a named regression test in
`Tests/OklchCoreTests/RegressionTests.swift`:

- `B1` — `RegressionTests.test_B1_hueInterpolationTakesShortestArc_fwrsOKLCHGradient`
- `B2` — `RegressionTests.test_B2_powerlessWhiteDoesNotTintGradient_fwrsOKLCHGradient`
- `B3` — `RegressionTests.test_B3_gammaEncoderIsSignSymmetric_nikstarSwiftOklch`
- `B4` — `RegressionTests.test_B4_clipGuardUsesTargetGamut_danielcr12OKLCHKit`
- `B5` — `RegressionTests.test_B5_defaultMappingIsNotAHardClip_metasiddColorTokensKit`

All five pass (`swift test`, 52 tests total, 0 failures, 0 skipped — see
`docs/pins.md`'s Linux build verification section for the full run).

Zero of the twenty repos read `colorSchemeContrast`; zero contain any Helmholtz–Kohlrausch or
Okhsl/Okhsv handling. (Both claims are scoped to the 2026-07-24/25 window — see the addendum
below for one package that appeared as the survey closed.)

## Addendum — appeared after the survey window

| Candidate | Stars | License | Verdict (read 2026-07-27) |
|---|---|---|---|
| `eliseyOzerov/okcolor-swift` | 0 | nonstandard (GitHub: `NOASSERTION`) | Careful port of Ottosson's reference `ok_color.h`: Oklab/OkLch/OkHsv/OkHsl, shortest-arc hue interpolation, Ottosson-style gamut clipping, tested against generated C++ parity fixtures. Still the eager category: public API is `SRGB`-typed end to end, no P3 path, no SwiftUI layer, no environment reads. |

Created 2026-07-25, the survey's final day, so it postdates the reading above. It is the first
package seen shipping Okhsv/Okhsl, and its C++ parity fixtures are the same oracle discipline
this package applies with Color.js — but it changes no verdict: nothing in it resolves late,
and the licence would need clarifying before it could be considered as a dependency at all.

## Known limitations — core maths (`OklchCore`)

Found during `OklchCore` implementation and parked rather than fixed: fixing them would exceed
v1's scope (the `Oklch`/`Gamut`/`GamutMap`/interpolation/contrast surface of ARCHITECTURE.md
§3.1) or require new fixture generation, which ARCHITECTURE.md §5.1 treats as a deliberate,
reviewed step. Recorded here so they are not silently lost.

- **The committed fixture set is far smaller than ARCHITECTURE.md §5.1 called for.** ARCHITECTURE.md §5.1 asks for "a
  few hundred cases." The committed set is `24` conversion cases + `4` hue-arc cases + `6`
  contrast cases = `34` total (`Fixtures/colorjs/conversions.json`'s own `cases`/`hue_arcs`/
  `contrast` array lengths, echoed in `Tools/gen-fixtures/generate.mjs`'s own console output:
  "24 conversion cases, 4 hue-arc cases, 6 contrast cases"). All three fixture-derived pins
  (`P-TOL-3`, `P-TOL-4`, `P-TOL-5`) rest on this 34-case set, not the few hundred ARCHITECTURE.md §5.1
  anticipated.

- **`in_p3_gamut` is never asserted by any test.** `FixtureLoader.swift` decodes it on every
  `FixtureCase`, and `Tools/gen-fixtures/generate.mjs` populates it, but
  `Tests/OklchCoreTests/FixtureTests.swift` only asserts `in_srgb_gamut` against
  `RGB.isInGamut(epsilon:)`. P3 gamut-membership agreement with Color.js is therefore unverified,
  even though the field exists in every committed fixture case.

- **The non-monotonic sRGB gamut boundary IS oracle-covered, but only at the island itself —
  not between the two crossings.** `GamutMapping.swift`'s file header and `Oklch.maxChroma`'s doc
  comment both document that the sRGB gamut boundary is not monotonic in chroma at fixed lightness
  and hue — at `L=0.45, h=264.1`, chroma `0.31` is inside sRGB while both `0.29` and `0.315` (on
  either side of it) are outside, a narrow in-gamut "island" beyond the first true boundary
  crossing. `GamutMappingTests.swift`'s `testNonMonotonicBoundaryStillReturnsInGamutResult`
  reconfirms this with those exact values.
  `oog-blue` in the committed fixture set is `oklch: [0.45, 0.34, 264.1]`, the island's
  exact lightness and hue, and its `mapped_css_srgb`/`mapped_css_oklch` fields ARE asserted
  against Color.js under `P-TOL-4` (`Tests/OklchCoreTests/FixtureTests.swift`'s
  `testGamutMappingMatchesColorJS`); Color.js itself lands the mapped result at chroma
  `0.31251603143400747` — inside the island. So the island endpoint IS oracle-covered.
  What is missing is a fixture case whose input chroma is sampled BETWEEN the two
  boundary crossings, rather than beyond both the way `oog-blue`'s input chroma (`0.34`) is —
  a probe of whether the search's monotonicity assumption changes the outcome when the starting
  point already straddles the ambiguous zone, not just when it starts well outside it.

- **`P-TOL-4` rests on only 4 `oog-*` fixture cases, sRGB only, `.cssColor4` only.** There is no
  P3 gamut-map oracle case in the fixture set. `mapped_clip_srgb` (the `.clip` counterpart) IS
  generated by `Tools/gen-fixtures/generate.mjs` and IS decoded by `FixtureLoader.swift` on all 4
  `oog-*` cases — the data exists — but no test in `Tests/OklchCoreTests/` ever reads or asserts
  against it, the same class of hole as `in_p3_gamut` above rather than a genuine absence of data.
  See `docs/pins.md`'s `P-TOL-4` section.

- **`test_B4`'s 2.5° tolerance is fixture-specific**, with roughly a 1.18° discrimination window
  between the measured correct-code value (1.7833°) and the measured defect-reintroduced value
  (2.9612°) on the same fixture. A discrete branch-flip risk exists near threshold
  comparisons in the surrounding search; the Linux run reconfirmed the measurement:
  the Linux-measured value is `1.7833092065677931` degrees, bit-for-bit identical to the same
  measurement run natively on macOS (see `docs/pins.md`'s Linux build verification section, Route 2).
  Also note: the `isInGamut` assertion in `test_B4` itself was proven vacuous for this defect
  over a 113,316-sample sweep — the wrong-gamut misread still lands inside P3 by construction.
  It is a sanity check only; the hue-drift assertion is what actually discriminates.

- **`.apca(_:)`'s sign is discarded by `solveContrast`.** `ContrastSolver.swift` documents this
  explicitly: `requested = abs(lc)` regardless of the sign passed to `.apca`, and which side of
  the backdrop the solve lands on is governed entirely by `direction`, not by the target's sign.
  `.apca(-60)` and `.apca(60)` against the same backdrop with the same `direction` therefore
  return the bit-identical colour. This is a reviewed, documented design choice, not an oversight,
  but it means callers cannot use the sign of an `.apca` target to imply a direction.

- **`interpolate` does not clamp `t`.** `Interpolation.swift`'s `interpolate(_:_:t:)` uses `t`
  directly in every linear blend with no `min`/`max` guard. Values outside `0...1` extrapolate
  lightness, chroma and the shortest-arc hue blend beyond the two endpoints, which can produce
  invalid (negative or unbounded) chroma or out-of-range lightness. No test in
  `InterpolationTests.swift` or `PropertyTests.swift` currently exercises `t` outside `0...1`.

- **`solveContrast` accepts negative chroma and out-of-range backdrop lightness without
  validation.** `ContrastSolver.swift`'s `solveContrast` does not guard `chroma < 0` or a
  `backdrop.lightness` outside `0...1` before searching. Neither crashes, and the returned colour
  still stays in gamut (every candidate is gamut-mapped before being measured or returned — the
  file header's ordering guarantee holds regardless of how the caller's inputs were formed). But
  the WCAG contrast reported against such an out-of-range backdrop can exceed the documented
  `1...21` range, since `testWCAGStaysWithinDocumentedRangeForOutOfGamutColour` only covers
  `wcagContrast` being called with an out-of-gamut colour directly, not `solveContrast` being fed
  an out-of-range backdrop. Not fixed: v1's contrast surface (ARCHITECTURE.md §3.1) does not
  include input validation.

## Known limitations — the SwiftUI layer (`OklchUI`)

Found during `OklchUI` implementation and review; same status as the core-maths list above —
real, not fixed, worth knowing before relying on the behaviour.

- **The characterization runner exercises LIGHT mode only.** `Tools/run-characterization.sh`
  varies Increase Contrast (via `xcrun simctl ui <device> increase_contrast`) across two passes and
  asserts the resolved colour differs, but the simulator boots in light mode and the script never
  toggles `xcrun simctl ui <device> appearance dark`. So the contrast toggle it exercises is always
  `light` -> `lightIncreased`; `dark` and `darkIncreased` are never exercised end-to-end through a
  real hosted hierarchy with the real system setting — only through `ResolveTests`' unit-level
  calls to `Variants.select(scheme:contrast:)`, which construct an `EnvironmentValues` directly
  rather than reading a real trait. Also documented at the top of `Tools/run-characterization.sh`
  ("KNOWN COVERAGE GAP"). Closing it would need a second axis in the pass matrix (dark x
  contrast-off/on, four passes instead of two).

- **DocC prose values can drift from the tests that verify them, silently.** ARCHITECTURE.md §6's mechanism
  for keeping documented example values honest is a `<!-- verified-by: testName -->` marker per
  claim, checked by `DocExampleTests.testEveryVerifiedByMarkerNamesARealTest` — but that test only
  confirms the NAMED test exists in `DocExampleTests.swift`, not that the number the marker sits
  next to still matches what the test asserts. `GettingStarted.md`'s claim ("resolves to a lightness
  of approximately `0.57`") and `testGettingStartedContrastingLightnessClaim`'s
  `XCTAssertEqual(solved.lightness, 0.57, accuracy: 0.02, ...)` are two independent hardcoded
  literals, kept in sync only by hand. Editing the prose's `0.57` to a wrong value (e.g. `0.91`)
  while leaving the test's literal untouched leaves `swift test`, `check.sh`, and DocC's
  `--warnings-as-errors` docbuild all green — nothing reads the number back out of the rendered
  documentation. A fix (regex the "approximately `X`" value out of the prose at test time and
  compare it to a shared constant) was scoped out: it would only cover scalar claims phrased that
  exact way, not the behavioural claim under `testGettingStartedUnreachableClaim`'s marker, and it
  imposes a prose convention that is itself a smaller, different drift risk. Anyone changing a
  DocC-claimed numeric value must update both the prose and its paired test by hand.

- **DocC symbol links needed `SwiftUICore/...` qualification, not `SwiftUI/...`.**
  `Sources/OklchUI/OklchUI.docc/OklchUI.md`'s Topics section links to
  ``SwiftUICore/EnvironmentValues/colorGamut`` etc. rather than ``SwiftUI/EnvironmentValues/colorGamut``
  — on this repo's toolchain (Xcode 26.6, DocC via `xcodebuild docbuild`), the `SwiftUI/...` form
  left the link unresolved (a warning, promoted to a build failure by `check.sh`'s
  `--warnings-as-errors`), because `EnvironmentValues` and `View` are actually declared in the
  `SwiftUICore` module that `SwiftUI` re-exports, and DocC's cross-module symbol resolution wanted
  the declaring module's name, not the umbrella framework's. This may be specific to this Xcode/DocC
  version rather than a stable rule — worth re-checking if `check.sh`'s DocC step ever starts failing
  on a toolchain bump.

- **`oklchBackground(.contrasting(...))` publishing `nil` clears an ancestor's published backdrop
  for the whole subtree, not just for itself.** `Modifiers.swift`'s `publishedColour` deliberately
  returns `nil` for a `.contrasting` background — solving against a backdrop it would itself be
  publishing is circular — and that `nil` is documented at the call site. What is NOT documented is
  the consequence: `.environment(\.themeBackground, nil)` overwrites whatever an ANCESTOR published,
  for every descendant of this modifier, not merely "fails to add a new backdrop." Concretely: an
  outer `oklchBackground(.fixed(someRealColour))` followed by an inner
  `oklchBackground(.contrasting(...))` means any `.contrasting` style further down inside that inner
  subtree solves against `ContrastRequest.fallbackBackdrop` (white), not against the outer real
  colour that is still visually on screen behind it. A caller nesting `.contrasting` regions inside
  a `.contrasting`-backed region gets a silently wrong (if always-drawable, per ARCHITECTURE.md §4.6) answer.
  Whether `.contrasting` backgrounds should instead solve against the ancestor's backdrop and
  publish THAT solved colour forward, or keep `nil`-clears-ancestor as documented, deliberate
  behaviour, is an open design question.

- **`check.sh`'s `EXPECTED_HOST_TOTAL` / `EXPECTED_SKIPS` / `EXPECTED_SIM_TOTAL` /
  `EXPECTED_CORE_TOTAL` totals are hand-maintained integers, not derived from anything.** They are
  the only thing standing between a deleted test and a green gate (see the extensive comments at
  each check in `check.sh` itself for the specific deletion scenarios each guards against). Nothing
  computes them from the actual test manifest; anyone who adds or removes tests must edit
  these four numbers by hand, in the same commit, or the gate either fails for a change that was
  actually fine, or — worse, if a number is bumped without a corresponding test really having been
  added — quietly stops verifying that the count didn't shrink.

## Known limitations — the on-device harness

Found while building the on-device Display P3 harness (ARCHITECTURE.md §5.6). Each one will bite
anyone who tries the obvious thing next time.

- **On-device XCTest is impossible from a pure SPM package.** Running `OklchUITests` directly on
  a physical device via `xcodebuild test -destination 'platform=iOS,id=…'` fails at scheme
  resolution, before code signing is even attempted, verbatim:

  ```
  Cannot test target "OklchUITests" on "<device>": Tool-hosted testing
  is unavailable on device destinations. Select a host application for the test
  target, or use a simulator destination instead.
  ```

  SPM's plain `.testTarget` is tool-hosted — it runs as a bare executable invoked directly by the
  test runner. iOS device sandboxing does not permit that; on-device testing requires the test
  bundle to be injected into an installed, signed **host application**, which in turn requires an
  `.xcodeproj` (or an Xcode workspace with one), not a package target. This is exactly why
  `Tools/DeviceHarness/` exists as a small, hand-written, standalone SwiftUI app rather than a
  device-run XCTest suite: it is the host application the platform requires, doing the
  measurement itself (`ImageRenderer` readback -> stdout) instead of being tested by one.

- **Reading your Apple Development Team ID off the keychain identity string gives the WRONG
  value.** The keychain displays a signing identity as `Apple Development: YOUR NAME (XXXXXXXXXX)`.
  That parenthesised suffix looks exactly like a Team ID and is not one — it identifies the
  **certificate**, not the team. Passing it as `DEVELOPMENT_TEAM` produces a confusing
  `No Account for Team XXXXXXXXXX` failure, which reads like a missing Apple ID sign-in rather
  than a wrong constant, and sends you off re-authenticating Xcode instead of fixing the value.
  The authoritative source is the `TeamIdentifier` field inside an actual `.mobileprovision`:

  ```bash
  security cms -D -i <profile>.mobileprovision | plutil -extract TeamIdentifier xml1 -o - -
  ```

  The ten-character string that returns is the one that signs successfully against
  `iOS Team Provisioning Profile: *` with `CODE_SIGN_STYLE=Automatic`. The certificate suffix does
  not. Supply it via `OKLCH_DEVELOPMENT_TEAM` (see `Tools/run-ondevice-evidence.sh`) —
  `DeviceHarness.xcodeproj` deliberately commits an empty `DEVELOPMENT_TEAM` rather than one
  contributor's, so Xcode prompts you to pick your own team instead of failing against a stranger's.

- **Provisioning profiles live at `~/Library/Developer/Xcode/UserData/Provisioning Profiles/` on
  this Xcode (26.6), not the legacy `~/Library/MobileDevice/Provisioning Profiles/`.** Checking
  only the legacy path reports "no profiles" when profiles genuinely exist at the newer location —
  a false negative that looks identical to an actual missing-profile failure.

- **`xcrun devicectl device process launch --console` hangs after printing all expected output.**
  It prints "Waiting for the application to terminate…" and does not return control even after the
  app has finished writing everything it needs to stdout, because the console stream stays attached
  until the process actually exits (which the harness app, by design, does not do on its own).
  `Tools/run-ondevice-evidence.sh` wraps the call in `timeout 90 … ` and treats exit code `124`
  (the timeout firing) as the expected, successful outcome — distinguished from a real launch
  failure by checking that the expected `DEVICE-EVIDENCE ` line count was actually captured before
  the timeout hit, not by exit code alone.
