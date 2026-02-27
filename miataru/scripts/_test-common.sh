#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

PROJECT_PATH="${PROJECT_PATH:-$REPO_ROOT/miataru.xcodeproj}"
SCHEME="${SCHEME:-miataru}"
CONFIGURATION="${CONFIGURATION:-Debug}"

resolve_destination() {
  if [[ -n "${TEST_DESTINATION:-}" ]]; then
    echo "$TEST_DESTINATION"
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
