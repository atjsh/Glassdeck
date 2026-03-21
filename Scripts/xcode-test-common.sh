#!/usr/bin/env bash

XCODE_TEST_COMMON_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
XCODE_TEST_ROOT="$(cd "$XCODE_TEST_COMMON_DIR/.." && pwd)"
XCODE_TEST_DEFAULT_RESULTS_DIR="$XCODE_TEST_ROOT/.build/TestResults"
XCODE_TEST_DEFAULT_LOGS_DIR="$XCODE_TEST_ROOT/.build/TestLogs"

XCODE_TEST_LOG_FILE=""
XCODE_TEST_RESULT_BUNDLE=""

xcode_test_die() {
  echo "$*" >&2
  exit 1
}

ensure_xcode_test_tools() {
  command -v xcodebuild >/dev/null 2>&1 || xcode_test_die "xcodebuild is required."
  command -v xcrun >/dev/null 2>&1 || xcode_test_die "xcrun is required."
}

resolve_simulator_id() {
  local simulator_name="${1:-${SIMULATOR_NAME:-iPhone 17}}"
  local resolved_id="${SIMULATOR_ID:-}"

  if [[ -n "$resolved_id" ]]; then
    printf '%s\n' "$resolved_id"
    return 0
  fi

  resolved_id="$(
    xcrun simctl list devices available \
      | awk -F '[()]' -v name="$simulator_name" '
          $1 ~ "^[[:space:]]*" name "[[:space:]]*$" {
            print $2
          }
        ' \
      | tail -n 1
  )"

  [[ -n "$resolved_id" ]] || xcode_test_die "No available simulator named '$simulator_name' was found."
  printf '%s\n' "$resolved_id"
}

boot_simulator() {
  local simulator_id="$1"

  open -a Simulator >/dev/null 2>&1 || true
  xcrun simctl boot "$simulator_id" >/dev/null 2>&1 || true
  xcrun simctl bootstatus "$simulator_id" -b
}

describe_test_filters() {
  local description=""
  local filter

  if [[ $# -eq 0 ]]; then
    printf '%s\n' "all tests"
    return 0
  fi

  for filter in "$@"; do
    if [[ -n "$description" ]]; then
      description+=", "
    fi
    description+="$filter"
  done

  printf '%s\n' "$description"
}

run_xcode_test() {
  local runner_name="$1"
  local project="$2"
  local scheme="$3"
  local derived_data="$4"
  local simulator_id="$5"
  local filter_description="$6"
  local results_dir="$7"
  local logs_dir="$8"
  local verbose="${GLASSDECK_VERBOSE:-0}"
  local suppress_success="${XCODE_TEST_SUPPRESS_SUCCESS:-0}"
  local timestamp
  local destination
  local command_status
  local env_assignments=()
  local xcodebuild_args=()
  local command=()

  shift 8

  while [[ $# -gt 0 && "$1" != "--" ]]; do
    env_assignments+=("$1")
    shift
  done

  [[ $# -gt 0 ]] || xcode_test_die "run_xcode_test requires a -- delimiter before xcodebuild arguments."
  shift
  xcodebuild_args=("$@")

  timestamp="$(date +%Y%m%d-%H%M%S)"
  destination="platform=iOS Simulator,id=$simulator_id"

  mkdir -p "$results_dir" "$logs_dir"

  XCODE_TEST_RESULT_BUNDLE="$results_dir/$runner_name-$timestamp.xcresult"
  XCODE_TEST_LOG_FILE="$logs_dir/$runner_name-$timestamp.log"

  rm -rf "$XCODE_TEST_RESULT_BUNDLE"

  if [[ ${#env_assignments[@]} -gt 0 ]]; then
    command=(env "${env_assignments[@]}" xcodebuild)
  else
    command=(xcodebuild)
  fi

  if [[ "$verbose" != "1" ]]; then
    command+=(-quiet)
  fi

  command+=(
    -project "$project"
    -scheme "$scheme"
    -configuration Debug
    -destination "$destination"
    -derivedDataPath "$derived_data"
    -resultBundlePath "$XCODE_TEST_RESULT_BUNDLE"
    "${xcodebuild_args[@]}"
  )

  printf '[%s] Running tests on %s (filters: %s)\n' "$runner_name" "$destination" "$filter_description"

  if [[ "$verbose" == "1" ]]; then
    if "${command[@]}" 2>&1 | tee "$XCODE_TEST_LOG_FILE"; then
      command_status=0
    else
      command_status=${PIPESTATUS[0]}
    fi
  else
    if "${command[@]}" >"$XCODE_TEST_LOG_FILE" 2>&1; then
      command_status=0
    else
      command_status=$?
    fi
  fi

  if [[ "$command_status" -eq 0 ]]; then
    if [[ "$suppress_success" != "1" ]]; then
      printf 'PASS [%s] log=%s xcresult=%s\n' "$runner_name" "$XCODE_TEST_LOG_FILE" "$XCODE_TEST_RESULT_BUNDLE"
    fi
    return 0
  fi

  printf 'FAIL [%s] log=%s xcresult=%s\n' "$runner_name" "$XCODE_TEST_LOG_FILE" "$XCODE_TEST_RESULT_BUNDLE" >&2

  if [[ "$verbose" != "1" ]]; then
    cat "$XCODE_TEST_LOG_FILE" >&2
  fi

  return "$command_status"
}
