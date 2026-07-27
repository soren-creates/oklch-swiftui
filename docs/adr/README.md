# Decision records

One file per architectural decision that is expensive to reverse. Format is a trimmed
[MADR](https://adr.github.io/madr/): context, decision, consequences, and what would make us
revisit it.

These are **immutable once accepted**. A decision that changes gets a new record that supersedes
the old one, rather than an edit — so the reasoning available at the time stays legible.

[`../ARCHITECTURE.md`](../ARCHITECTURE.md) describes what the design *is*. These records say why,
and what was given up.

| # | Decision | Status |
|---|---|---|
| [0001](0001-resolve-late-not-at-construction.md) | Resolve colours at `resolve(in:)`, not at construction | Accepted |
| [0002](0002-split-core-from-swiftui-layer.md) | Split platform-free maths from the SwiftUI layer | Accepted |
| [0003](0003-own-colorgamut-environment-key.md) | Declare our own `\.colorGamut` environment key | Accepted |
| [0004](0004-couple-background-drawing-to-publication.md) | Couple background drawing to background publication | Accepted |
| [0005](0005-gamut-map-before-measuring-contrast.md) | Gamut-map each candidate before measuring contrast | Accepted |
| [0006](0006-report-unreachable-targets-rather-than-throw.md) | Report unreachable contrast targets; never throw or clamp silently | Accepted |
| [0007](0007-build-new-rather-than-fork.md) | Build new rather than fork an existing package | Accepted |
