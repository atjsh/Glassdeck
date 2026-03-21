#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="$ROOT/GlassdeckApp.xcodeproj"
PROJECT_SPEC="$ROOT/project.yml"
GENERATE_SCRIPT="$ROOT/Scripts/generate-xcodeproj.sh"
SCHEME="${SCHEME:-GlassdeckAppUI}"
SIMULATOR_NAME="${SIMULATOR_NAME:-iPhone 17}"
RESULTS_DIR="${RESULTS_DIR:-$ROOT/.build/TestResults}"
TEST_LOGS_DIR="${TEST_LOGS_DIR:-$ROOT/.build/TestLogs}"
ARTIFACTS_ROOT="${ARTIFACTS_ROOT:-$ROOT/.build/TestArtifacts/docker-ui}"
TEST_HOST="${GLASSDECK_TEST_SSH_SIM_HOST:-127.0.0.1}"
RUNNER_NAME="test-docker-ui-sim"
TEST_FILTERS=(
  "GlassdeckAppUITests/DockerLiveUITests"
  "GlassdeckAppUITests/RemoteTrackpadScreenshotUITests"
)
XCODE_ACTION_ARGS=()

# shellcheck source=Scripts/docker/common.sh
source "$ROOT/Scripts/docker/common.sh"
# shellcheck source=Scripts/xcode-test-common.sh
source "$ROOT/Scripts/xcode-test-common.sh"

DERIVED_DATA="${DERIVED_DATA:-$XCODE_TEST_DEFAULT_UI_SIM_DERIVED_DATA}"

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
"$ROOT/Scripts/docker/smoke-test-ssh.sh"

SIMULATOR_ID="$(resolve_simulator_id "$SIMULATOR_NAME")"
FILTER_DESCRIPTION="$(describe_test_filters "${TEST_FILTERS[@]}")"

boot_simulator "$SIMULATOR_ID"
xcrun simctl pbcopy "$SIMULATOR_ID" < "$GLASSDECK_TEST_SSH_KEY"

clear_simulator_env() {
  local key

  for key in \
    GLASSDECK_LIVE_SSH_ENABLED \
    GLASSDECK_LIVE_SSH_HOST \
    GLASSDECK_LIVE_SSH_PORT \
    GLASSDECK_LIVE_SSH_USER \
    GLASSDECK_LIVE_SSH_PASSWORD \
    GLASSDECK_LIVE_SSH_KEY_PATH \
    GLASSDECK_UI_SCREENSHOT_CAPTURE
  do
    xcrun simctl spawn "$SIMULATOR_ID" launchctl unsetenv "$key" >/dev/null 2>&1 || true
  done
}

trap clear_simulator_env EXIT
append_xcode_action_args XCODE_ACTION_ARGS test

xcrun simctl spawn "$SIMULATOR_ID" launchctl setenv GLASSDECK_LIVE_SSH_ENABLED 1
xcrun simctl spawn "$SIMULATOR_ID" launchctl setenv GLASSDECK_LIVE_SSH_HOST "$TEST_HOST"
xcrun simctl spawn "$SIMULATOR_ID" launchctl setenv GLASSDECK_LIVE_SSH_PORT "$GLASSDECK_TEST_SSH_PORT"
xcrun simctl spawn "$SIMULATOR_ID" launchctl setenv GLASSDECK_LIVE_SSH_USER "$GLASSDECK_TEST_SSH_USER"
xcrun simctl spawn "$SIMULATOR_ID" launchctl setenv GLASSDECK_LIVE_SSH_PASSWORD "$GLASSDECK_TEST_SSH_PASSWORD"
xcrun simctl spawn "$SIMULATOR_ID" launchctl setenv GLASSDECK_LIVE_SSH_KEY_PATH "$GLASSDECK_TEST_SSH_KEY"
xcrun simctl spawn "$SIMULATOR_ID" launchctl setenv GLASSDECK_UI_SCREENSHOT_CAPTURE 1

XCODE_TEST_SUPPRESS_SUCCESS=1 run_xcode_action \
  "$RUNNER_NAME" \
  "$PROJECT" \
  "$SCHEME" \
  "$DERIVED_DATA" \
  "platform=iOS Simulator,id=$SIMULATOR_ID" \
  "tests (filters: $FILTER_DESCRIPTION)" \
  "$RESULTS_DIR" \
  "$TEST_LOGS_DIR" \
  "GLASSDECK_LIVE_SSH_ENABLED=1" \
  "GLASSDECK_LIVE_SSH_HOST=$TEST_HOST" \
  "GLASSDECK_LIVE_SSH_PORT=$GLASSDECK_TEST_SSH_PORT" \
  "GLASSDECK_LIVE_SSH_USER=$GLASSDECK_TEST_SSH_USER" \
  "GLASSDECK_LIVE_SSH_PASSWORD=$GLASSDECK_TEST_SSH_PASSWORD" \
  "GLASSDECK_LIVE_SSH_KEY_PATH=$GLASSDECK_TEST_SSH_KEY" \
  "GLASSDECK_UI_SCREENSHOT_CAPTURE=1" \
  "SIMCTL_CHILD_GLASSDECK_LIVE_SSH_ENABLED=1" \
  "SIMCTL_CHILD_GLASSDECK_LIVE_SSH_HOST=$TEST_HOST" \
  "SIMCTL_CHILD_GLASSDECK_LIVE_SSH_PORT=$GLASSDECK_TEST_SSH_PORT" \
  "SIMCTL_CHILD_GLASSDECK_LIVE_SSH_USER=$GLASSDECK_TEST_SSH_USER" \
  "SIMCTL_CHILD_GLASSDECK_LIVE_SSH_PASSWORD=$GLASSDECK_TEST_SSH_PASSWORD" \
  "SIMCTL_CHILD_GLASSDECK_LIVE_SSH_KEY_PATH=$GLASSDECK_TEST_SSH_KEY" \
  "SIMCTL_CHILD_GLASSDECK_UI_SCREENSHOT_CAPTURE=1" \
  -- \
  "${XCODE_ACTION_ARGS[@]}" \
  "-only-testing:${TEST_FILTERS[0]}" \
  "-only-testing:${TEST_FILTERS[1]}"

ARTIFACT_DIR="$ARTIFACTS_ROOT/$(basename "$XCODE_TEST_RESULT_BUNDLE" .xcresult)"
mkdir -p "$ARTIFACT_DIR"
xcrun xcresulttool export attachments \
  --path "$XCODE_TEST_RESULT_BUNDLE" \
  --output-path "$ARTIFACT_DIR"

printf 'PASS [%s] log=%s xcresult=%s attachments=%s\n' \
  "$RUNNER_NAME" \
  "$XCODE_TEST_LOG_FILE" \
  "$XCODE_TEST_RESULT_BUNDLE" \
  "$ARTIFACT_DIR"
