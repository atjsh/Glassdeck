#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="$ROOT/GlassdeckApp.xcodeproj"
PROJECT_SPEC="$ROOT/project.yml"
GENERATE_SCRIPT="$ROOT/Scripts/generate-xcodeproj.sh"
SCHEME="${SCHEME:-GlassdeckApp}"
SIMULATOR_NAME="${SIMULATOR_NAME:-iPhone 17}"
DERIVED_DATA="${DERIVED_DATA:-$ROOT/.build/DerivedData-LiveDockerSSH}"
RESULTS_DIR="${RESULTS_DIR:-$ROOT/.build/TestResults}"
TEST_LOGS_DIR="${TEST_LOGS_DIR:-$ROOT/.build/TestLogs}"
TEST_HOST="${GLASSDECK_TEST_SSH_SIM_HOST:-127.0.0.1}"
RUNNER_NAME="test-live-docker-ssh"
TEST_FILTER="GlassdeckAppTests/SSHConnectionManagerLiveDockerTests"

# shellcheck source=Scripts/docker/common.sh
source "$ROOT/Scripts/docker/common.sh"
# shellcheck source=Scripts/xcode-test-common.sh
source "$ROOT/Scripts/xcode-test-common.sh"

while [[ $# -gt 0 ]]; do
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

"$GENERATE_SCRIPT"
"$ROOT/Scripts/docker/smoke-test-ssh.sh"

SIMULATOR_ID="$(resolve_simulator_id "$SIMULATOR_NAME")"

boot_simulator "$SIMULATOR_ID"

clear_simulator_env() {
  local key

  for key in \
    GLASSDECK_LIVE_SSH_ENABLED \
    GLASSDECK_LIVE_SSH_HOST \
    GLASSDECK_LIVE_SSH_PORT \
    GLASSDECK_LIVE_SSH_USER \
    GLASSDECK_LIVE_SSH_PASSWORD \
    GLASSDECK_LIVE_SSH_KEY_PATH
  do
    xcrun simctl spawn "$SIMULATOR_ID" launchctl unsetenv "$key" >/dev/null 2>&1 || true
  done
}

trap clear_simulator_env EXIT

FILTER_DESCRIPTION="$(describe_test_filters "$TEST_FILTER")"

xcrun simctl spawn "$SIMULATOR_ID" launchctl setenv GLASSDECK_LIVE_SSH_ENABLED 1
xcrun simctl spawn "$SIMULATOR_ID" launchctl setenv GLASSDECK_LIVE_SSH_HOST "$TEST_HOST"
xcrun simctl spawn "$SIMULATOR_ID" launchctl setenv GLASSDECK_LIVE_SSH_PORT "$GLASSDECK_TEST_SSH_PORT"
xcrun simctl spawn "$SIMULATOR_ID" launchctl setenv GLASSDECK_LIVE_SSH_USER "$GLASSDECK_TEST_SSH_USER"
xcrun simctl spawn "$SIMULATOR_ID" launchctl setenv GLASSDECK_LIVE_SSH_PASSWORD "$GLASSDECK_TEST_SSH_PASSWORD"
xcrun simctl spawn "$SIMULATOR_ID" launchctl setenv GLASSDECK_LIVE_SSH_KEY_PATH "$GLASSDECK_TEST_SSH_KEY"

run_xcode_test \
  "$RUNNER_NAME" \
  "$PROJECT" \
  "$SCHEME" \
  "$DERIVED_DATA" \
  "$SIMULATOR_ID" \
  "$FILTER_DESCRIPTION" \
  "$RESULTS_DIR" \
  "$TEST_LOGS_DIR" \
  "GLASSDECK_LIVE_SSH_ENABLED=1" \
  "GLASSDECK_LIVE_SSH_HOST=$TEST_HOST" \
  "GLASSDECK_LIVE_SSH_PORT=$GLASSDECK_TEST_SSH_PORT" \
  "GLASSDECK_LIVE_SSH_USER=$GLASSDECK_TEST_SSH_USER" \
  "GLASSDECK_LIVE_SSH_PASSWORD=$GLASSDECK_TEST_SSH_PASSWORD" \
  "GLASSDECK_LIVE_SSH_KEY_PATH=$GLASSDECK_TEST_SSH_KEY" \
  "SIMCTL_CHILD_GLASSDECK_LIVE_SSH_ENABLED=1" \
  "SIMCTL_CHILD_GLASSDECK_LIVE_SSH_HOST=$TEST_HOST" \
  "SIMCTL_CHILD_GLASSDECK_LIVE_SSH_PORT=$GLASSDECK_TEST_SSH_PORT" \
  "SIMCTL_CHILD_GLASSDECK_LIVE_SSH_USER=$GLASSDECK_TEST_SSH_USER" \
  "SIMCTL_CHILD_GLASSDECK_LIVE_SSH_PASSWORD=$GLASSDECK_TEST_SSH_PASSWORD" \
  "SIMCTL_CHILD_GLASSDECK_LIVE_SSH_KEY_PATH=$GLASSDECK_TEST_SSH_KEY" \
  -- \
  clean test \
  "-only-testing:$TEST_FILTER"
