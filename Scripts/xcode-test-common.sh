#!/usr/bin/env bash

XCODE_TEST_COMMON_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
XCODE_TEST_ROOT="$(cd "$XCODE_TEST_COMMON_DIR/.." && pwd)"
XCODE_TEST_DEFAULT_RESULTS_DIR="$XCODE_TEST_ROOT/.build/TestResults"
XCODE_TEST_DEFAULT_LOGS_DIR="$XCODE_TEST_ROOT/.build/TestLogs"
XCODE_TEST_DEFAULT_UNIT_SIM_DERIVED_DATA="$XCODE_TEST_ROOT/.build/DerivedData-SimTests"
XCODE_TEST_DEFAULT_UI_SIM_DERIVED_DATA="$XCODE_TEST_ROOT/.build/DerivedData-UISim"

XCODE_TEST_PROJECT="$XCODE_TEST_ROOT/GlassdeckApp.xcodeproj"
XCODE_TEST_PROJECT_SPEC="$XCODE_TEST_ROOT/project.yml"
XCODE_TEST_GENERATE_SCRIPT="$XCODE_TEST_ROOT/Scripts/generate-xcodeproj.sh"

XCODE_TEST_LOG_FILE=""
XCODE_TEST_RESULT_BUNDLE=""
XCODE_TEST_SHOULD_CLEAN=0
GLASSDECK_VERBOSE="${GLASSDECK_VERBOSE:-0}"
XTEST_ONLY_ARGS=()
XTEST_ONLY_LABELS=()
SIMULATOR_ID=""

xcode_test_die() {
  echo "$*" >&2
  exit 1
}

ensure_xcodebuild_tool() {
  command -v xcodebuild >/dev/null 2>&1 || xcode_test_die "xcodebuild is required."
}

ensure_xcode_test_tools() {
  ensure_xcodebuild_tool
  command -v xcrun >/dev/null 2>&1 || xcode_test_die "xcrun is required."
}

ensure_generated_project() {
  local project="$1"
  local project_spec="$2"
  local generate_script="$3"

  if [[ ! -d "$project" ]] || [[ "$project_spec" -nt "$project/project.pbxproj" ]]; then
    "$generate_script"
  fi
}

reset_xcode_action_mode() {
  XCODE_TEST_SHOULD_CLEAN=0
}

handle_xcode_action_arg() {
  case "$1" in
    --clean|--rebuild)
      XCODE_TEST_SHOULD_CLEAN=1
      return 0
      ;;
  esac

  return 1
}

append_xcode_action_args() {
  local array_name="$1"
  local action="$2"

  eval "$array_name=()"
  if [[ "$XCODE_TEST_SHOULD_CLEAN" == "1" ]]; then
    eval "$array_name+=(clean)"
  fi
  eval "$array_name+=(\"$action\")"
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

run_xcode_action() {
  local runner_name="$1"
  local project="$2"
  local scheme="$3"
  local derived_data="$4"
  local simulator_id="$5"
  local action_description="$6"
  local results_dir="$7"
  local logs_dir="$8"
  local verbose="${GLASSDECK_VERBOSE:-0}"
  local quiet="${XCODE_ACTION_QUIET:-1}"
  local suppress_success="${XCODE_TEST_SUPPRESS_SUCCESS:-0}"
  local timestamp
  local destination
  local command_status
  local has_result_bundle=0
  local env_assignments=()
  local xcodebuild_args=()
  local command=()
  local arg

  shift 8

  while [[ $# -gt 0 && "$1" != "--" ]]; do
    env_assignments+=("$1")
    shift
  done

  [[ $# -gt 0 ]] || xcode_test_die "run_xcode_action requires a -- delimiter before xcodebuild arguments."
  shift
  xcodebuild_args=("$@")

  timestamp="$(date +%Y%m%d-%H%M%S)"
  destination="$simulator_id"
  mkdir -p "$logs_dir"
  XCODE_TEST_LOG_FILE="$logs_dir/$runner_name-$timestamp.log"
  XCODE_TEST_RESULT_BUNDLE=""

  if [[ ${#env_assignments[@]} -gt 0 ]]; then
    command=(env "${env_assignments[@]}" xcodebuild)
  else
    command=(xcodebuild)
  fi

  if [[ "$quiet" == "1" && "$verbose" != "1" ]]; then
    command+=(-quiet)
  fi

  command+=(
    -project "$project"
    -scheme "$scheme"
    -configuration Debug
    -destination "$destination"
    -derivedDataPath "$derived_data"
  )

  for arg in "${xcodebuild_args[@]}"; do
    case "$arg" in
      test|test-without-building|build-for-testing)
        has_result_bundle=1
        break
        ;;
    esac
  done

  if [[ "$has_result_bundle" -eq 1 ]]; then
    [[ -n "$results_dir" ]] || xcode_test_die "run_xcode_action requires a results directory for test actions."
    mkdir -p "$results_dir"
    XCODE_TEST_RESULT_BUNDLE="$results_dir/$runner_name-$timestamp.xcresult"
    rm -rf "$XCODE_TEST_RESULT_BUNDLE"
    command+=(-resultBundlePath "$XCODE_TEST_RESULT_BUNDLE")
  fi

  command+=("${xcodebuild_args[@]}")

  printf '[%s] Running %s on %s\n' "$runner_name" "$action_description" "$destination"

  if [[ "$verbose" == "1" || "$quiet" != "1" ]]; then
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
      if [[ -n "$XCODE_TEST_RESULT_BUNDLE" ]]; then
        printf 'PASS [%s] log=%s xcresult=%s\n' "$runner_name" "$XCODE_TEST_LOG_FILE" "$XCODE_TEST_RESULT_BUNDLE"
      else
        printf 'PASS [%s] log=%s\n' "$runner_name" "$XCODE_TEST_LOG_FILE"
      fi
    fi
    return 0
  fi

  if [[ -n "$XCODE_TEST_RESULT_BUNDLE" ]]; then
    printf 'FAIL [%s] log=%s xcresult=%s\n' "$runner_name" "$XCODE_TEST_LOG_FILE" "$XCODE_TEST_RESULT_BUNDLE" >&2
  else
    printf 'FAIL [%s] log=%s\n' "$runner_name" "$XCODE_TEST_LOG_FILE" >&2
  fi

  if [[ "$verbose" != "1" && "$quiet" == "1" ]]; then
    cat "$XCODE_TEST_LOG_FILE" >&2
  fi

  return "$command_status"
}

run_xcode_test() {
  run_xcode_action "$@"
}

# ---------------------------------------------------------------------------
# High-level helpers — absorb the boilerplate repeated by every script.
# ---------------------------------------------------------------------------

parse_standard_args() {
  reset_xcode_action_mode
  while [[ $# -gt 0 ]]; do
    if handle_xcode_action_arg "$1"; then shift; continue; fi
    case "$1" in
      --verbose) GLASSDECK_VERBOSE=1; shift ;;
      --only-testing)
        [[ $# -ge 2 ]] || xcode_test_die "--only-testing requires a test identifier."
        XTEST_ONLY_ARGS+=("-only-testing:$2")
        XTEST_ONLY_LABELS+=("$2")
        shift 2 ;;
      *) xcode_test_die "Unknown argument: $1" ;;
    esac
  done
}

prepare_simulator() {
  ensure_xcode_test_tools
  ensure_generated_project "$XCODE_TEST_PROJECT" "$XCODE_TEST_PROJECT_SPEC" "$XCODE_TEST_GENERATE_SCRIPT"
  SIMULATOR_ID="$(resolve_simulator_id "${SIMULATOR_NAME:-iPhone 17}")"
  boot_simulator "$SIMULATOR_ID"
}

prepare_device() {
  ensure_xcodebuild_tool
  [[ -n "${DEVICE_ID:-}" ]] || xcode_test_die "Set DEVICE_ID to a connected iOS device UDID."
  ensure_generated_project "$XCODE_TEST_PROJECT" "$XCODE_TEST_PROJECT_SPEC" "$XCODE_TEST_GENERATE_SCRIPT"
}

# run_sim_test RUNNER SCHEME DERIVED_DATA [ENV_ARGS...] [-- EXTRA_XCODEBUILD_ARGS...]
run_sim_test() {
  local runner="$1" scheme="$2" dd="$3"
  shift 3
  local env_args=() extra_args=()
  while [[ $# -gt 0 && "$1" != "--" ]]; do env_args+=("$1"); shift; done
  [[ "${1:-}" == "--" ]] && shift
  extra_args=("$@")

  local action_args=()
  append_xcode_action_args action_args test

  run_xcode_action "$runner" "$XCODE_TEST_PROJECT" "$scheme" "$dd" \
    "platform=iOS Simulator,id=$SIMULATOR_ID" \
    "tests (filters: $(describe_test_filters "${XTEST_ONLY_LABELS[@]}"))" \
    "$XCODE_TEST_DEFAULT_RESULTS_DIR" "$XCODE_TEST_DEFAULT_LOGS_DIR" \
    "${env_args[@]}" \
    -- "${action_args[@]}" "${XTEST_ONLY_ARGS[@]}" "${extra_args[@]}"
}

# run_device_test RUNNER SCHEME DERIVED_DATA [-- EXTRA_XCODEBUILD_ARGS...]
run_device_test() {
  local runner="$1" scheme="$2" dd="$3"
  shift 3
  [[ "${1:-}" == "--" ]] && shift
  local extra_args=("$@")

  local action_args=()
  append_xcode_action_args action_args test

  run_xcode_action "$runner" "$XCODE_TEST_PROJECT" "$scheme" "$dd" \
    "id=$DEVICE_ID" \
    "tests (filters: $(describe_test_filters "${XTEST_ONLY_LABELS[@]}"))" \
    "$XCODE_TEST_DEFAULT_RESULTS_DIR" "$XCODE_TEST_DEFAULT_LOGS_DIR" \
    -- "${action_args[@]}" "${XTEST_ONLY_ARGS[@]}" "${extra_args[@]}"
}

# run_sim_build RUNNER SCHEME DERIVED_DATA
run_sim_build() {
  local runner="$1" scheme="$2" dd="$3"
  local action_args=()
  append_xcode_action_args action_args build

  XCODE_ACTION_QUIET=0 XCODE_TEST_SUPPRESS_SUCCESS=1 run_xcode_action \
    "$runner" "$XCODE_TEST_PROJECT" "$scheme" "$dd" \
    "platform=iOS Simulator,id=$SIMULATOR_ID" "build" "" \
    "$XCODE_TEST_DEFAULT_LOGS_DIR" \
    -- "${action_args[@]}"
}
