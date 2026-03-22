#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=Scripts/xcode-test-common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/xcode-test-common.sh"

parse_standard_args "$@"
prepare_simulator
run_sim_test test-ios-sim GlassdeckAppUnit "$XCODE_TEST_DEFAULT_UNIT_SIM_DERIVED_DATA"
