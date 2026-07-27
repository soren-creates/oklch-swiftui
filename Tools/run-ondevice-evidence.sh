#!/bin/bash
# Tools/run-ondevice-evidence.sh — on-device P3 evidence (ARCHITECTURE.md §5.6).
#
# Builds, installs, and launches the DeviceHarness app on a physical iOS
# device, captures its DEVICE-EVIDENCE console lines, and writes the
# committed evidence file docs/evidence/2026-07-26-ondevice-p3.json.
#
# THE PROPERTY THAT MATTERS MOST: this script REFUSES TO WRITE on any
# failure. The final `cp` to the committed path is only reachable after the
# build, the install, the launch, AND the expected evidence-line count have
# all succeeded and the assembled JSON has been independently re-parsed. A
# wrapper that writes a partial or stale file manufactures fake evidence —
# this file is the ground truth every later claim rests on.
#
# Deliberately NOT `set -e`: the launch step's expected outcome is a
# `timeout`-induced kill (exit 124), which must be interpreted, not treated
# as an uncaught fatal error. Every step's exit status is checked explicitly
# instead.
set -uo pipefail

# Device and signing identity are supplied by the caller — nothing here is
# specific to the machine that captured the committed evidence. Both are
# REQUIRED and fail loudly when absent, rather than defaulting to a value that
# only works on one person's hardware.
UDID="${1:-${OKLCH_DEVICE_UDID:-}}"
TEAM="${OKLCH_DEVELOPMENT_TEAM:-${DEVELOPMENT_TEAM:-}}"
BUNDLE_ID="${OKLCH_BUNDLE_ID:-com.example.oklch.DeviceHarness}"
EXPECTED_LINES=3   # C2-smoke, C2-render-paths, C2-gradient-agreement

if [ -z "$UDID" ]; then
    echo "FAIL: no device UDID. Pass it as \$1 or set OKLCH_DEVICE_UDID." >&2
    echo "  List attached devices:  xcrun devicectl list devices" >&2
    exit 1
fi
if [ -z "$TEAM" ]; then
    echo "FAIL: no Apple Development Team ID. Set OKLCH_DEVELOPMENT_TEAM." >&2
    echo "  Read it from a provisioning profile's TeamIdentifier field:" >&2
    echo "    security cms -D -i <profile>.mobileprovision \\" >&2
    echo "      | plutil -extract TeamIdentifier.0 raw -o - -" >&2
    echo "  Do NOT use the parenthesised suffix of a keychain signing-identity" >&2
    echo "  string — that identifies the CERTIFICATE, not the team, and produces" >&2
    echo "  a misleading 'No Account for Team ...' error. See docs/survey.md." >&2
    exit 1
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# OKLCH_EVIDENCE_OUT lets a caller redirect the write target (check.sh's
# optional step uses this to capture into a scratch directory for a diff,
# rather than overwriting the committed file — see check.sh's OPTIONAL
# on-device step). It must keep the SAME BASENAME as the committed file: the
# capture date is derived from that basename (see CAPTURE_DATE below), and a
# renamed basename would silently produce a wrong date instead of failing.
OUT="${OKLCH_EVIDENCE_OUT:-$REPO_ROOT/docs/evidence/2026-07-26-ondevice-p3.json}"

LOG_DIR="$(mktemp -d "${TMPDIR:-/tmp}/ondevice-evidence.XXXXXX")"
BUILD_LOG="$LOG_DIR/build.log"
INSTALL_LOG="$LOG_DIR/install.log"
LAUNCH_LOG="$LOG_DIR/launch.log"
EVIDENCE_FILE="$LOG_DIR/evidence-lines.txt"
TMP_OUT="$LOG_DIR/evidence.json"

fail() {
    echo "FAIL: $1" >&2
    echo "Logs: $LOG_DIR" >&2
    exit 1
}

echo "=== 1/4 build ==="
(
  cd "$REPO_ROOT/Tools/DeviceHarness" && xcodebuild build \
    -project DeviceHarness.xcodeproj -scheme DeviceHarness \
    -destination "platform=iOS,id=$UDID" \
    -derivedDataPath ./build -allowProvisioningUpdates \
    DEVELOPMENT_TEAM="$TEAM" CODE_SIGN_STYLE=Automatic
) >"$BUILD_LOG" 2>&1
BUILD_STATUS=$?
[ $BUILD_STATUS -eq 0 ] || fail "build exited $BUILD_STATUS"
grep -q "BUILD SUCCEEDED" "$BUILD_LOG" || fail "build log missing BUILD SUCCEEDED"

APP="$REPO_ROOT/Tools/DeviceHarness/build/Build/Products/Debug-iphoneos/DeviceHarness.app"
[ -d "$APP" ] || fail "app bundle not found at $APP"

echo "=== 2/4 install ==="
xcrun devicectl device install app --device "$UDID" "$APP" >"$INSTALL_LOG" 2>&1
INSTALL_STATUS=$?
[ $INSTALL_STATUS -eq 0 ] || fail "install exited $INSTALL_STATUS"
grep -q "App installed" "$INSTALL_LOG" || fail "install log missing 'App installed' confirmation"

echo "=== 3/4 launch (console; a 90s timeout is EXPECTED — see header comment) ==="
timeout 90 xcrun devicectl device process launch --device "$UDID" --console "$BUNDLE_ID" \
    >"$LAUNCH_LOG" 2>&1
LAUNCH_STATUS=$?
# 0 = process launch reported clean exit. 124 = our timeout fired, which is
# the documented normal outcome of --console hanging on "Waiting for the
# application to terminate…" after all evidence has already been printed.
# Anything else is a real failure of the launch step.
if [ $LAUNCH_STATUS -ne 0 ] && [ $LAUNCH_STATUS -ne 124 ]; then
    fail "launch exited $LAUNCH_STATUS (neither clean exit nor expected timeout)"
fi

echo "=== 4/4 extract + assemble + validate ==="
grep -o 'DEVICE-EVIDENCE .*' "$LAUNCH_LOG" | sed 's/^DEVICE-EVIDENCE //' > "$EVIDENCE_FILE"
COUNT=$(wc -l < "$EVIDENCE_FILE" | tr -d ' ')
[ "$COUNT" -eq "$EXPECTED_LINES" ] || fail "expected $EXPECTED_LINES DEVICE-EVIDENCE lines, got $COUNT"

XCODE_VERSION="$(xcodebuild -version | head -1)"
SWIFT_VERSION="$(swift --version 2>&1 | grep -m1 'Apple Swift version')"

# WHAT IDENTIFIES THE DEVICE, AND WHY IT IS NOT THE UDID. An earlier version of
# this script recorded `device_udid`. A UDID is useless to a reader — it is an
# opaque per-unit serial that nobody else can reproduce, act on, or compare
# against — while being a hardware identifier of one person's phone. Model,
# product type and OS build are what a replicator actually needs in order to
# know what to reproduce this on, and they are stable for a given device, so the
# byte-for-byte reproducibility this script guarantees still holds.
#
# `deviceProperties.name` is deliberately NOT recorded: it is a user-chosen
# device name and typically contains the owner's name.
DEVICE_INFO_JSON="$LOG_DIR/device-info.json"
xcrun devicectl device info details --device "$UDID" \
    --json-output "$DEVICE_INFO_JSON" >/dev/null 2>&1 \
    || fail "could not read device details for $UDID via xcrun devicectl"

# Tab-separated, because marketing names contain spaces ("iPhone 14").
DEVICE_FIELDS="$(python3 - "$DEVICE_INFO_JSON" <<'PYEOF'
import json, sys
r = json.load(open(sys.argv[1]))["result"]
hw, dp = r["hardwareProperties"], r["deviceProperties"]
print("\t".join([hw["marketingName"], hw["productType"],
                 f'{hw["platform"]} {dp["osVersionNumber"]} ({dp["osBuildUpdate"]})']))
PYEOF
)" || fail "could not parse device details JSON for $UDID"
IFS=$'\t' read -r DEVICE_MODEL DEVICE_PRODUCT_TYPE DEVICE_OS <<<"$DEVICE_FIELDS"
[ -n "$DEVICE_MODEL" ] && [ -n "$DEVICE_PRODUCT_TYPE" ] && [ -n "$DEVICE_OS" ] \
    || fail "device details missing marketingName/productType/OS fields"
# The `date` field is derived from the OUTPUT FILENAME, not from `date -u`.
# Why this matters: the committed evidence file's name is pinned to the day
# it was captured (2026-07-26-ondevice-p3.json). If the JSON's `date` field
# instead came from `date -u` at run time, EVERY re-run on a later calendar
# day would write a different `date` into a file whose name still says
# 2026-07-26 — the evidence would drift its own checksum on every re-run,
# with no code change and no new information. That silently undermines the
# refuse-to-write guarantee this script exists to provide (see header
# comment): "refuse to write" is only meaningful if a clean re-run reproduces
# the committed file BYTE-FOR-BYTE. Deriving the date from the filename
# instead makes that reproducibility permanent rather than good-until-
# tomorrow.
OUT_BASENAME="$(basename "$OUT")"
CAPTURE_DATE="$(printf '%s' "$OUT_BASENAME" | sed -E 's/^([0-9]{4}-[0-9]{2}-[0-9]{2})-.*/\1/')"
[[ "$CAPTURE_DATE" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || \
    fail "could not derive a YYYY-MM-DD capture date from OUT's basename '$OUT_BASENAME'"

EXPECTED_PATH_KEYS="canvas,foreground,gradient,oklch_style,solid_fill"

python3 - "$EVIDENCE_FILE" "$TMP_OUT" "$XCODE_VERSION" "$SWIFT_VERSION" "$CAPTURE_DATE" \
         "$EXPECTED_PATH_KEYS" "$DEVICE_MODEL" "$DEVICE_PRODUCT_TYPE" "$DEVICE_OS" <<'PYEOF'
import json, sys

(evidence_path, out_path, xcode_version, swift_version, capture_date,
 expected_path_keys, device_model, device_product_type, device_os) = sys.argv[1:10]
expected_keys = set(expected_path_keys.split(","))

measurements = []
with open(evidence_path) as f:
    for line in f:
        line = line.strip()
        if not line:
            continue
        measurements.append(json.loads(line))

# Dropped-key guard: `paths["x"] = centrePixel(...)` in Measurement.swift assigns
# a [Double]?, and Swift dictionary-subscript assignment of `nil` REMOVES the
# key rather than storing null. A nil readback from any one render path
# (foreground, canvas, oklch_style, ...) therefore silently shrinks the
# "paths" dict instead of producing a visible null — and the DEVICE-EVIDENCE
# *line* count (checked above as EXPECTED_LINES) does not change, so that
# check alone cannot catch it. Assert the actual path KEYS explicitly here,
# by name, and refuse to write if any are missing.
render_paths_measurement = next(
    (m for m in measurements if m.get("probe") == "C2-render-paths"), None)
if render_paths_measurement is None:
    print("assembly check FAILED: no C2-render-paths measurement present", file=sys.stderr)
    sys.exit(1)
got_keys = set(render_paths_measurement.get("paths", {}).keys())
missing_keys = expected_keys - got_keys
if missing_keys:
    print(
        f"assembly check FAILED: C2-render-paths is missing path key(s) "
        f"{sorted(missing_keys)} (a nil centrePixel() readback silently drops "
        f"a dictionary key rather than storing null — see Measurement.swift). "
        f"Expected keys: {sorted(expected_keys)}. Got: {sorted(got_keys)}.",
        file=sys.stderr)
    sys.exit(1)

doc = {
    "probe_set": "device",
    "date": capture_date,
    "xcode": xcode_version,
    "swift": swift_version,
    "device_model": device_model,
    "device_product_type": device_product_type,
    "device_os": device_os,
    "capture_method": "xcrun devicectl device process launch --console via Tools/run-ondevice-evidence.sh",
    "measurements": measurements,
}

with open(out_path, "w") as f:
    json.dump(doc, f, indent=2, sort_keys=True)
    f.write("\n")
PYEOF
[ $? -eq 0 ] || fail "python3 assembly of evidence JSON failed (see message above — missing path keys refuse to write)"

python3 -c "import json; json.load(open('$TMP_OUT'))" || fail "assembled JSON failed to re-validate"

echo "=== writing $OUT ==="
mkdir -p "$(dirname "$OUT")"
cp "$TMP_OUT" "$OUT"
echo "OK: wrote $OUT ($COUNT measurements)"
exit 0
