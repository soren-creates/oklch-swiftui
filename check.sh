#!/bin/bash
# ./check.sh — the all-green gate (ARCHITECTURE.md §6.1).
#
# Runs in order, failing fast. Green is required before any release tag.
#
# Deliberately NOT containerised: SwiftUI needs Apple hardware and a simulator,
# so Docker buys nothing here. Reproducibility comes from a pinned toolchain
# plus pinned node + Color.js for fixture regeneration.
#
# Eight steps, not six (ARCHITECTURE.md §6.1 lists six). Measured:
#   - `swift test` on macOS cannot run the tier-5 characterization tests at
#     all — they need UIKit and SKIP. With `contrast: .standard` hardcoded
#     inside resolve(in:) (breaking the package's central claim), `swift
#     test` still reports 0 failures, exit 0.
#   - A single `xcodebuild test` simulator pass does not catch that mutation
#     either: all three tier-5 tests still PASS under it.
#   - Only Tools/run-characterization.sh, which runs the suite twice with
#     simctl toggling Increase Contrast between passes and diffs the
#     resolved colour, catches it.
# So "OklchUITests" is split into 4a (host, with an explicit skip ceiling so
# an unbounded skip count can't quietly go hollow), 4b (simulator, the only
# place tier 5 executes), and 4c (the two-pass contrast probe, the only
# thing that actually exercises the claim end to end).
#
# There is a ninth, explicitly OPTIONAL step after step 8: on-device P3
# evidence (ARCHITECTURE.md §5.6). It is not numbered N/8 and never affects this
# script's exit code — no CI runner has a physical device attached, so it
# cannot be a required gate step. When no device is reachable it prints a
# visible SKIPPED line explaining why, rather than silently doing nothing.
set -euo pipefail

# Run from the repo root regardless of the caller's cwd.
cd "$(dirname "${BASH_SOURCE[0]}")"

step() { printf '\n=== %s ===\n' "$1"; }

command -v jq >/dev/null 2>&1 || {
    echo "FAIL: jq is required (step 6 uses it to normalise swift-api-digester output)." >&2
    exit 1
}

# All scratch files for this run live in one unpredictable directory rather
# than fixed /tmp/check-* names, which collide across concurrent runs and are
# guessable in a shared /tmp. Left in place (not trap-cleaned) so a failing
# step's full log is still there to read afterwards.
CHECK_TMP="$(mktemp -d "${TMPDIR:-/tmp}/oklch-check.XXXXXX")"
echo "check.sh scratch directory: $CHECK_TMP"

step "1/8 fixtures regenerate byte-identically"
cp Fixtures/colorjs/conversions.json "$CHECK_TMP/fixtures-before.json"
(cd Tools/gen-fixtures && npm install --silent && npm run --silent generate >/dev/null)
if ! diff -q "$CHECK_TMP/fixtures-before.json" Fixtures/colorjs/conversions.json >/dev/null; then
    echo "FAIL: regenerating fixtures changed them. Either the generator is" >&2
    echo "      non-deterministic or the committed file is stale." >&2
    exit 1
fi
echo "byte-identical"

step "2/8 build"
swift build

step "3/8 OklchCoreTests"
# Captured via `... || STATUS=$?` rather than a bare `swift test` piped
# straight to the terminal: under `set -e` a bare failing command aborts the
# script immediately, but capturing lets us assert the total count below
# (see the comment there) before deciding pass/fail, and always writes a full
# log even on success. `||` (not a raw pipe) is required: `set -e` does NOT
# abort on the left side of `cmd || handler`, whereas `VAR=$(cmd)` alone WOULD
# abort right there, before anything below it runs — measured during review:
# a failing test with the old code produced exit 1 and zero output.
CORE_STATUS=0
CORE_OUT="$(swift test --filter OklchCoreTests 2>&1)" || CORE_STATUS=$?
echo "$CORE_OUT" > "$CHECK_TMP/core-tests.log"
echo "$CORE_OUT" | tail -8
if [ "$CORE_STATUS" -ne 0 ]; then
    echo "FAIL: OklchCoreTests did not pass (exit $CORE_STATUS)." >&2
    echo "      Full log: $CHECK_TMP/core-tests.log" >&2
    exit 1
fi
# The skip ceiling below (step 4a) exists because an unbounded skip count is
# how a suite goes hollow — but a test can also just be DELETED, which keeps
# "0 failures" true and passes silently. Asserting the total test count too
# means a deleted (or accidentally-not-added) test fails the gate instead of
# vanishing unnoticed. 52 is the current OklchCoreTests count — if this
# assertion trips because you added/removed a test on purpose, update the
# number deliberately; do not delete this check.
EXPECTED_CORE_TOTAL=52
if ! echo "$CORE_OUT" | grep -q "Executed $EXPECTED_CORE_TOTAL tests, with 0 failures"; then
    echo "FAIL: expected exactly $EXPECTED_CORE_TOTAL OklchCoreTests, 0 failures." >&2
    echo "      A changed total means a test was added or removed — verify before adjusting." >&2
    echo "      Full log: $CHECK_TMP/core-tests.log" >&2
    exit 1
fi

step "4a/8 OklchUITests (host) — with a skip ceiling AND a total-count floor"
# `swift test` on macOS CANNOT run the tier-5 characterization tests: they need
# UIKit and skip. That is legitimate, but an unbounded skip count is how a
# suite goes hollow, so assert the number rather than trusting exit 0.
#
# Same capture-then-check reasoning as step 3 above: this MUST be `... ||
# HOST_STATUS=$?`, not a bare `HOST_OUT="$(swift test ...)"`. Measured during
# review: with the bare form, a broken host-run test made the whole script
# exit 1 having printed NOTHING beyond the "=== 4a/8 ===" banner — the
# `echo "$HOST_OUT"` below it never executed, because `set -e` fires on the
# failing command substitution itself, before this line is reached.
HOST_STATUS=0
HOST_OUT="$(swift test --filter OklchUITests 2>&1)" || HOST_STATUS=$?
echo "$HOST_OUT" > "$CHECK_TMP/host-tests.log"
echo "$HOST_OUT" | tail -8
if [ "$HOST_STATUS" -ne 0 ]; then
    echo "FAIL: OklchUITests (host) did not pass (exit $HOST_STATUS)." >&2
    echo "      Full log: $CHECK_TMP/host-tests.log" >&2
    exit 1
fi
# Asserting the FULL line — total AND skip count together — not just "with 4
# tests skipped": that clause alone still matches after a test is deleted
# (Executed 29 tests, with 4 tests skipped ... still contains "with 4 tests
# skipped"). Measured during review: deleting testLightSchemeUsesBase from
# ResolveTests.swift left this gate green under the old, skip-only check.
# 33 total / 6 skipped (3 tier-5 CharacterizationTests +
# 3 BackgroundTests cases requiring a hosted hierarchy — including the two
# added later for the previously-untested dark-scheme
# and .contrasting-background publish paths — all UIKit-only) are current,
# measured counts. The total rose from 31 to 33 in a later fix wave
# (later review): two new host-runnable tests in ContrastingTests.swift
# — the backdrop-gamut-mapping regression test and the
# no-op-pin test for `.dark()`/`.increasedContrast()` on a `.contrasting`
# style — neither needs a hosted hierarchy, so the skip count is unchanged. If
# this trips on a further deliberate change, update both numbers; do not
# delete the check.
EXPECTED_HOST_TOTAL=33
EXPECTED_SKIPS=6
if ! echo "$HOST_OUT" | grep -q "Executed $EXPECTED_HOST_TOTAL tests, with $EXPECTED_SKIPS tests skipped and 0 failures"; then
    echo "FAIL: expected exactly $EXPECTED_HOST_TOTAL OklchUITests on the host, $EXPECTED_SKIPS skipped, 0 failures." >&2
    echo "      A changed total or skip count means coverage moved — verify before adjusting." >&2
    echo "      Full log: $CHECK_TMP/host-tests.log" >&2
    exit 1
fi

step "4b/8 OklchUITests (simulator) — the only place tier 5 executes"
# testColorSchemeChangesTheResolvedColour and testColorGamutChangesTheResolvedColour
# do not run at all under `swift test`. Without this step they are never executed.
#
# Captured via `... || SIM_STATUS=$?` for the same reason as steps 3/4a — the
# previous version piped `xcodebuild test` straight into `tee | grep`, so
# under `set -e`+`pipefail` a failure (or even an unreachable simulator name)
# aborted the whole script with NO message at all: the actual xcodebuild
# error text (e.g. "Unable to find a device matching the provided destination
# specifier") went only to the tee'd log, which nothing ever printed or even
# named. Measured: `OKLCH_SIM=no-such-simulator-xyz ./check.sh` exited 1 with
# output ending at the "=== 4b/8 ===" banner and nothing else.
SIM_STATUS=0
SIM_OUT="$(xcodebuild test -scheme oklch-swiftui-Package \
    -only-testing:OklchUITests \
    -destination "platform=iOS Simulator,name=${OKLCH_SIM:-oklch-probe}" 2>&1)" || SIM_STATUS=$?
echo "$SIM_OUT" > "$CHECK_TMP/sim-tests.log"
echo "$SIM_OUT" | grep -E "Executed .* tests|\*\* TEST|error:" | tail -8 || true
if [ "$SIM_STATUS" -ne 0 ] || ! echo "$SIM_OUT" | grep -q '\*\* TEST SUCCEEDED \*\*'; then
    echo "FAIL: simulator run of OklchUITests did not succeed (exit $SIM_STATUS)." >&2
    echo "      Full log: $CHECK_TMP/sim-tests.log" >&2
    exit 1
fi
# Same rationale as step 4a's total: a deleted test would otherwise still
# report 0 failures and TEST SUCCEEDED. 33 is the current total (all 33 run
# for real here — none skip in the simulator). Update deliberately; do not
# delete the check.
EXPECTED_SIM_TOTAL=33
if ! echo "$SIM_OUT" | grep -q "Executed $EXPECTED_SIM_TOTAL tests, with 0 failures"; then
    echo "FAIL: expected exactly $EXPECTED_SIM_TOTAL OklchUITests to run in the simulator, 0 failures." >&2
    echo "      A changed total means a test was added or removed — verify before adjusting." >&2
    echo "      Full log: $CHECK_TMP/sim-tests.log" >&2
    exit 1
fi

step "4c/8 characterization two-pass contrast probe"
# The ONLY thing in this repo that catches a `contrast: .standard` hardcode
# inside resolve(in:). A single simulator pass does not: all three tier-5 tests
# still pass under that mutation. Must be its own step with its own exit check.
./Tools/run-characterization.sh "${OKLCH_SIM:-oklch-probe}"

step "5/8 DocC"
# `swift package generate-documentation` does not work in this repo: there is
# no swift-docc-plugin dependency in Package.swift and
# `swift package plugin --list` is empty (verified). The command
# that does work is `xcodebuild docbuild`, which drives DocC through the
# Xcode toolchain directly and needs no plugin.
#
# Plain `xcodebuild docbuild` is NOT a gate on its own: DocC reports broken
# symbol links, duplicate technology roots, and malformed directives as
# WARNINGS, and xcodebuild's exit code and "BUILD DOCUMENTATION SUCCEEDED"
# banner do not reflect them (measured: an unresolved ``Symbol`` link and a
# duplicated module-root title both left exit 0 / SUCCEEDED). Passing
# `OTHER_DOCC_FLAGS=--warnings-as-errors` forwards docc's own
# --warnings-as-errors to the underlying `docc convert` invocation, which
# turns those warnings into a real "BUILD DOCUMENTATION FAILED" — verified
# against this repo's current docs, which are clean under it.
DOCC_STATUS=0
DOCC_OUT="$(xcodebuild docbuild -scheme oklch-swiftui-Package -destination 'platform=macOS' \
    OTHER_DOCC_FLAGS='--warnings-as-errors' 2>&1)" || DOCC_STATUS=$?
echo "$DOCC_OUT" > "$CHECK_TMP/docc.log"
echo "$DOCC_OUT" | tail -8
if [ "$DOCC_STATUS" -ne 0 ] || ! echo "$DOCC_OUT" | grep -q '\*\* BUILD DOCUMENTATION SUCCEEDED \*\*'; then
    echo "FAIL: DocC build did not succeed (exit $DOCC_STATUS)." >&2
    echo "      Full log: $CHECK_TMP/docc.log" >&2
    exit 1
fi

step "6/8 public API surface"
# swift-api-digester's SDK dump embeds its own invocation (including the -o
# path and SDK build number) inside the JSON under ABIRoot.tool_arguments.
# Left in, that field alone makes every run "differ" from the baseline —
# recorded with -o docs/api-baseline/$MODULE.json — even with zero API
# changes, because the current run's -o is a /tmp path. Strip it with jq
# before comparing so the diff reflects the actual public surface, not the
# invocation that produced it. (No other volatile content was found: no
# "location" fields — -avoid-location isn't even needed — and no other
# absolute paths appear in the dump.)
#
# -target uses the host's own architecture rather than a hardcoded
# "arm64-apple-macos14.0", so the gate also works on an Intel Mac. The
# baselines in docs/api-baseline were recorded on arm64 — see
# docs/api-baseline/README.md for the exact toolchain — so a cross-arch diff
# is a real (if unlikely) source of a step-6 failure that is not an API
# change; that README is what makes such a failure interpretable.
FAILED=0
for MODULE in OklchCore OklchUI; do
    swift build --target "$MODULE" >/dev/null
    RAW="$CHECK_TMP/api-$MODULE-raw.json"
    CURRENT="$CHECK_TMP/api-$MODULE.json"
    xcrun swift-api-digester -dump-sdk -module "$MODULE" -o "$RAW" \
        -I .build/debug/Modules -sdk "$(xcrun --show-sdk-path)" \
        -target "$(uname -m)-apple-macos14.0"
    jq 'del(.ABIRoot.tool_arguments)' "$RAW" > "$CURRENT"
    if ! diff -q "docs/api-baseline/$MODULE.json" "$CURRENT" >/dev/null; then
        echo "FAIL: $MODULE's public API differs from its recorded baseline." >&2
        diff "docs/api-baseline/$MODULE.json" "$CURRENT" | head -40 >&2
        echo "If the change is intended, re-record the baseline and say so in the commit." >&2
        FAILED=1
    fi
done
[ "$FAILED" -eq 0 ] || exit 1
echo "API surface unchanged"

step "OPTIONAL: on-device P3 evidence (ARCHITECTURE.md §5.6) — NOT part of the required gate"
# This is explicitly optional and can NEVER fail ./check.sh: it needs a physical Apple device with
# a Display P3 screen plugged in, which no CI runner has. It is deliberately not step "9/8" — the
# header comment above and every EXPECTED_* total in this file cover only the eight required
# steps, and this one adds no package tests (it touches docs, Tools/DeviceHarness/, and this
# comment — never Sources/, Tests/, or Package.swift).
#
# What must NOT happen is silence: if no device is attached, that has to be an explicit, visible
# line in the output, not an absent one — an omitted step reads as "forgotten," a printed skip
# reads as "deliberately optional and currently unmet."
#
# A GATE VERIFIES EVIDENCE, IT DOES NOT MUTATE IT: this step captures a fresh run into a scratch
# directory (via OKLCH_EVIDENCE_OUT) and diffs it against the committed evidence file — it never
# writes over docs/evidence/2026-07-26-ondevice-p3.json. Agreement is reported; drift is reported
# LOUDLY (to stderr) but still does not fail the gate, since re-capturing committed evidence is a
# deliberate, reviewed action, not something a gate run should do on its own.
#
# Device and team are read from the environment with no default. An earlier
# version defaulted to the UDID of the phone that captured the committed
# evidence, which meant this step announced "no physical device reachable at
# UDID 00008110-…" on every other machine on earth — naming hardware the reader
# does not have, and baking one contributor's device into a public gate.
DEVICE_UDID="${OKLCH_DEVICE_UDID:-}"
COMMITTED_EVIDENCE="docs/evidence/2026-07-26-ondevice-p3.json"
if [ -z "$DEVICE_UDID" ] || [ -z "${OKLCH_DEVELOPMENT_TEAM:-${DEVELOPMENT_TEAM:-}}" ]; then
    echo "SKIPPED (optional, does not fail ./check.sh): on-device P3 evidence needs both" >&2
    echo "  OKLCH_DEVICE_UDID and OKLCH_DEVELOPMENT_TEAM set, and a physical device attached." >&2
    echo "    xcrun devicectl list devices            # to find a UDID" >&2
    echo "    docs/survey.md                          # how to read the RIGHT team ID" >&2
    echo "  This is expected on CI and on any checkout without Apple hardware to hand." >&2
    echo "  Already-committed evidence: $COMMITTED_EVIDENCE" >&2
    echo "  (see docs/evidence/2026-07-26-ondevice-p3-findings.md)." >&2
elif xcrun devicectl device info details --device "$DEVICE_UDID" >/dev/null 2>&1; then
    echo "Device $DEVICE_UDID is reachable — running Tools/run-ondevice-evidence.sh to VERIFY (not overwrite) $COMMITTED_EVIDENCE."
    VERIFY_DIR="$CHECK_TMP/ondevice-verify"
    mkdir -p "$VERIFY_DIR"
    # Same basename as the committed file — required so the wrapper's own
    # date-from-filename derivation (see Tools/run-ondevice-evidence.sh)
    # reproduces the same `date` field; only the directory differs.
    VERIFY_OUT="$VERIFY_DIR/$(basename "$COMMITTED_EVIDENCE")"
    if OKLCH_EVIDENCE_OUT="$VERIFY_OUT" ./Tools/run-ondevice-evidence.sh "$DEVICE_UDID"; then
        if diff -q "$COMMITTED_EVIDENCE" "$VERIFY_OUT" >/dev/null; then
            echo "On-device P3 evidence: OK — fresh capture agrees byte-for-byte with $COMMITTED_EVIDENCE."
        else
            echo "DRIFT (optional, does not fail ./check.sh): fresh on-device capture differs from" >&2
            echo "  committed $COMMITTED_EVIDENCE. The committed file was NOT overwritten — a gate" >&2
            echo "  verifies evidence, it does not mutate it. Diff (committed vs. fresh):" >&2
            diff "$COMMITTED_EVIDENCE" "$VERIFY_OUT" >&2 || true
            echo "  Fresh capture retained for inspection: $VERIFY_OUT" >&2
        fi
    else
        echo "SKIPPED-ON-FAILURE (optional, does not fail ./check.sh): on-device evidence capture" >&2
        echo "  failed. See output above. Committed evidence is untouched: $COMMITTED_EVIDENCE." >&2
    fi
else
    echo "SKIPPED (optional, does not fail ./check.sh): OKLCH_DEVICE_UDID is set but no device" >&2
    echo "  answered 'xcrun devicectl device info details'. This step needs real Apple" >&2
    echo "  hardware attached and unlocked. Already-committed evidence:" >&2
    echo "  $COMMITTED_EVIDENCE (see docs/evidence/2026-07-26-ondevice-p3-findings.md)." >&2
fi

printf '\nALL GREEN\n'
