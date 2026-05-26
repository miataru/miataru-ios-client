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

  if [[ -n "$only_testing" ]]; then
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
  if [[ -n "$only_testing" ]]; then
    echo "  only-testing: $only_testing"
  fi

  xcodebuild test "${args[@]}" "$@"
}
