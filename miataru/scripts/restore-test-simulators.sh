#!/usr/bin/env bash
set -euo pipefail

simulator_specs=(
  "miataru Tests - iPhone 16|com.apple.CoreSimulator.SimDeviceType.iPhone-16"
  "miataru Screenshots - iPhone 16 Pro Max|com.apple.CoreSimulator.SimDeviceType.iPhone-16-Pro-Max"
  "miataru Screenshots - iPad Pro 13-inch (M5)|com.apple.CoreSimulator.SimDeviceType.iPad-Pro-13-inch-M5-12GB"
)

usage() {
  cat <<'EOF'
Usage: ./scripts/restore-test-simulators.sh

Creates the dedicated Miataru test and screenshot iOS simulator devices if
they are missing. Existing matching devices are left unchanged.

Environment:
  IOS_RUNTIME_ID   Optional explicit iOS runtime id, e.g.
                   com.apple.CoreSimulator.SimRuntime.iOS-26-5
EOF
}

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

ensure_simulator() {
  local simulator_name="$1"
  local device_type_id="$2"
  local runtime_id="$3"

  local existing
  existing="$(find_simulator_udid_by_name "$simulator_name" || true)"
  if [[ -n "$existing" ]]; then
    printf "exists   %s (%s)\n" "$simulator_name" "$existing"
    return
  fi

  local created
  created="$(xcrun simctl create "$simulator_name" "$device_type_id" "$runtime_id")"
  printf "created  %s (%s)\n" "$simulator_name" "$created"
}

case "${1:-}" in
  --help|-h)
    usage
    exit 0
    ;;
  "")
    ;;
  *)
    echo "Unknown option: $1" >&2
    usage >&2
    exit 1
    ;;
esac

runtime_id="${IOS_RUNTIME_ID:-$(latest_ios_runtime_id)}"
if [[ -z "$runtime_id" ]]; then
  echo "Unable to find an available iOS simulator runtime." >&2
  exit 1
fi

echo "Using iOS runtime: $runtime_id"

for spec in "${simulator_specs[@]}"; do
  IFS='|' read -r simulator_name device_type_id <<< "$spec"
  ensure_simulator "$simulator_name" "$device_type_id" "$runtime_id"
done
