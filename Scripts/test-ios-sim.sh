#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="$ROOT/GlassdeckApp.xcodeproj"
PROJECT_SPEC="$ROOT/project.yml"
GENERATE_SCRIPT="$ROOT/Scripts/generate-xcodeproj.sh"
# shellcheck source=Scripts/xcode-test-common.sh
source "$ROOT/Scripts/xcode-test-common.sh"

SCHEME="${SCHEME:-GlassdeckApp}"
SIMULATOR_NAME="${SIMULATOR_NAME:-iPhone 17}"
DERIVED_DATA="${DERIVED_DATA:-$ROOT/.build/DerivedData-Tests}"
RESULTS_DIR="${RESULTS_DIR:-$ROOT/.build/TestResults}"
TEST_LOGS_DIR="${TEST_LOGS_DIR:-$ROOT/.build/TestLogs}"
RUNNER_NAME="test-ios-sim"
ONLY_TESTING_ARGS=()
ONLY_TESTING_LABELS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --verbose)
      GLASSDECK_VERBOSE=1
      shift
      ;;
    --only-testing)
      if [[ $# -lt 2 ]]; then
        echo "--only-testing requires a test identifier." >&2
        exit 1
      fi
      ONLY_TESTING_ARGS+=("-only-testing:$2")
      ONLY_TESTING_LABELS+=("$2")
      shift 2
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

ensure_xcode_test_tools

if [[ ! -d "$PROJECT" ]] || [[ "$PROJECT_SPEC" -nt "$PROJECT/project.pbxproj" ]]; then
  "$GENERATE_SCRIPT"
fi

SIMULATOR_ID="$(resolve_simulator_id "$SIMULATOR_NAME")"
FILTER_DESCRIPTION="$(describe_test_filters "${ONLY_TESTING_LABELS[@]}")"

boot_simulator "$SIMULATOR_ID"

run_xcode_test \
  "$RUNNER_NAME" \
  "$PROJECT" \
  "$SCHEME" \
  "$DERIVED_DATA" \
  "$SIMULATOR_ID" \
  "$FILTER_DESCRIPTION" \
  "$RESULTS_DIR" \
  "$TEST_LOGS_DIR" \
  -- \
  clean test \
  "${ONLY_TESTING_ARGS[@]}"
