#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="$ROOT/GlassdeckApp.xcodeproj"
PROJECT_SPEC="$ROOT/project.yml"
GENERATE_SCRIPT="$ROOT/Scripts/generate-xcodeproj.sh"
SCHEME="${SCHEME:-GlassdeckApp}"
APP_NAME="${APP_NAME:-Glassdeck}"
SIMULATOR_NAME="${SIMULATOR_NAME:-iPhone 17}"
DERIVED_DATA="${DERIVED_DATA:-$ROOT/.build/DerivedData-Sim}"
TAIL_LOGS=false

for arg in "$@"; do
  case "$arg" in
    --logs)
      TAIL_LOGS=true
      ;;
    *)
      echo "Unknown argument: $arg" >&2
      exit 1
      ;;
  esac
done

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "xcodebuild is required." >&2
  exit 1
fi

if ! command -v xcrun >/dev/null 2>&1; then
  echo "xcrun is required." >&2
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
xcrun simctl launch "$SIMULATOR_ID" "$BUNDLE_ID"

if [[ "$TAIL_LOGS" == true ]]; then
  xcrun simctl spawn "$SIMULATOR_ID" \
    log stream --style compact --level debug \
    --predicate "processImagePath CONTAINS[c] \"$APP_NAME.app\""
fi
