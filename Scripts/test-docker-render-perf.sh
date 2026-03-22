#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=Scripts/xcode-test-common.sh
source "$SCRIPT_DIR/xcode-test-common.sh"
# shellcheck source=Scripts/docker/common.sh
source "$SCRIPT_DIR/docker/common.sh"

XTEST_ONLY_ARGS=("-only-testing:GlassdeckAppTests/TerminalRenderPerformanceLiveDockerTests")
XTEST_ONLY_LABELS=("GlassdeckAppTests/TerminalRenderPerformanceLiveDockerTests")
parse_standard_args "$@"
"$XCODE_TEST_COMMON_DIR/docker/smoke-test-ssh.sh"
prepare_simulator

TEST_HOST="${GLASSDECK_TEST_SSH_SIM_HOST:-127.0.0.1}"
inject_docker_ssh_sim_env "$SIMULATOR_ID" "$TEST_HOST"
trap 'clear_docker_ssh_sim_env "$SIMULATOR_ID"' EXIT
docker_ssh_xcode_env "$TEST_HOST"

run_sim_test test-docker-render-perf GlassdeckAppUnit "$XCODE_TEST_DEFAULT_UNIT_SIM_DERIVED_DATA" \
  "${DOCKER_SSH_XCODE_ENV[@]}"
