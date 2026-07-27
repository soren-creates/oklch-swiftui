# ADR-0004 — Couple background drawing to background publication

**Status:** Accepted
**Relates to:** [ARCHITECTURE §4.4](../ARCHITECTURE.md#44-background-plumbing)

## Context

A contrast-solved foreground needs to know its backdrop. The obvious design is an environment value
callers set themselves:

```swift
.environment(\.themeBackground, myBackdrop)   // rejected as the primary API
.background(myBackdrop)
```

Two statements, two sources of truth. Nothing keeps them in step. The failure mode is not a crash
or a compile error — it is a foreground colour solved for a backdrop that is not on screen,
producing text that reports 4.5:1 contrast and is in fact unreadable.

That is worse than having no backdrop information at all. With no backdrop, a caller knows they must
supply one. With a stale backdrop, everything looks fine, tests pass against the published value,
and the bug ships. A lying backdrop is the single most dangerous state this package can be in,
because the whole point is to be trustworthy about contrast.

## Decision

Drawing and publishing are one modifier:

```swift
extension View {
    /// Fills the background AND publishes it to \.themeBackground.
    public func oklchBackground(_ style: OklchStyle) -> some View
}
```

One call site. The environment cannot disagree with the pixels, because the same argument produces
both. The coupling is the design, not an implementation detail.

`\.themeBackground` remains readable, and settable directly for cases where the backdrop genuinely
is not drawn by this package (an image, a material, a parent's fill). That escape hatch exists, but
it is not the path of least resistance.

## Consequences

**Gained.** The dangerous state is unreachable through the primary API. A caller who uses
`oklchBackground` cannot desynchronise drawing from publication — not because they are careful, but
because there is only one argument.

**Cost — less compositional.** A caller who wants to publish a backdrop *without* drawing it, or
draw one without publishing, has to reach for the environment key directly. That is a real
limitation for anyone layering materials or images behind text.

**Cost — one modifier does two things.** It reads as a violation of single-responsibility, and a
reviewer unfamiliar with the reasoning will flag it. Hence this record.

**Verified, not assumed.** Tests assert that `oklchBackground` publishes exactly what it draws, and
that a `.contrasting` style resolves against that published value. Three of them need a hosted
`UIWindow` and therefore run only under `xcodebuild test` in the simulator.

## Revisit if

A pattern emerges where publish-without-draw is common enough that the escape hatch becomes the
main path — at which point the honest move is a second, explicitly-named modifier rather than
loosening this one.
