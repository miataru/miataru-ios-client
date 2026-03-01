#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PROJECT_PATH="${PROJECT_PATH:-$REPO_ROOT/miataru.xcodeproj}"
SCHEME="${SCHEME:-miataru-Screenshots}"
CONFIGURATION="${CONFIGURATION:-Debug}"
TEST_PLAN="${TEST_PLAN:-Screenshots}"

ARTIFACT_ROOT="${ARTIFACT_ROOT:-$REPO_ROOT/artifacts}"
SCREENSHOT_ROOT=""
XCRESULT_ROOT=""
APP_VERSION=""
APP_BUILD=""
ARTIFACT_VERSION_TAG=""

LANGUAGES=(en de ja fr es zh-Hans nl da it fi)
if [[ -n "${LANGUAGES_CSV:-}" ]]; then
  IFS=',' read -r -a LANGUAGES <<< "$LANGUAGES_CSV"
fi

extra_xcodebuild_args=()
if [[ "${XCODEBUILD_DRY_RUN:-0}" == "1" ]]; then
  extra_xcodebuild_args+=("-dry-run")
fi

device_specs=(
  "iPhone 16 Pro Max|com.apple.CoreSimulator.SimDeviceType.iPhone-16-Pro-Max"
  "iPad Pro 13-inch (M5)|com.apple.CoreSimulator.SimDeviceType.iPad-Pro-13-inch-M5-12GB"
)

scenario_specs=(
  "root-devices|miataruScreenshotUITests/FeatureScreenshotScenariosUITests/test_01_root_devices|Root Devices Startansicht"
  "root-qr|miataruScreenshotUITests/FeatureScreenshotScenariosUITests/test_02_root_qr|Root QR Tab"
  "root-settings|miataruScreenshotUITests/FeatureScreenshotScenariosUITests/test_03_root_settings|Root Settings Tab"
  "devices-add-sheet|miataruScreenshotUITests/FeatureScreenshotScenariosUITests/test_04_devices_add_sheet|Devices Add Sheet offen"
  "settings-show-onboarding|miataruScreenshotUITests/FeatureScreenshotScenariosUITests/test_05_settings_show_onboarding_action|Settings Onboarding Aktion sichtbar"
  "onboarding-start|miataruScreenshotUITests/FeatureScreenshotScenariosUITests/test_06_onboarding_start|Onboarding Startscreen"
  "onboarding-pager|miataruScreenshotUITests/FeatureScreenshotScenariosUITests/test_07_onboarding_pager|Onboarding Pager"
  "qr-device-key|miataruScreenshotUITests/FeatureScreenshotScenariosUITests/test_08_qr_device_key_action|QR Device Key Aktion"
  "groups-tab|miataruScreenshotUITests/FeatureScreenshotScenariosUITests/test_09_ipad_groups_tab_or_skip|iPad Groups Tab (oder Skip)"
  "settings-navigation|miataruScreenshotUITests/FeatureScreenshotScenariosUITests/test_10_settings_navigation_container|Settings Navigation Container"
)

selected_inputs=()
selected_test_ids=()
only_testing_args=()
selected_count=0
list_only=0

usage() {
  cat <<'EOF'
Usage: ./scripts/test-screenshots.sh [options]

Options:
  --list, -l            List available screenshot tests and exit
  --test, -t <selector> Run only selected screenshot test(s)
  --help, -h            Show help

Selector forms for --test (repeatable, comma-separated also supported):
  - Scenario ID       (e.g. root-devices)
  - Test method name  (e.g. test_01_root_devices)
  - Full test ID      (e.g. miataruScreenshotUITests/FeatureScreenshotScenariosUITests/test_01_root_devices)

Environment:
  SCREENSHOT_TESTS_CSV   Optional comma-separated selectors (same forms as --test)
  LANGUAGES_CSV          Optional comma-separated language list (e.g. en,de)
  XCODEBUILD_DRY_RUN=1   Build/test dry-run without attachment export
  APP_VERSION_OVERRIDE   Override app marketing version in artifact structure
  APP_BUILD_OVERRIDE     Override app build number in artifact structure
  ARTIFACT_VERSION_TAG   Explicit artifact version folder name (highest priority)
EOF
}

trim_whitespace() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
}

sanitize_slug() {
  local input="$1"
  local value
  value="$(printf '%s' "$input" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9_-]+/-/g; s/^-+//; s/-+$//; s/-+/-/g')"
  if [[ -z "$value" ]]; then
    value="unknown"
  fi
  printf '%s' "$value"
}

list_available_tests() {
  printf "%-3s %-24s %-34s %s\n" "Nr" "Scenario ID" "Testmethode" "Beschreibung"
  printf "%-3s %-24s %-34s %s\n" "---" "------------------------" "----------------------------------" "------------------------------"
  local i=1
  local spec scenario_id test_id description method
  for spec in "${scenario_specs[@]}"; do
    IFS='|' read -r scenario_id test_id description <<< "$spec"
    method="${test_id##*/}"
    printf "%-3s %-24s %-34s %s\n" "$i" "$scenario_id" "$method" "$description"
    i=$((i + 1))
  done
}

append_test_if_missing() {
  local test_id="$1"
  local existing
  for existing in "${selected_test_ids[@]-}"; do
    if [[ "$existing" == "$test_id" ]]; then
      return
    fi
  done
  selected_test_ids+=("$test_id")
  only_testing_args+=("-only-testing:$test_id")
  selected_count=$((selected_count + 1))
}

resolve_selector() {
  local selector="$1"
  local spec scenario_id test_id description method
  for spec in "${scenario_specs[@]}"; do
    IFS='|' read -r scenario_id test_id description <<< "$spec"
    method="${test_id##*/}"
    if [[ "$selector" == "$scenario_id" || "$selector" == "$method" || "$selector" == "$test_id" ]]; then
      printf '%s' "$test_id"
      return
    fi
  done
  printf ''
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --list|-l)
        list_only=1
        shift
        ;;
      --test|-t)
        if [[ $# -lt 2 ]]; then
          echo "Missing value for $1" >&2
          usage >&2
          exit 1
        fi
        selected_inputs+=("$2")
        shift 2
        ;;
      --help|-h)
        usage
        exit 0
        ;;
      *)
        echo "Unknown option: $1" >&2
        usage >&2
        exit 1
        ;;
    esac
  done
}

resolve_selected_tests() {
  local input selector resolved
  if [[ -n "${SCREENSHOT_TESTS_CSV:-}" ]]; then
    selected_inputs+=("$SCREENSHOT_TESTS_CSV")
  fi

  for input in "${selected_inputs[@]}"; do
    IFS=',' read -r -a parts <<< "$input"
    local selector_raw
    for selector_raw in "${parts[@]}"; do
      selector="$(trim_whitespace "$selector_raw")"
      if [[ -z "$selector" ]]; then
        continue
      fi
      resolved="$(resolve_selector "$selector")"
      if [[ -z "$resolved" ]]; then
        echo "Unknown screenshot selector: $selector" >&2
        echo >&2
        list_available_tests >&2
        exit 1
      fi
      append_test_if_missing "$resolved"
    done
  done
}

resolve_app_version_info() {
  APP_VERSION="${APP_VERSION_OVERRIDE:-}"
  APP_BUILD="${APP_BUILD_OVERRIDE:-}"

  if [[ -z "$APP_VERSION" || -z "$APP_BUILD" ]]; then
    local build_settings
    build_settings="$(xcodebuild -project "$PROJECT_PATH" -target miataru -configuration "$CONFIGURATION" -showBuildSettings 2>/dev/null || true)"

    if [[ -z "$APP_VERSION" ]]; then
      APP_VERSION="$(printf '%s\n' "$build_settings" | sed -n 's/^[[:space:]]*MARKETING_VERSION = //p' | head -n1)"
    fi
    if [[ -z "$APP_BUILD" ]]; then
      APP_BUILD="$(printf '%s\n' "$build_settings" | sed -n 's/^[[:space:]]*CURRENT_PROJECT_VERSION = //p' | head -n1)"
    fi
  fi

  if [[ -z "$APP_VERSION" ]]; then
    APP_VERSION="unknown"
  fi
  if [[ -z "$APP_BUILD" ]]; then
    APP_BUILD="unknown"
  fi

  if [[ -z "${ARTIFACT_VERSION_TAG:-}" ]]; then
    local version_slug build_slug
    version_slug="$(sanitize_slug "$APP_VERSION")"
    build_slug="$(sanitize_slug "$APP_BUILD")"
    ARTIFACT_VERSION_TAG="v${version_slug}-b${build_slug}"
  fi

  SCREENSHOT_ROOT="$ARTIFACT_ROOT/screenshots/$ARTIFACT_VERSION_TAG"
  XCRESULT_ROOT="$ARTIFACT_ROOT/xcresult/$ARTIFACT_VERSION_TAG"
}

parse_args "$@"
if [[ $list_only -eq 1 ]]; then
  list_available_tests
  exit 0
fi
resolve_selected_tests
resolve_app_version_info

region_for_language() {
  case "$1" in
    en) echo "US" ;;
    de) echo "DE" ;;
    ja) echo "JP" ;;
    fr) echo "FR" ;;
    es) echo "ES" ;;
    zh-Hans) echo "CN" ;;
    nl) echo "NL" ;;
    da) echo "DK" ;;
    it) echo "IT" ;;
    fi) echo "FI" ;;
    *) echo "US" ;;
  esac
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

run_single_capture() {
  local language="$1"
  local region="$2"
  local device_name="$3"
  local udid="$4"

  local language_slug
  language_slug="$(sanitize_slug "$language")"
  local device_slug
  device_slug="$(sanitize_slug "$device_name")"

  local run_key
  run_key="${language_slug}__${device_slug}"
  local result_bundle
  result_bundle="$XCRESULT_ROOT/$run_key.xcresult"
  local export_dir
  export_dir="$XCRESULT_ROOT/export/$run_key"
  local target_dir
  target_dir="$SCREENSHOT_ROOT/$language_slug/$device_slug"

  rm -rf "$result_bundle" "$export_dir" "$target_dir"
  mkdir -p "$export_dir" "$target_dir"

  echo "Running screenshot suite for language=$language region=$region device=$device_name ($udid)" >&2

  local xcodebuild_args=(
    test
    -project "$PROJECT_PATH"
    -scheme "$SCHEME"
    -configuration "$CONFIGURATION"
    -testPlan "$TEST_PLAN"
    -destination "platform=iOS Simulator,id=$udid"
    -resultBundlePath "$result_bundle"
    -parallel-testing-enabled NO
    -parallel-testing-worker-count 1
    -maximum-parallel-testing-workers 1
    -maximum-concurrent-test-simulator-destinations 1
    -testLanguage "$language"
    -testRegion "$region"
  )
  if (( selected_count > 0 )); then
    xcodebuild_args+=("${only_testing_args[@]}")
  fi
  if [[ ${#extra_xcodebuild_args[@]} -gt 0 ]]; then
    xcodebuild_args+=("${extra_xcodebuild_args[@]}")
  fi

  SCREENSHOT_LANG="$language" \
  SCREENSHOT_DEVICE_NAME="$device_name" \
  xcodebuild "${xcodebuild_args[@]}"

  if [[ "${XCODEBUILD_DRY_RUN:-0}" == "1" ]]; then
    echo "Dry-run enabled, skipping xcresult attachment export." >&2
    cat > "$target_dir/manifest.json" <<EOF
{
  "language": "$language",
  "region": "$region",
  "device": "$device_name",
  "device_udid": "$udid",
  "result_bundle": "$result_bundle",
  "files": []
}
EOF
    echo "$language_slug|$device_slug|$target_dir/manifest.json" >> "$manifest_tmp"
    return
  fi

  xcrun xcresulttool export attachments \
    --path "$result_bundle" \
    --output-path "$export_dir"

  local copied=0
  while IFS= read -r -d '' png_path; do
    local filename
    filename="$(basename "$png_path")"
    cp "$png_path" "$target_dir/$filename"
    copied=$((copied + 1))
  done < <(find "$export_dir" -type f -name '*.png' -print0 | sort -z)

  echo "Exported $copied PNG attachments to $target_dir" >&2

  local run_manifest
  run_manifest="$target_dir/manifest.json"
  {
    echo "{"
    echo "  \"app_version\": \"$APP_VERSION\","
    echo "  \"app_build\": \"$APP_BUILD\","
    echo "  \"artifact_version_tag\": \"$ARTIFACT_VERSION_TAG\","
    echo "  \"language\": \"$language\","
    echo "  \"region\": \"$region\","
    echo "  \"device\": \"$device_name\","
    echo "  \"device_udid\": \"$udid\","
    echo "  \"result_bundle\": \"$result_bundle\","
    echo "  \"files\": ["

    local first=1
    while IFS= read -r -d '' file_path; do
      local rel
      rel="$(basename "$file_path")"
      if [[ $first -eq 0 ]]; then
        echo ","
      fi
      printf "    \"%s\"" "$rel"
      first=0
    done < <(find "$target_dir" -maxdepth 1 -type f -name '*.png' -print0 | sort -z)

    echo
    echo "  ]"
    echo "}"
  } > "$run_manifest"

  echo "$language_slug|$device_slug|$run_manifest" >> "$manifest_tmp"
}

mkdir -p "$SCREENSHOT_ROOT" "$XCRESULT_ROOT"

manifest_tmp="$SCREENSHOT_ROOT/.manifest_entries.tmp"
rm -f "$manifest_tmp"

echo "Artifact version tag: $ARTIFACT_VERSION_TAG (app $APP_VERSION build $APP_BUILD)" >&2

if (( selected_count > 0 )); then
  echo "Running selected screenshot tests only:" >&2
  test_id=""
  for test_id in "${selected_test_ids[@]-}"; do
    echo "  - $test_id" >&2
  done
fi

for language in "${LANGUAGES[@]}"; do
  region="$(region_for_language "$language")"
  for spec in "${device_specs[@]}"; do
    IFS='|' read -r device_name type_id <<< "$spec"
    udid="$(ensure_simulator "$device_name" "$type_id")"
    run_single_capture "$language" "$region" "$device_name" "$udid"
  done
done

final_manifest="$SCREENSHOT_ROOT/manifest.json"
{
  echo "{"
  echo "  \"generated_at\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\","
  echo "  \"app_version\": \"$APP_VERSION\","
  echo "  \"app_build\": \"$APP_BUILD\","
  echo "  \"artifact_version_tag\": \"$ARTIFACT_VERSION_TAG\","
  echo "  \"scheme\": \"$SCHEME\","
  echo "  \"test_plan\": \"$TEST_PLAN\","
  echo "  \"entries\": ["

  first_entry=1
  while IFS='|' read -r language_slug device_slug run_manifest; do
    [[ -z "$language_slug" ]] && continue
    if [[ $first_entry -eq 0 ]]; then
      echo ","
    fi
    printf "    {\"language\":\"%s\",\"device\":\"%s\",\"manifest\":\"%s\"}" "$language_slug" "$device_slug" "$run_manifest"
    first_entry=0
  done < "$manifest_tmp"

  echo
  echo "  ]"
  echo "}"
} > "$final_manifest"

rm -f "$manifest_tmp"

echo "Combined manifest written to $final_manifest"
