#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=Scripts/xcode-test-common.sh
source "$SCRIPT_DIR/xcode-test-common.sh"
# shellcheck source=Scripts/docker/common.sh
source "$SCRIPT_DIR/docker/common.sh"

XTEST_ONLY_ARGS=("-only-testing:GlassdeckAppUITests/DockerLiveUITests")
XTEST_ONLY_LABELS=("GlassdeckAppUITests/DockerLiveUITests")
parse_standard_args "$@"
"$XCODE_TEST_COMMON_DIR/docker/smoke-test-ssh.sh"
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
run_sim_test test-docker-ui-sim GlassdeckAppUI \
  "$XCODE_TEST_DEFAULT_UI_SIM_DERIVED_DATA" \
  "${DOCKER_SSH_XCODE_ENV[@]}"

ARTIFACTS_ROOT="${ARTIFACTS_ROOT:-$XCODE_TEST_ROOT/.build/TestArtifacts/docker-ui}"
ARTIFACT_DIR="$ARTIFACTS_ROOT/$(basename "$XCODE_TEST_RESULT_BUNDLE" .xcresult)"
mkdir -p "$ARTIFACT_DIR"
xcrun xcresulttool export attachments \
  --path "$XCODE_TEST_RESULT_BUNDLE" \
  --output-path "$ARTIFACT_DIR"

printf 'PASS [test-docker-ui-sim] log=%s xcresult=%s attachments=%s\n' \
  "$XCODE_TEST_LOG_FILE" "$XCODE_TEST_RESULT_BUNDLE" "$ARTIFACT_DIR"
