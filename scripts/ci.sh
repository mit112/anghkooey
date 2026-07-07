#!/usr/bin/env bash
# CI pipeline for Anghkooey.
#
# Package tests run via `swift test` on macOS (all three packages declare
# .macOS(.v15), so no simulator is required and the loop is fast).
# The app target is built via xcodebuild against the iOS Simulator to
# verify the Xcode project and SwiftUI compilation.
set -euo pipefail

SIMULATOR="generic/platform=iOS Simulator"
TEST_SIMULATOR="platform=iOS Simulator,name=iPhone 17 Pro,OS=latest"
WORKSPACE_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED="$WORKSPACE_ROOT/.ci-derived-data"

echo "=== M1 forbidden-pattern check ==="
bash "$WORKSPACE_ROOT/scripts/tests/m1-forbidden-patterns-test.sh"
bash "$WORKSPACE_ROOT/scripts/m1-forbidden-patterns.sh"

echo "=== AnghkooeyCore tests ==="
(cd "$WORKSPACE_ROOT/Packages/AnghkooeyCore" && swift test)

echo "=== AnghkooeyIntelligence tests ==="
# TODO: Switch to xcodebuild once AnghkooeyIntelligence scheme is added in Xcode
# xcodebuild test \
#   -scheme AnghkooeyIntelligence \
#   -destination "$SIMULATOR" \
#   -resultBundlePath /tmp/anghkooey-m2.xcresult \
#   CODE_SIGNING_ALLOWED=NO \
#   -derivedDataPath "$DERIVED"
(cd "$WORKSPACE_ROOT/Packages/AnghkooeyIntelligence" && swift test)

echo "=== AnghkooeyUI tests ==="
(
  cd "$WORKSPACE_ROOT/Packages/AnghkooeyUI"
  xcodebuild test \
    -scheme AnghkooeyUI \
    -destination "$TEST_SIMULATOR" \
    -configuration Debug \
    CODE_SIGNING_ALLOWED=NO \
    -derivedDataPath "$DERIVED/ui-tests"
)

echo "=== App target test ==="
xcodebuild test \
  -project "$WORKSPACE_ROOT/App/Anghkooey.xcodeproj" \
  -scheme Anghkooey \
  -destination "$TEST_SIMULATOR" \
  -configuration Debug \
  CODE_SIGNING_ALLOWED=NO \
  -derivedDataPath "$DERIVED/app-tests"

echo "=== PrivacyInfo manifest check ==="
PBXPROJ="$WORKSPACE_ROOT/App/Anghkooey.xcodeproj/project.pbxproj"
for uuid in AA000001000000000000AA01 AA000001000000000000AA02 AA000001000000000000AA03; do
  grep -q "$uuid" "$PBXPROJ" || { echo "ERROR: PrivacyInfo file-ref $uuid missing from pbxproj — regenerate dropped a .xcprivacy (see #56)"; exit 1; }
done
# sanity: expect 12 total PrivacyInfo lines (4 per target × 3 targets)
count=$(grep -c "PrivacyInfo" "$PBXPROJ" || true)
[ "$count" -eq 12 ] || { echo "ERROR: expected 12 PrivacyInfo lines in pbxproj, found $count (see #56)"; exit 1; }

# Guard the project.yml -> Info.plist contract: these two keys are ONLY kept
# across `make generate` because they live in project.yml's info.properties
# (xcodegen writes Info.plist purely from properties). CI does not run
# `make generate`, so a merge could drop them from project.yml while the
# committed Info.plist still has them — CI would pass and the NEXT generate
# would silently re-drop them (camera crash / ITMS-91053). Fail here if the
# source of truth loses either key (Epic-10 tooling checkpoint, see #56).
PROJECT_YML="$WORKSPACE_ROOT/App/project.yml"
for key in NSCameraUsageDescription LSSupportsOpeningDocumentsInPlace; do
  grep -q "$key" "$PROJECT_YML" || { echo "ERROR: $key missing from App/project.yml info.properties — make generate would drop it from Info.plist (see #56)"; exit 1; }
done

echo ""
echo "✓ All checks passed"
