#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="$ROOT/GlassdeckApp.xcodeproj"
PROJECT_SPEC="$ROOT/project.yml"
GENERATE_SCRIPT="$ROOT/Scripts/generate-xcodeproj.sh"
SCHEME="${SCHEME:-GlassdeckApp}"
DERIVED_DATA="${DERIVED_DATA:-$ROOT/.build/DerivedData-AnimationRender-Device}"
RESULTS_DIR="${RESULTS_DIR:-$ROOT/.build/TestResults}"
TEST_LOGS_DIR="${TEST_LOGS_DIR:-$ROOT/.build/TestLogs}"
RUNNER_NAME="test-animation-render-device"
TEST_FILTER="GlassdeckAppTests/GhosttyHomeAnimationPerformanceTests"
DEVICE_ID="${DEVICE_ID:-}"
VERBOSE="${GLASSDECK_VERBOSE:-0}"

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "xcodebuild is required." >&2
  exit 1
fi

if [[ -z "$DEVICE_ID" ]]; then
  echo "Set DEVICE_ID to a connected iOS device UDID." >&2
  exit 1
fi

if [[ ! -d "$PROJECT" ]] || [[ "$PROJECT_SPEC" -nt "$PROJECT/project.pbxproj" ]]; then
  "$GENERATE_SCRIPT"
fi

mkdir -p "$RESULTS_DIR" "$TEST_LOGS_DIR"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
RESULT_BUNDLE="$RESULTS_DIR/$RUNNER_NAME-$TIMESTAMP.xcresult"
LOG_FILE="$TEST_LOGS_DIR/$RUNNER_NAME-$TIMESTAMP.log"
rm -rf "$RESULT_BUNDLE"

COMMAND=(
  xcodebuild
  -project "$PROJECT"
  -scheme "$SCHEME"
  -configuration Debug
  -destination "id=$DEVICE_ID"
  -derivedDataPath "$DERIVED_DATA"
  -resultBundlePath "$RESULT_BUNDLE"
  clean test
  "-only-testing:$TEST_FILTER"
)

printf '[%s] Running tests on id=%s (filters: %s)\n' "$RUNNER_NAME" "$DEVICE_ID" "$TEST_FILTER"

if [[ "$VERBOSE" == "1" ]]; then
  if "${COMMAND[@]}" 2>&1 | tee "$LOG_FILE"; then
    printf 'PASS [%s] log=%s xcresult=%s\n' "$RUNNER_NAME" "$LOG_FILE" "$RESULT_BUNDLE"
  else
    status=${PIPESTATUS[0]}
    printf 'FAIL [%s] log=%s xcresult=%s\n' "$RUNNER_NAME" "$LOG_FILE" "$RESULT_BUNDLE" >&2
    exit "$status"
  fi
else
  if "${COMMAND[@]}" >"$LOG_FILE" 2>&1; then
    printf 'PASS [%s] log=%s xcresult=%s\n' "$RUNNER_NAME" "$LOG_FILE" "$RESULT_BUNDLE"
  else
    status=$?
    printf 'FAIL [%s] log=%s xcresult=%s\n' "$RUNNER_NAME" "$LOG_FILE" "$RESULT_BUNDLE" >&2
    cat "$LOG_FILE" >&2
    exit "$status"
  fi
fi
