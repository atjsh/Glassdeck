#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=Scripts/xcode-test-common.sh
source "$SCRIPT_DIR/xcode-test-common.sh"
# shellcheck source=Scripts/docker/common.sh
source "$SCRIPT_DIR/docker/common.sh"

RUNNER_NAME="test-docker-ui-key-sim"
RUNNER_LOG_DIR="$XCODE_TEST_DEFAULT_LOGS_DIR/$RUNNER_NAME"

run_command_silently() {
  local label="$1"
  local log_file="$2"
  shift 2

  if [[ "${GLASSDECK_VERBOSE:-0}" == "1" ]]; then
    "$@"
    return $?
  fi

  if "$@" >"$log_file" 2>&1; then
    return 0
  fi

  local status=$?
  if [[ -n "${XCODE_TEST_RESULT_BUNDLE:-}" ]]; then
    printf 'FAIL [%s] %s. log=%s xcresult=%s\n' \
      "$RUNNER_NAME" "$label" "$log_file" "$XCODE_TEST_RESULT_BUNDLE" >&2
  else
    printf 'FAIL [%s] %s. log=%s\n' \
      "$RUNNER_NAME" "$label" "$log_file" >&2
  fi
  cat "$log_file" >&2
  return "$status"
}

XTEST_ONLY_ARGS=("-only-testing:GlassdeckAppUITests/DockerLiveUITests/testSSHKeyAuthFlowCapturesGhosttyScreenshot")
XTEST_ONLY_LABELS=("DockerLiveUITests/testSSHKeyAuthFlowCapturesGhosttyScreenshot")
parse_standard_args "$@"
mkdir -p "$RUNNER_LOG_DIR"
run_command_silently \
  "Docker SSH smoke test" \
  "$RUNNER_LOG_DIR/smoke-test.log" \
  "$XCODE_TEST_COMMON_DIR/docker/smoke-test-ssh.sh"
run_command_silently \
  "Preparing simulator" \
  "$RUNNER_LOG_DIR/prepare-simulator.log" \
  prepare_simulator

TEST_HOST="${GLASSDECK_TEST_SSH_SIM_HOST:-127.0.0.1}"
xcrun simctl pbcopy "$SIMULATOR_ID" < "$GLASSDECK_TEST_SSH_KEY"
inject_docker_ssh_sim_env "$SIMULATOR_ID" "$TEST_HOST"
xcrun simctl spawn "$SIMULATOR_ID" launchctl setenv GLASSDECK_UI_SCREENSHOT_CAPTURE 1
trap 'clear_docker_ssh_sim_env "$SIMULATOR_ID"' EXIT

docker_ssh_xcode_env "$TEST_HOST"
DOCKER_SSH_XCODE_ENV+=(
  "GLASSDECK_UI_SCREENSHOT_CAPTURE=1"
  "SIMCTL_CHILD_GLASSDECK_UI_SCREENSHOT_CAPTURE=1"
)

export XCODE_TEST_SUPPRESS_SUCCESS=1
run_command_silently \
  "Running UI key auth test" \
  "$RUNNER_LOG_DIR/run-ui-test.log" \
  run_sim_test test-docker-ui-key-sim GlassdeckAppUI \
    "$XCODE_TEST_DEFAULT_UI_SIM_DERIVED_DATA" \
    "${DOCKER_SSH_XCODE_ENV[@]}"

ARTIFACTS_ROOT="${ARTIFACTS_ROOT:-$XCODE_TEST_ROOT/.build/TestArtifacts/docker-ui-key}"
ARTIFACT_DIR="$ARTIFACTS_ROOT/$(basename "$XCODE_TEST_RESULT_BUNDLE" .xcresult)"
mkdir -p "$ARTIFACT_DIR"
run_command_silently \
  "Exporting xcresult attachments" \
  "$RUNNER_LOG_DIR/export-attachments.log" \
  xcrun xcresulttool export attachments \
  --path "$XCODE_TEST_RESULT_BUNDLE" \
  --output-path "$ARTIFACT_DIR"

printf 'PASS [test-docker-ui-key-sim] log=%s xcresult=%s attachments=%s\n' \
  "$XCODE_TEST_LOG_FILE" "$XCODE_TEST_RESULT_BUNDLE" "$ARTIFACT_DIR"
