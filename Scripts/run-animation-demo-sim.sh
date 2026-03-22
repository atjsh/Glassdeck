#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=Scripts/xcode-test-common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/xcode-test-common.sh"

FIXTURES_DIR="${FIXTURES_DIR:-$XCODE_TEST_ROOT/Tests/Fixtures/GhosttyHomeAnimationFrames}"
ENV_KEY="GLASSDECK_UI_TEST_ANIMATION_FRAMES_PATH"
APP_NAME="${APP_NAME:-Glassdeck}"

reset_xcode_action_mode
for arg in "$@"; do
  if handle_xcode_action_arg "$arg"; then continue; fi
  case "$arg" in
    --verbose) GLASSDECK_VERBOSE=1 ;;
    *) xcode_test_die "Unknown argument: $arg" ;;
  esac
done

[[ -d "$FIXTURES_DIR" ]] || xcode_test_die "Animation fixtures not found at $FIXTURES_DIR"
prepare_simulator
trap 'xcrun simctl spawn "$SIMULATOR_ID" launchctl unsetenv "$ENV_KEY" >/dev/null 2>&1 || true' EXIT
run_sim_build run-animation-demo-sim GlassdeckApp "$XCODE_TEST_DEFAULT_UI_SIM_DERIVED_DATA"

APP_PATH="$XCODE_TEST_DEFAULT_UI_SIM_DERIVED_DATA/Build/Products/Debug-iphonesimulator/$APP_NAME.app"
[[ -d "$APP_PATH" ]] || xcode_test_die "Built app not found at $APP_PATH"
BUNDLE_ID="$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$APP_PATH/Info.plist")"

xcrun simctl install "$SIMULATOR_ID" "$APP_PATH"
xcrun simctl terminate "$SIMULATOR_ID" "$BUNDLE_ID" >/dev/null 2>&1 || true
xcrun simctl spawn "$SIMULATOR_ID" launchctl setenv "$ENV_KEY" "$FIXTURES_DIR"
xcrun simctl launch "$SIMULATOR_ID" "$BUNDLE_ID" \
  -uiTestScenario animation \
  -uiTestDisableAnimations \
  -uiTestOpenActiveSession

printf 'PASS [run-animation-demo-sim] simulator=%s bundle_id=%s fixtures=%s\n' \
  "$SIMULATOR_ID" "$BUNDLE_ID" "$FIXTURES_DIR"
