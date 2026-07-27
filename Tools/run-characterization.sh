#!/bin/bash
# Tools/run-characterization.sh [simulator-name]
#
# colorSchemeContrast is a read-only KeyPath (pin P-ENV-1), so it cannot be
# varied in-process. This runs the characterization suite once per system
# setting and asserts the two runs produced DIFFERENT resolved colours.
#
# A run where both settings produce the same colour means Increase Contrast is
# not reaching resolve(in:) — the failure probe A2 was designed to
# detect, and the architecture's load-bearing assumption.
#
# This is also the ONLY thing that exercises CharacterizationTests against a
# real simulator with the real system setting, so it must be a complete
# tier-5 gate, not just a contrast-delta check: each pass's xcodebuild run
# must itself have succeeded (all three characterization tests green), not
# merely have produced a CHARACTERIZATION line. -only-testing runs all three
# tier-5 tests per pass, so a failure in either of the other two must fail
# the runner too.
#
# KNOWN COVERAGE GAP: this runner exercises LIGHT mode only — the simulator
# boots in light mode, so the contrast toggle moves `light` -> `lightIncreased`.
# `dark` and `darkIncreased` are NEVER exercised here; those branches of
# Variants.select are covered only by ResolveTests' unit tests, not
# end-to-end. Closing this would need a second axis in the pass matrix (dark x
# contrast-off/on, i.e. four passes) plus forcing dark mode via
# `xcrun simctl ui <device> appearance dark`.
set -uo pipefail

SIM="${1:-oklch-probe}"
UDID="$(xcrun simctl list devices -j | python3 -c "
import json,sys
d=json.load(sys.stdin)
for _, devs in d['devices'].items():
    for dev in devs:
        if dev['name'] == '$SIM':
            print(dev['udid']); raise SystemExit
")"
if [ -z "$UDID" ]; then echo "ERROR: no simulator named '$SIM'" >&2; exit 1; fi

# Runs the suite once, with the given Increase Contrast setting. Prints the
# CHARACTERIZATION line (if any) to stdout and returns non-zero if the
# xcodebuild invocation did not fully succeed — checked via both its exit
# status and "** TEST SUCCEEDED **", so a failure of
# testColorSchemeChangesTheResolvedColour or testColorGamutChangesTheResolvedColour
# (which emit no CHARACTERIZATION line of their own) cannot be swallowed by
# grep/head's exit status the way piping directly into them would.
run_pass() {  # $1 = enabled|disabled
    xcrun simctl bootstatus "$UDID" -b >/dev/null 2>&1 || xcrun simctl boot "$UDID" >/dev/null 2>&1
    xcrun simctl ui "$UDID" increase_contrast "$1" >/dev/null 2>&1

    local log
    log="$(mktemp)"
    xcodebuild test -scheme oklch-swiftui-Package \
        -only-testing:OklchUITests/CharacterizationTests \
        -destination "platform=iOS Simulator,id=$UDID" > "$log" 2>&1
    local xcode_status=$?

    grep '^CHARACTERIZATION ' "$log" | head -1

    if [ "$xcode_status" -ne 0 ] || ! grep -q '\*\* TEST SUCCEEDED \*\*' "$log"; then
        echo "xcodebuild test did not succeed for pass '$1' (exit $xcode_status):" >&2
        grep -E ': error:|Failing tests:' "$log" >&2
        rm -f "$log"
        return 1
    fi
    rm -f "$log"
    return 0
}

# Compares two CHARACTERIZATION lines' resolved RGB using the same tolerance
# CharacterizationTests.swift uses for its own in-process assertions
# (P-TOL-1: Color.Resolved is Float32-backed). Exact equality would treat a
# sub-tolerance nudge as "changed" here while the tests call the identical
# pair "unchanged" — the two halves of one claim must share a predicate.
# Ignores `contrast_seen` and `probe`: those only echo request metadata, not
# resolve(in:)'s output, and always differ between the two passes regardless
# of whether the colour itself moved.
# Exit 0 = differs (beyond tolerance), 1 = does not differ, 2 = parse error.
rgb_differs() {  # $1 = OFF line, $2 = ON line
    python3 -c "
import json, sys
tolerance = 5.9604644775390625e-08
prefix = 'CHARACTERIZATION '
def rgb(line):
    payload = line[len(prefix):] if line.startswith(prefix) else line
    d = json.loads(payload)
    return d['resolved_red'], d['resolved_green'], d['resolved_blue']
try:
    a = rgb(sys.argv[1])
    b = rgb(sys.argv[2])
except Exception as e:
    print(f'parse error: {e}', file=sys.stderr)
    sys.exit(2)
sys.exit(0 if any(abs(x - y) > tolerance for x, y in zip(a, b)) else 1)
" "$1" "$2"
}

OFF="$(run_pass disabled)"
OFF_STATUS=$?
ON="$(run_pass enabled)"
ON_STATUS=$?
xcrun simctl ui "$UDID" increase_contrast disabled >/dev/null 2>&1

echo "contrast off: $OFF"
echo "contrast on:  $ON"

if [ "$OFF_STATUS" -ne 0 ] || [ "$ON_STATUS" -ne 0 ]; then
    echo "FAIL: CharacterizationTests did not fully pass in one or both runs — see xcodebuild output above." >&2
    exit 1
fi
if [ -z "$OFF" ] || [ -z "$ON" ]; then
    echo "FAIL: a pass produced no CHARACTERIZATION line" >&2
    exit 1
fi

rgb_differs "$OFF" "$ON"
CMP_STATUS=$?
if [ "$CMP_STATUS" -eq 2 ]; then
    echo "FAIL: could not parse resolved RGB from a CHARACTERIZATION line" >&2
    exit 1
fi
if [ "$CMP_STATUS" -ne 0 ]; then
    echo "FAIL: Increase Contrast did not change the resolved colour." >&2
    echo "      Either the style has no increased-contrast variant, or the" >&2
    echo "      setting is not reaching resolve(in:) — see pin P-ENV-1." >&2
    exit 1
fi
echo "PASS: contrast setting changes the resolved colour"
