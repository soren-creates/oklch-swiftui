# ADR-0001 — Resolve colours at `resolve(in:)`, not at construction

**Status:** Accepted
**Relates to:** [ARCHITECTURE §4.2](../ARCHITECTURE.md#42-oklchui--the-resolution-pipeline)

## Context

An OKLCH colour cannot be converted to a displayable RGB colour correctly without three facts that
are unknowable when the colour is written down in source:

1. **The destination gamut.** Whether the display is sRGB or Display P3 is a runtime property. A
   colour mapped for sRGB looks needlessly dull on a P3 panel; a colour that assumes P3 gets
   clamped, hue-shifted, or both on an sRGB one.
2. **The colour scheme and contrast setting.** Light/dark is knowable only at render time, and
   Increase Contrast can change while the app is running.
3. **The backdrop.** A foreground colour solved for contrast depends on what it lands on.

Every one of the twenty-plus surveyed Swift packages converts eagerly — in the initialiser, or in
a `var color: Color` computed the moment it is touched. By the time SwiftUI knows the answers, the
library has already discarded the inputs it needed.

SwiftUI has exposed `ShapeStyle.resolve(in: EnvironmentValues)` since iOS 17. It is called with the
resolved environment, at draw time, exactly when those three facts are available.

## Decision

`OklchStyle` stays in OKLCH internally and performs **all** conversion — variant selection, gamut
mapping, and any contrast solve — inside `resolve(in:)`.

Nothing about the display is captured at construction time. `Oklch` values in `OklchCore` are pure
data with no notion of a destination.

## Consequences

**Gained.** Correctness on wide-gamut displays; Increase Contrast support that no other surveyed
package has; contrast solving against the actual backdrop; and a core library that is trivially
testable because it has no environment.

**Cost — an iOS 17 floor.** `resolve(in:)` does not exist earlier. This rules out iOS 16 and below
entirely. It is the single largest constraint the design imposes and it is accepted deliberately:
the package's whole reason to exist is the thing that API enables.

**Cost — work at draw time.** Gamut mapping is a binary search, and a contrast solve is a
bisection on top of it. Both run during rendering rather than once upfront. Both are bounded by
hard iteration caps (§4.5), and both operate on scalars, so the cost is small — but it is not
zero, and a caller drawing thousands of independently-solved styles per frame would feel it.

**Cost — the environment must actually carry the inputs.** This design is worthless if SwiftUI does
not re-invoke `resolve(in:)` when the contrast setting changes. That was not documented anywhere,
so it was measured before any of this was built (`P-ENV-1`, [`../pins.md`](../pins.md)). Two
constraints fell out of that measurement and now bind the test suite: `ImageRenderer` does not
carry environment traits, and `colorSchemeContrast` is not settable in-process.

## Revisit if

Apple exposes display gamut as a first-class environment value and a resolved-colour API that
carries backdrop information — at which point parts of this could be handed back to the framework.
