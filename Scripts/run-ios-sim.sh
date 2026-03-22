#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=Scripts/xcode-test-common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/xcode-test-common.sh"

TAIL_LOGS=false
reset_xcode_action_mode
for arg in "$@"; do
  if handle_xcode_action_arg "$arg"; then continue; fi
  case "$arg" in
    --logs) TAIL_LOGS=true ;;
    --verbose) GLASSDECK_VERBOSE=1 ;;
    *) xcode_test_die "Unknown argument: $arg" ;;
  esac
done

APP_NAME="${APP_NAME:-Glassdeck}"
prepare_simulator
run_sim_build run-ios-sim GlassdeckApp "$XCODE_TEST_DEFAULT_UI_SIM_DERIVED_DATA"

APP_PATH="$XCODE_TEST_DEFAULT_UI_SIM_DERIVED_DATA/Build/Products/Debug-iphonesimulator/$APP_NAME.app"
[[ -d "$APP_PATH" ]] || xcode_test_die "Built app not found at $APP_PATH"
BUNDLE_ID="$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$APP_PATH/Info.plist")"

xcrun simctl install "$SIMULATOR_ID" "$APP_PATH"
xcrun simctl launch "$SIMULATOR_ID" "$BUNDLE_ID"

if [[ "$TAIL_LOGS" == true ]]; then
  xcrun simctl spawn "$SIMULATOR_ID" \
    log stream --style compact --level debug \
    --predicate "processImagePath CONTAINS[c] \"$APP_NAME.app\""
fi
