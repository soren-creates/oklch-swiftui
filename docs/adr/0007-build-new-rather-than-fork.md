# ADR-0007 — Build new rather than fork an existing package

**Status:** Accepted
**Relates to:** [ARCHITECTURE §2](../ARCHITECTURE.md#2-prior-art), [`../survey.md`](../survey.md)

## Context

Twenty-plus Swift packages already expose OKLCH. Writing another one needs justification, so all of
them were read at source level before any code was written. Six were plausible fork candidates; the
full table, with licences and per-package verdicts, is in [`../survey.md`](../survey.md).

The blocking findings:

- **Three of the six carry no licence at all.** Two of those three (`nikstar/swift-oklch`,
  `geonu1109/swift-color`) have real, usable-looking code. An unlicensed repository cannot legally
  be forked or vendored from regardless of code quality, so they were out on that basis alone.
- **The closest existing work is structurally eager.** `danielcr12/OKLCHKit` (MIT) has the best
  gamut mapping in the ecosystem, and still resolves at construction time — the one thing this
  design cannot accept ([ADR-0001](0001-resolve-late-not-at-construction.md)) — while carrying
  3,351 LOC of unrelated scope and a confirmed P3 correctness bug.
- **The maths that exists is small.** Ottosson's matrices and the CSS Color 4 gamut map are together
  roughly 100 LOC, both published specifications, both with reference fixtures available.

## Decision

Build new. Consult MIT-licensed prior art freely; copy no code without shipping its notice.

## Consequences

**Gained.** No inherited architecture to fight. The eager-resolution assumption is baked into the
type signatures of every candidate, so a fork's first commit would have been deleting most of it.

**Gained.** The survey's defects became the regression suite. `B1`–`B5` are five real bugs found in
shipping packages, each now a named test. Forking would have inherited some of them.

**Cost — no community, no battle-testing.** A fork of a 212-star package starts with users. This
starts with none, and every bug is ours.

**Cost — the maths is ours to get wrong.** Mitigated by validating against Color.js as an
independent oracle rather than by self-consistency (ARCHITECTURE §5.1). That mitigation earned its
keep: the fixture generator's stop-on-disagreement rule caught a real divergence between a
reference pseudocode listing and the published spec text, recorded as `P-TOL-4` in
[`../pins.md`](../pins.md).

**Attribution.** Vendored maths carries attribution in-file. No code has been copied from any
surveyed package; `OklchCore`'s gamut mapping was derived from the CSS Color 4 spec text directly.
If that ever changes, the relevant notice ships in `THIRD-PARTY-NOTICES.md`.

## Revisit if

Nothing plausible. This decision is spent — the code exists. Recorded so the question is not
relitigated from scratch by the next reader who notices twenty packages already do OKLCH.
