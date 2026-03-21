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
FIXTURES_DIR="${FIXTURES_DIR:-$ROOT/Tests/Fixtures/GhosttyHomeAnimationFrames}"
ENV_KEY="GLASSDECK_UI_TEST_ANIMATION_FRAMES_PATH"
RUNNER_NAME="run-animation-demo-sim"
XCODE_ACTION_ARGS=()

reset_xcode_action_mode
while [[ $# -gt 0 ]]; do
  if handle_xcode_action_arg "$1"; then
    shift
    continue
  fi

  case "$1" in
    --verbose)
      GLASSDECK_VERBOSE=1
      shift
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

ensure_xcode_test_tools

if [[ ! -d "$FIXTURES_DIR" ]]; then
  echo "Animation fixtures not found at $FIXTURES_DIR" >&2
  exit 1
fi

ensure_generated_project "$PROJECT" "$PROJECT_SPEC" "$GENERATE_SCRIPT"
SIMULATOR_ID="$(resolve_simulator_id "$SIMULATOR_NAME")"

clear_animation_env() {
  xcrun simctl spawn "$SIMULATOR_ID" launchctl unsetenv "$ENV_KEY" >/dev/null 2>&1 || true
}

trap clear_animation_env EXIT

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
xcrun simctl terminate "$SIMULATOR_ID" "$BUNDLE_ID" >/dev/null 2>&1 || true
xcrun simctl spawn "$SIMULATOR_ID" launchctl setenv "$ENV_KEY" "$FIXTURES_DIR"
xcrun simctl launch "$SIMULATOR_ID" "$BUNDLE_ID" \
  -uiTestScenario animation \
  -uiTestDisableAnimations \
  -uiTestOpenActiveSession

printf 'PASS [run-animation-demo-sim] simulator=%s bundle_id=%s fixtures=%s\n' \
  "$SIMULATOR_ID" \
  "$BUNDLE_ID" \
  "$FIXTURES_DIR"
