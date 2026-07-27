# ADR-0002 — Split platform-free maths from the SwiftUI layer

**Status:** Accepted
**Relates to:** [ARCHITECTURE §4.1](../ARCHITECTURE.md#41-oklchcore--pure-values-no-platform-dependencies)

## Context

Every surveyed package conflates colour maths with platform types. Conversions take or return
`Color`, `UIColor`, or `CGColor`; gamut mapping reaches for `CGColorSpace`. The consequences show
up in their test suites, which are thin — testing maths through a `UIColor` requires a simulator, a
render, or both, so most of the maths simply goes untested.

That conflation also makes the maths unusable anywhere else: a CLI that exports design tokens, a
server-side theme generator, or a Linux CI job cannot link a library that imports UIKit.

## Decision

Two modules with a one-way dependency:

- **`OklchCore`** imports no SwiftUI, no UIKit, no AppKit, no CoreGraphics, and no Foundation —
  only the standard library, plus `Darwin`/`Glibc`/`Musl` for `libm`. It holds `Oklch`, `Gamut`,
  gamut mapping, interpolation, contrast measurement, and the contrast solver.
- **`OklchUI`** imports SwiftUI and depends on `OklchCore`. It holds `OklchStyle`, the environment
  keys, and the modifiers.

`OklchCore` must never gain a dependency on `OklchUI`. Two things enforce this rather than a
convention: `check.sh`'s public-API-surface diff, and the fact that `OklchCore` is built and tested
on Linux, where SwiftUI does not exist.

Notably, the **contrast solver lives in `OklchCore`, not `OklchUI`**, even though contrast solving
feels like a UI concern. The solve is pure maths — resolve a backdrop, bisect on lightness,
gamut-map each candidate — and putting it in the platform layer would make its central invariant
(`achieved >= requested`) untestable without a simulator.

## Consequences

**Gained.** The maths is tested at speed with no simulator: 52 tests run on both macOS and Linux.
The Linux build is not decoration — it is the mechanism that makes the layering violation
impossible to commit by accident.

**Gained, unexpectedly.** Verifying on Linux surfaced a real portability bug. The Swift Static
Linux SDK exposes a `Musl` module rather than `Glibc`, so the original two-way
`#if canImport(Darwin) / #else Glibc` guard was wrong for a supported configuration. It is now a
genuine three-way split. No amount of macOS testing would have found that.

**Cost — some duplication at the seam.** `OklchUI` restates a small amount of surface (targets,
directions) to keep `OklchCore` free of SwiftUI's vocabulary.

**Cost — no Foundation.** Excluding Foundation from `OklchCore` costs conveniences a colour library
would otherwise reach for casually, string formatting and `Codable` among them. The fixture loader
lives on the test side for exactly this reason.

## Revisit if

A platform-free `Color`-equivalent lands in the standard library or in a Swift-blessed
cross-platform graphics package, making the seam unnecessary.
