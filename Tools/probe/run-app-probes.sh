#!/bin/bash
# Tools/probe/run-app-probes.sh [simulator-name] [runtime-label] [device-label]
#
# Runs the full runtime probe suite twice — Increase Contrast off, then on —
# and collects every EVIDENCE line into one JSON array.
#
# Defaults to the iOS 26.5 probe device. Pass arguments to target another
# runtime; ARCHITECTURE.md §3.3 declares an iOS 17 floor, so that runtime is measured too
# and gets its own evidence file rather than being assumed equivalent.
#
#   ./run-app-probes.sh                                             # iOS 26.5
#   ./run-app-probes.sh oklch-probe-ios17 "iOS 17.0" "iPhone 15 Pro"
#
# Deviations from the plan, all forced by observed behaviour:
#   - Scheme is OklchProbe-Package, the name SPM actually generates.
#     `xcodebuild -list` is the authority; the plan's `OklchProbe` does not exist.
#   - Destinations are resolved to a UDID. Once two iOS runtimes are installed,
#     `name=` matching fails and xcodebuild reports an unrelated tvOS/visionOS
#     error that does not name the real cause.
#   - The simulator is booted defensively before each run. Devices were observed
#     shutting down between runs, which fails simctl with CoreSimulator 405.
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$DIR/../.." && pwd)"

SIM="${1:-oklch-probe}"
RUNTIME_LABEL="${2:-iOS 26.5}"
DEVICE_LABEL="${3:-iPhone 17 Pro}"

SCHEME="OklchProbe-Package"
SLUG="$(echo "$RUNTIME_LABEL" | tr -d ' ' | tr '[:upper:]' '[:lower:]')"
if [ "$SIM" = "oklch-probe" ]; then
    OUT="$REPO/docs/evidence/2026-07-25-app-probes.json"
else
    OUT="$REPO/docs/evidence/2026-07-25-app-probes-$SLUG.json"
fi
mkdir -p "$(dirname "$OUT")"

UDID="$(xcrun simctl list devices -j \
    | python3 -c "
import json,sys
d=json.load(sys.stdin)
for runtime, devs in d['devices'].items():
    for dev in devs:
        if dev['name'] == '$SIM':
            print(dev['udid']); raise SystemExit
")"

if [ -z "$UDID" ]; then
    echo "ERROR: no simulator named '$SIM'" >&2
    exit 1
fi

run_suite() {  # $1 = enabled|disabled
    xcrun simctl bootstatus "$UDID" -b >/dev/null 2>&1 || xcrun simctl boot "$UDID" >/dev/null 2>&1
    xcrun simctl ui "$UDID" increase_contrast "$1" >/dev/null 2>&1
    (cd "$DIR" && xcodebuild test \
        -scheme "$SCHEME" \
        -destination "platform=iOS Simulator,id=$UDID" 2>&1) \
      | grep '^EVIDENCE ' | sed "s/^EVIDENCE /  /" \
      | sed "s/^  {/  {\"contrast_setting\":\"$1\",/"
}

{
    echo "{"
    echo "  \"probe_set\": \"runtime\","
    echo "  \"date\": \"2026-07-25\","
    echo "  \"xcode\": \"$(xcodebuild -version | head -1)\","
    echo "  \"runtime\": \"$RUNTIME_LABEL\","
    echo "  \"device\": \"$DEVICE_LABEL\","
    echo "  \"simulator_udid\": \"$UDID\","
    echo "  \"measurements\": ["
    { run_suite disabled; run_suite enabled; } | paste -sd, -
    echo "  ]"
    echo "}"
} > "$OUT"

echo "wrote $OUT"
python3 -c "import json;json.load(open('$OUT'));print('valid JSON')"
