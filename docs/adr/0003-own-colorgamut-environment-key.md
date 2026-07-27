# ADR-0003 — Declare our own `\.colorGamut` environment key

**Status:** Accepted
**Relates to:** [ARCHITECTURE §4.3](../ARCHITECTURE.md#43-why-colorgamut-is-our-own-environment-key)

## Context

Gamut mapping needs a destination gamut. SwiftUI's `EnvironmentValues` does not expose the display
gamut in any form — there is `colorScheme`, `colorSchemeContrast`, `displayScale`, but nothing for
sRGB versus Display P3.

The platform does expose it outside SwiftUI: `UITraitCollection.current.displayGamut` on iOS,
`NSScreen.canRepresent(.p3)` on macOS.

An earlier draft of this design justified an injected key by claiming
`UITraitCollection.current` "is not dependably meaningful inside `resolve(in:)`". **That claim was
measured and is false** — the trait reports `P3` both inside and outside `resolve(in:)`, in
agreement. The original justification for this decision did not survive contact with evidence.

## Decision

Keep the injected `\.colorGamut` environment key, defaulting to a value detected once at first use
from the platform trait, and overridable with `.colorGamut(.sRGB)`.

The decision stands on two justifications that *do* hold, rather than the availability claim that
did not:

1. **Deterministic tests.** A test that asserts gamut-dependent behaviour must be able to state the
   gamut. Reading an ambient trait makes the same test pass or fail depending on which Mac runs it.
2. **External displays.** A P3 Mac driving an sRGB display: auto-detection reports the capability of
   one screen while the window may be on another. An app that knows better must be able to say so,
   or the library hands back colours the display cannot show.

## Consequences

**Gained.** Tier-5 characterization tests can assert that `resolve(in:)` output genuinely changes
with gamut, which is one of the three central architectural claims.

**Cost — a second source of truth.** The environment value and the hardware can disagree, and when
they do, the environment wins. That is intended, but it means a caller who overrides carelessly can
make things worse. Documented, not prevented.

**Cost — an API surface Apple may later duplicate.** If SwiftUI ships its own gamut environment
value, ours becomes redundant and awkwardly similar.

**Honest characterisation.** This is a convenience-and-testability choice, not a workaround for a
missing platform capability. Reading the trait directly would also work. The architecture document
says so explicitly, because the earlier, stronger claim was wrong and the record should not imply
we were forced into this.

## Revisit if

SwiftUI exposes display gamut in `EnvironmentValues`. Then default to theirs and keep ours only as
a test override, or drop it entirely.
