# ADR-0006 — Report unreachable contrast targets; never throw or clamp silently

**Status:** Accepted
**Relates to:** [ARCHITECTURE §4.6](../ARCHITECTURE.md#46-unreachable-contrast-targets)

## Context

Some contrast targets have no solution. APCA Lc 90 against a mid-grey backdrop at high chroma is not
achievable at *any* lightness — there is no colour that satisfies it. The solver will bisect, run
out of iterations, and hold something that misses the target.

Three ways to handle that, and two of them are bad:

**Throw or trap.** `resolve(in:)` cannot throw — `ShapeStyle` conformance does not allow it. A
precondition failure would crash an app in production because a designer picked an ambitious
contrast target against one backdrop. Refusing to draw a view because a colour is imperfect is a
worse outcome than drawing an imperfect colour.

**Return the best effort silently.** Never crashes, always draws. But it quietly ships the exact
failure this package exists to eliminate: a colour that claims a contrast guarantee it does not
meet. Worse than the eager-conversion libraries, because this one advertised the guarantee.

**Return the best effort, and make the shortfall observable.** Renders never break, and the miss is
detectable by anyone who looks.

## Decision

Resolution always returns the best achievable colour. The shortfall is published as a value:

```swift
public struct ContrastResolution: Sendable {
    public let requested: Double
    public let achieved: Double
}
```

A `\.oklchDiagnostics` handler receives every solve that falls short of its target. Callers can log
it, assert on it in tests, or ignore it. Tests assert on `achieved`, never on "it didn't crash".

## Consequences

**Gained.** A view body cannot break because of an ambitious contrast target. Simultaneously, a
contrast regression is catchable in CI: install a diagnostics handler that fails the test, and an
unreachable target becomes a test failure rather than a silent visual defect.

**Gained — the honest reporting channel.** `achieved` is a number, not a boolean. A caller can
decide that Lc 74 instead of Lc 75 is fine while Lc 40 is not. A thrown error would have collapsed
that into "failed".

**Cost — it is opt-in.** A caller who installs no handler gets the silent-best-effort behaviour,
which is the bad option above. The design makes the good path *available* and easy; it does not make
it mandatory. That is a deliberate trade against crashing, and it means "no diagnostics installed"
is a meaningful gap rather than a safe default.

**Cost — an extra environment key.** `\.oklchDiagnostics` is a second piece of plumbing a caller has
to learn about to get the full benefit.

## Revisit if

A compile-time or build-time mechanism becomes available to catch unreachable targets before they
render — a macro validating literal targets against literal backdrops would remove most of the need
for a runtime channel.
