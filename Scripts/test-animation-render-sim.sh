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
DERIVED_DATA="${DERIVED_DATA:-$ROOT/.build/DerivedData-AnimationRender}"
RESULTS_DIR="${RESULTS_DIR:-$ROOT/.build/TestResults}"
TEST_LOGS_DIR="${TEST_LOGS_DIR:-$ROOT/.build/TestLogs}"
RUNNER_NAME="test-animation-render-sim"
TEST_FILTER="GlassdeckAppTests/GhosttyHomeAnimationPerformanceTests"

ensure_xcode_test_tools

if [[ ! -d "$PROJECT" ]] || [[ "$PROJECT_SPEC" -nt "$PROJECT/project.pbxproj" ]]; then
  "$GENERATE_SCRIPT"
fi

SIMULATOR_ID="$(resolve_simulator_id "$SIMULATOR_NAME")"
boot_simulator "$SIMULATOR_ID"

run_xcode_test \
  "$RUNNER_NAME" \
  "$PROJECT" \
  "$SCHEME" \
  "$DERIVED_DATA" \
  "$SIMULATOR_ID" \
  "$TEST_FILTER" \
  "$RESULTS_DIR" \
  "$TEST_LOGS_DIR" \
  -- \
  clean test \
  "-only-testing:$TEST_FILTER"
