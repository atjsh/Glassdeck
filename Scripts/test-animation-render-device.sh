#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/xcode-test-common.sh"

XTEST_ONLY_ARGS=("-only-testing:GlassdeckAppTests/GhosttyHomeAnimationPerformanceTests")
XTEST_ONLY_LABELS=("GlassdeckAppTests/GhosttyHomeAnimationPerformanceTests")
parse_standard_args "$@"
prepare_device
run_device_test test-animation-render-device GlassdeckAppUnit \
  "$XCODE_TEST_ROOT/.build/DerivedData-AnimationRender-Device"
