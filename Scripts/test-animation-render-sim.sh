#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=Scripts/xcode-test-common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/xcode-test-common.sh"

XTEST_ONLY_ARGS=("-only-testing:GlassdeckAppTests/GhosttyHomeAnimationPerformanceTests")
XTEST_ONLY_LABELS=("GlassdeckAppTests/GhosttyHomeAnimationPerformanceTests")
parse_standard_args "$@"
prepare_simulator
run_sim_test test-animation-render-sim GlassdeckAppUnit "$XCODE_TEST_DEFAULT_UNIT_SIM_DERIVED_DATA"
