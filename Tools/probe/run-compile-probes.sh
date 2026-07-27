#!/bin/bash
# Tools/probe/run-compile-probes.sh
# Runs the compile-time probes and writes JSON evidence.
# A probe "passes" if it typechecks. Neither outcome is a script failure —
# the ANSWER is the deliverable, so we record it either way.
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$DIR/../.." && pwd)"
SDK="$(xcrun --show-sdk-path)"
TARGET="arm64-apple-macos14.0"
OUT="$REPO/docs/evidence/2026-07-25-compile-probes.json"
mkdir -p "$(dirname "$OUT")"

typecheck() {
    xcrun swiftc -typecheck -sdk "$SDK" -target "$TARGET" "$1" 2>"$1.log"
}

typecheck "$DIR/compile/A1_ColorResolvedShapeStyle.swift" && A1=true || A1=false
typecheck "$DIR/compile/A2a_ContrastSettable.swift"       && A2A=true || A2A=false

cat > "$OUT" <<JSON
{
  "probe_set": "compile",
  "date": "2026-07-25",
  "xcode": "$(xcodebuild -version | head -1)",
  "swift": "$(swift --version 2>&1 | head -1)",
  "sdk": "$SDK",
  "target": "$TARGET",
  "a1_color_resolved_is_shapestyle": $A1,
  "a2a_contrast_settable": $A2A
}
JSON

echo "A1 Color.Resolved: ShapeStyle    = $A1"
echo "A2a colorSchemeContrast settable = $A2A"
echo "wrote $OUT"
