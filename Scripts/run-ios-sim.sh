#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="$ROOT/GlassdeckApp.xcodeproj"
PROJECT_SPEC="$ROOT/project.yml"
GENERATE_SCRIPT="$ROOT/Scripts/generate-xcodeproj.sh"
# shellcheck source=Scripts/xcode-test-common.sh
source "$ROOT/Scripts/xcode-test-common.sh"

SCHEME="${SCHEME:-GlassdeckApp}"
APP_NAME="${APP_NAME:-Glassdeck}"
SIMULATOR_NAME="${SIMULATOR_NAME:-iPhone 17}"
DERIVED_DATA="${DERIVED_DATA:-$XCODE_TEST_DEFAULT_UI_SIM_DERIVED_DATA}"
TEST_LOGS_DIR="${TEST_LOGS_DIR:-$ROOT/.build/TestLogs}"
TAIL_LOGS=false
RUNNER_NAME="run-ios-sim"
XCODE_ACTION_ARGS=()

reset_xcode_action_mode
for arg in "$@"; do
  if handle_xcode_action_arg "$arg"; then
    continue
  fi

  case "$arg" in
    --logs)
      TAIL_LOGS=true
      ;;
    --verbose)
      GLASSDECK_VERBOSE=1
      ;;
    *)
      echo "Unknown argument: $arg" >&2
      exit 1
      ;;
  esac
done

ensure_xcode_test_tools
ensure_generated_project "$PROJECT" "$PROJECT_SPEC" "$GENERATE_SCRIPT"
SIMULATOR_ID="$(resolve_simulator_id "$SIMULATOR_NAME")"
boot_simulator "$SIMULATOR_ID"
append_xcode_action_args XCODE_ACTION_ARGS build

XCODE_ACTION_QUIET=0 XCODE_TEST_SUPPRESS_SUCCESS=1 run_xcode_action \
  "$RUNNER_NAME" \
  "$PROJECT" \
  "$SCHEME" \
  "$DERIVED_DATA" \
  "platform=iOS Simulator,id=$SIMULATOR_ID" \
  "build" \
  "" \
  "$TEST_LOGS_DIR" \
  -- \
  "${XCODE_ACTION_ARGS[@]}"

APP_PATH="$DERIVED_DATA/Build/Products/Debug-iphonesimulator/$APP_NAME.app"
if [[ ! -d "$APP_PATH" ]]; then
  echo "Built app not found at $APP_PATH" >&2
  exit 1
fi

BUNDLE_ID="$(
  /usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$APP_PATH/Info.plist"
)"

xcrun simctl install "$SIMULATOR_ID" "$APP_PATH"
xcrun simctl launch "$SIMULATOR_ID" "$BUNDLE_ID"

if [[ "$TAIL_LOGS" == true ]]; then
  xcrun simctl spawn "$SIMULATOR_ID" \
    log stream --style compact --level debug \
    --predicate "processImagePath CONTAINS[c] \"$APP_NAME.app\""
fi
