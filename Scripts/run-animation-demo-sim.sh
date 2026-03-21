#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="$ROOT/GlassdeckApp.xcodeproj"
PROJECT_SPEC="$ROOT/project.yml"
GENERATE_SCRIPT="$ROOT/Scripts/generate-xcodeproj.sh"
SCHEME="${SCHEME:-GlassdeckApp}"
APP_NAME="${APP_NAME:-Glassdeck}"
SIMULATOR_NAME="${SIMULATOR_NAME:-iPhone 17}"
DERIVED_DATA="${DERIVED_DATA:-$ROOT/.build/DerivedData-AnimationDemo}"
FIXTURES_DIR="${FIXTURES_DIR:-$ROOT/Tests/Fixtures/GhosttyHomeAnimationFrames}"
ENV_KEY="GLASSDECK_UI_TEST_ANIMATION_FRAMES_PATH"

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "xcodebuild is required." >&2
  exit 1
fi

if ! command -v xcrun >/dev/null 2>&1; then
  echo "xcrun is required." >&2
  exit 1
fi

if [[ ! -d "$FIXTURES_DIR" ]]; then
  echo "Animation fixtures not found at $FIXTURES_DIR" >&2
  exit 1
fi

if [[ ! -d "$PROJECT" ]] || [[ "$PROJECT_SPEC" -nt "$PROJECT/project.pbxproj" ]]; then
  "$GENERATE_SCRIPT"
fi

SIMULATOR_ID="$(
  xcrun simctl list devices available \
    | awk -F '[()]' -v name="$SIMULATOR_NAME" '
        $1 ~ "^[[:space:]]*" name "[[:space:]]*$" {
          print $2
        }
      ' \
    | tail -n 1
)"

if [[ -z "$SIMULATOR_ID" ]]; then
  echo "No available simulator named '$SIMULATOR_NAME' was found." >&2
  exit 1
fi

clear_animation_env() {
  xcrun simctl spawn "$SIMULATOR_ID" launchctl unsetenv "$ENV_KEY" >/dev/null 2>&1 || true
}

trap clear_animation_env EXIT

open -a Simulator >/dev/null 2>&1 || true
xcrun simctl boot "$SIMULATOR_ID" >/dev/null 2>&1 || true
xcrun simctl bootstatus "$SIMULATOR_ID" -b

xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Debug \
  -destination "platform=iOS Simulator,id=$SIMULATOR_ID" \
  -derivedDataPath "$DERIVED_DATA" \
  clean build

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
