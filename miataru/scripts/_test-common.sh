#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

PROJECT_PATH="${PROJECT_PATH:-$REPO_ROOT/miataru.xcodeproj}"
SCHEME="${SCHEME:-miataru}"
CONFIGURATION="${CONFIGURATION:-Debug}"
TEST_USE_DEDICATED_SIMULATOR="${TEST_USE_DEDICATED_SIMULATOR:-1}"
TEST_SIMULATOR_NAME="${TEST_SIMULATOR_NAME:-miataru Tests - iPhone 16}"
TEST_SIMULATOR_DEVICE_TYPE="${TEST_SIMULATOR_DEVICE_TYPE:-com.apple.CoreSimulator.SimDeviceType.iPhone-16}"
TEST_OUTPUT="${TEST_OUTPUT:-summary}"
TEST_LOG_DIR="${TEST_LOG_DIR:-$REPO_ROOT/artifacts/test-logs}"
TEST_SUMMARY_MAX_LINES="${TEST_SUMMARY_MAX_LINES:-200}"

latest_ios_runtime_id() {
  xcrun simctl list runtimes available | awk -F ' - ' '/iOS .*com.apple.CoreSimulator.SimRuntime.iOS-/{print $NF}' | tail -n1
}

find_simulator_udid_by_name() {
  local simulator_name="$1"
  xcrun simctl list devices available | awk -v target="$simulator_name" '
    index($0, target " (") > 0 {
      if (match($0, /[0-9A-F-]{36}/)) {
        print substr($0, RSTART, RLENGTH)
        exit
      }
    }
  '
}

ensure_test_simulator() {
  local simulator_name="$1"
  local device_type_id="$2"

  local existing
  existing="$(find_simulator_udid_by_name "$simulator_name" || true)"
  if [[ -n "$existing" ]]; then
    echo "$existing"
    return
  fi

  local runtime_id
  runtime_id="$(latest_ios_runtime_id)"
  if [[ -z "$runtime_id" ]]; then
    echo "Unable to find available iOS simulator runtime." >&2
    exit 1
  fi

  echo "Creating simulator: $simulator_name ($device_type_id, $runtime_id)" >&2
  xcrun simctl create "$simulator_name" "$device_type_id" "$runtime_id" >/dev/null

  local created
  created="$(find_simulator_udid_by_name "$simulator_name" || true)"
  if [[ -z "$created" ]]; then
    echo "Failed to create simulator for $simulator_name" >&2
    exit 1
  fi

  echo "$created"
}

resolve_destination() {
  if [[ -n "${TEST_DESTINATION:-}" ]]; then
    echo "$TEST_DESTINATION"
    return
  fi

  if [[ "$TEST_USE_DEDICATED_SIMULATOR" == "1" ]]; then
    local dedicated_udid
    dedicated_udid="$(ensure_test_simulator "$TEST_SIMULATOR_NAME" "$TEST_SIMULATOR_DEVICE_TYPE")"
    echo "platform=iOS Simulator,id=$dedicated_udid"
    return
  fi

  local booted
  booted="$(xcrun simctl list devices available | grep -E 'iPhone|iPad' | grep 'Booted' | head -n1 | awk -F '[()]' '{print $2}')"
  if [[ -n "$booted" ]]; then
    echo "platform=iOS Simulator,id=$booted"
    return
  fi

  local first_iphone
  first_iphone="$(xcrun simctl list devices available | grep 'iPhone' | head -n1 | awk -F '[()]' '{print $2}')"
  if [[ -n "$first_iphone" ]]; then
    echo "platform=iOS Simulator,id=$first_iphone"
    return
  fi

  local first_ipad
  first_ipad="$(xcrun simctl list devices available | grep 'iPad' | head -n1 | awk -F '[()]' '{print $2}')"
  if [[ -n "$first_ipad" ]]; then
    echo "platform=iOS Simulator,id=$first_ipad"
    return
  fi

  echo "platform=iOS Simulator,name=iPhone 16"
}

sanitize_log_label() {
  local label="$1"
  printf "%s" "$label" | tr -cs '[:alnum:]_.-' '_'
}

test_log_path() {
  local only_testing="${1:-all}"
  local timestamp
  local scheme_label
  local test_label

  timestamp="$(date +"%Y%m%d-%H%M%S")"
  scheme_label="$(sanitize_log_label "$SCHEME")"
  test_label="$(sanitize_log_label "${only_testing:-all}")"

  printf "%s/%s-%s-%s.log" "$TEST_LOG_DIR" "$timestamp" "$scheme_label" "$test_label"
}

filter_xcodebuild_summary() {
  awk -v max="$TEST_SUMMARY_MAX_LINES" '
    function emit(line) {
      if (count < max) {
        print line
      }
      count++
    }

    /Failing tests:/ {
      emit($0)
      failing_tests = 1
      failing_lines = 20
      next
    }

    failing_tests && failing_lines > 0 && /^[[:space:]]+/ {
      emit($0)
      failing_lines--
      next
    }

    failing_tests {
      failing_tests = 0
    }

    /xcodebuild: error/ ||
    /(^|[^[:alpha:]])error:/ ||
    /(^|[^[:alpha:]])warning:/ ||
    /TEST FAILED/ ||
    /TEST SUCCEEDED/ ||
    /Testing failed/ ||
    /Test Suite .* failed/ ||
    /Test Case .* failed/ ||
    /Executed [0-9]+ tests?/ ||
    /Test run with [0-9]+ tests?/ ||
    /Suite .* failed/ ||
    /Test .* failed after/ ||
    /Issue recorded/ ||
    /The following build commands failed/ ||
    /\*\* TEST (FAILED|SUCCEEDED) \*\*/ ||
    /\*\* BUILD (FAILED|SUCCEEDED) \*\*/ {
      emit($0)
      next
    }

    END {
      if (count > max) {
        printf "... %d additional focused log lines omitted. See full log.\n", count - max
      }
    }
  '
}

focused_line_count() {
  local log_file="$1"

  awk '
    /Failing tests:/ ||
    /xcodebuild: error/ ||
    /(^|[^[:alpha:]])error:/ ||
    /(^|[^[:alpha:]])warning:/ ||
    /TEST FAILED/ ||
    /TEST SUCCEEDED/ ||
    /Testing failed/ ||
    /Test Suite .* failed/ ||
    /Test Case .* failed/ ||
    /Executed [0-9]+ tests?/ ||
    /Test run with [0-9]+ tests?/ ||
    /Suite .* failed/ ||
    /Test .* failed after/ ||
    /Issue recorded/ ||
    /The following build commands failed/ ||
    /\*\* TEST (FAILED|SUCCEEDED) \*\*/ ||
    /\*\* BUILD (FAILED|SUCCEEDED) \*\*/ {
      count++
    }

    END {
      print count + 0
    }
  ' "$log_file"
}

has_explicit_only_testing() {
  local arg

  for arg in "$@"; do
    if [[ "$arg" == "-only-testing" || "$arg" == -only-testing:* ]]; then
      return 0
    fi
  done

  return 1
}

run_xcodebuild_test() {
  local only_testing="$1"
  shift

  case "$TEST_OUTPUT" in
    full)
      echo "  output: full"
      xcodebuild test "$@"
      ;;
    summary)
      local errexit_was_set
      local log_file
      local status
      local matches

      errexit_was_set=0
      case "$-" in
        *e*) errexit_was_set=1 ;;
      esac

      mkdir -p "$TEST_LOG_DIR"
      log_file="$(test_log_path "$only_testing")"

      echo "  output: summary"
      echo "  full log: $log_file"
      echo "Focused xcodebuild output:"

      set +e
      xcodebuild test "$@" 2>&1 | tee "$log_file" | filter_xcodebuild_summary
      status="${PIPESTATUS[0]}"
      if [[ "$errexit_was_set" == "1" ]]; then
        set -e
      else
        set +e
      fi

      echo "xcodebuild exit code: $status"

      if [[ "$status" -ne 0 ]]; then
        matches="$(focused_line_count "$log_file")"
        if [[ "$matches" == "0" ]]; then
          echo "No focused diagnostics matched the summary filter."
        fi
        echo "Full log: $log_file"
        echo "Next focused diagnostics:"
        echo "  rg -n \"error:|warning:|TEST FAILED|Testing failed|Failing tests|Executed\" \"$log_file\""
        echo "  tail -n 120 \"$log_file\""
      fi

      return "$status"
      ;;
    *)
      echo "Unknown TEST_OUTPUT '$TEST_OUTPUT'. Use 'summary' or 'full'." >&2
      return 2
      ;;
  esac
}

run_tests() {
  local only_testing="${1:-}"
  shift || true

  local destination
  destination="$(resolve_destination)"

  local args=(
    -project "$PROJECT_PATH"
    -scheme "$SCHEME"
    -configuration "$CONFIGURATION"
    -destination "$destination"
  )

  if [[ -n "$only_testing" ]] && ! has_explicit_only_testing "$@"; then
    args+=("-only-testing:$only_testing")
  fi

  if [[ -n "${RESULT_BUNDLE_PATH:-}" ]]; then
    args+=(-resultBundlePath "$RESULT_BUNDLE_PATH")
  fi

  echo "Running xcodebuild test"
  echo "  project: $PROJECT_PATH"
  echo "  scheme: $SCHEME"
  echo "  config: $CONFIGURATION"
  echo "  destination: $destination"
  if [[ -n "$only_testing" ]] && ! has_explicit_only_testing "$@"; then
    echo "  only-testing: $only_testing"
  elif has_explicit_only_testing "$@"; then
    echo "  only-testing: explicit argument"
  fi

  run_xcodebuild_test "$only_testing" "${args[@]}" "$@"
}
