#!/usr/bin/env bash
# CI pipeline for Anghkooey.
#
# Package tests run via `swift test` on macOS (all three packages declare
# .macOS(.v15), so no simulator is required and the loop is fast).
# The app target is built via xcodebuild against the iOS Simulator to
# verify the Xcode project and SwiftUI compilation.
set -euo pipefail

SIMULATOR="platform=iOS Simulator,name=iPhone 17,OS=26.0"
WORKSPACE_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED="$WORKSPACE_ROOT/.ci-derived-data"

echo "=== AnghkooeyCore tests ==="
(cd "$WORKSPACE_ROOT/Packages/AnghkooeyCore" && swift test)

echo "=== AnghkooeyIntelligence tests ==="
(cd "$WORKSPACE_ROOT/Packages/AnghkooeyIntelligence" && swift test)

echo "=== AnghkooeyUI tests ==="
(cd "$WORKSPACE_ROOT/Packages/AnghkooeyUI" && swift test)

echo "=== App target build ==="
xcodebuild build \
  -project "$WORKSPACE_ROOT/App/Anghkooey.xcodeproj" \
  -scheme Anghkooey \
  -destination "$SIMULATOR" \
  -configuration Debug \
  CODE_SIGNING_ALLOWED=NO \
  -derivedDataPath "$DERIVED"

echo ""
echo "✓ All checks passed"
