# ADR-0005 — Gamut-map each candidate before measuring contrast

**Status:** Accepted
**Relates to:** [ARCHITECTURE §4.5](../ARCHITECTURE.md#45-contrast-solving)

## Context

Solving for contrast means bisecting on lightness until a candidate colour hits a target APCA Lc or
WCAG ratio against a backdrop. Each iteration must measure the contrast of a candidate. There are
two possible orders:

**Measure, then map.** Measure contrast on the raw OKLCH candidate, then gamut-map the winner once
at the end. Cheaper — one gamut map per solve instead of one per iteration.

**Map, then measure.** Gamut-map every candidate, and measure contrast on the mapped result.

The first order is wrong in a way that is easy to miss. A high-chroma candidate can sit outside the
destination gamut, and gamut mapping reduces chroma to bring it in — which changes its luminance,
which changes its contrast. So the solver converges on a target using a colour that will not exist
by the time it is drawn. The colour that *is* drawn misses the target.

This is precisely the defect class the package exists to prevent, and a version of it was found in
a shipping package during the survey (`B4`: a ΔE_OK guard round-tripping a clipped candidate through
the wrong gamut's conversion).

## Decision

Gamut-map first, measure contrast on the mapped colour. Every iteration. The candidate that the
solver evaluates is bit-for-bit the candidate that gets drawn.

## Consequences

**Gained.** `achieved >= requested` means what it says: it holds for the colour that reaches the
screen, not for an intermediate that never does. Tier-4 tests assert it across a grid of backdrops
and hues.

**Cost — the composed function is not strictly monotone.** Contrast is monotone in luminance on each
side of the backdrop, so bisection on lightness is stable in principle. But chroma reduction
perturbs luminance, so mapping composed with measurement is not strictly monotone, and bisection has
no formal convergence guarantee.

The perturbation is **not** negligible. CSS Color 4's gamut-mapping algorithm bounds its own error
at one JND (ΔE_OK < 0.02), and `P-TOL-6` measured a worst-case proxy of `0.01944706978379128` —
essentially *at* the bound. The correct characterisation is that the perturbation is bounded at
roughly one JND, not that it is small.

Non-strict monotonicity is therefore accepted rather than argued away, and handled with a hard
iteration cap plus a best-effort return (see
[ADR-0006](0006-report-unreachable-targets-rather-than-throw.md)) instead of a claim of exactness.

**Cost — one gamut map per iteration.** Bounded by the iteration cap. Scalar maths, so small in
absolute terms, but it is the price of the guarantee.

## Revisit if

A closed-form or provably-monotone formulation of "lightness that achieves target contrast after
gamut mapping" becomes available — which would let the solver keep the guarantee without bisecting.
