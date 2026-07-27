// Shared numeric literal for P-TOL-1 (docs/pins.md), so the bound is defined
// exactly once in this test target rather than copy-pasted.
//
// P-TOL-1: `Color.Resolved` is Float32-backed; `5.9604644775390625e-08` is
// `2^-24`, the half-ULP rounding bound for Float32 in `[0,1)` (measured,
// see docs/pins.md's P-TOL-1 section). `ResolveTests.swift`'s
// `resolvedTolerance` and `CharacterizationTests.swift`'s `tolerance` both
// alias this one constant rather than re-stating the literal, so a future
// re-measurement only has one place to change.
//
// Deliberately NOT unified with `Tools/run-characterization.sh`'s
// `rgb_differs`, which uses the identical literal for the same reason but
// out-of-process (bash, not Swift) — it genuinely cannot share this
// declaration and is documented there as a separate, intentional copy.
let resolvedFloat32Tolerance = 5.9604644775390625e-08
