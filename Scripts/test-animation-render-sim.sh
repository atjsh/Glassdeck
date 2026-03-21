#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="$ROOT/GlassdeckApp.xcodeproj"
PROJECT_SPEC="$ROOT/project.yml"
GENERATE_SCRIPT="$ROOT/Scripts/generate-xcodeproj.sh"
# shellcheck source=Scripts/xcode-test-common.sh
source "$ROOT/Scripts/xcode-test-common.sh"

SCHEME="${SCHEME:-GlassdeckAppUnit}"
SIMULATOR_NAME="${SIMULATOR_NAME:-iPhone 17}"
DERIVED_DATA="${DERIVED_DATA:-$XCODE_TEST_DEFAULT_UNIT_SIM_DERIVED_DATA}"
RESULTS_DIR="${RESULTS_DIR:-$ROOT/.build/TestResults}"
TEST_LOGS_DIR="${TEST_LOGS_DIR:-$ROOT/.build/TestLogs}"
RUNNER_NAME="test-animation-render-sim"
TEST_FILTER="GlassdeckAppTests/GhosttyHomeAnimationPerformanceTests"
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

ensure_generated_project "$PROJECT" "$PROJECT_SPEC" "$GENERATE_SCRIPT"

SIMULATOR_ID="$(resolve_simulator_id "$SIMULATOR_NAME")"
boot_simulator "$SIMULATOR_ID"
append_xcode_action_args XCODE_ACTION_ARGS test

run_xcode_action \
  "$RUNNER_NAME" \
  "$PROJECT" \
  "$SCHEME" \
  "$DERIVED_DATA" \
  "platform=iOS Simulator,id=$SIMULATOR_ID" \
  "tests (filters: $TEST_FILTER)" \
  "$RESULTS_DIR" \
  "$TEST_LOGS_DIR" \
  -- \
  "${XCODE_ACTION_ARGS[@]}" \
  "-only-testing:$TEST_FILTER"
