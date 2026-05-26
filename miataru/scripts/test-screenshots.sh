#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PROJECT_PATH="${PROJECT_PATH:-$REPO_ROOT/miataru.xcodeproj}"
SCHEME="${SCHEME:-miataru-Screenshots}"
CONFIGURATION="${CONFIGURATION:-Debug}"
TEST_PLAN="${TEST_PLAN:-Screenshots}"
SCREENSHOT_SIMULATOR_PREFIX="${SCREENSHOT_SIMULATOR_PREFIX:-miataru Screenshots - }"

ARTIFACT_ROOT="${ARTIFACT_ROOT:-$REPO_ROOT/artifacts}"
SCREENSHOT_ROOT=""
XCRESULT_ROOT=""
APP_VERSION=""
APP_BUILD=""
ARTIFACT_VERSION_TAG=""

SUPPORTED_LANGUAGES=(en de ja fr es zh-Hans nl da it fi)
LANGUAGES=("${SUPPORTED_LANGUAGES[@]}")

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
  "device-map-overview|miataruScreenshotUITests/FeatureScreenshotScenariosUITests/test_11_device_map_overview|Karten-Uebersicht"
)

selected_inputs=()
selected_language_inputs=()
selected_device_inputs=()
selected_test_ids=()
only_testing_args=()
selected_count=0
selected_languages=()
selected_language_count=0
selected_device_specs=()
selected_device_count=0
EFFECTIVE_DEVICE_SPECS=()
list_only=0

usage() {
  cat <<'EOF'
Usage: ./scripts/test-screenshots.sh [options]

Options:
  --list, -l            List available screenshot tests and exit
  --test, -t <selector> Run only selected screenshot test(s)
  --languages, -L <csv> Limit languages (comma-separated, e.g. en,de)
  --device, -d <name>   Limit device(s) (repeatable or comma-separated)
  --help, -h            Show help

Selector forms for --test (repeatable, comma-separated also supported):
  - Scenario ID       (e.g. root-devices)
  - Test method name  (e.g. test_01_root_devices)
  - Full test ID      (e.g. miataruScreenshotUITests/FeatureScreenshotScenariosUITests/test_01_root_devices)

Selector forms for --device:
  - Full device name  (e.g. "iPhone 16 Pro Max")
  - Device slug       (e.g. iphone-16-pro-max)
  - List index        (e.g. 1 or 2, see --list)

Environment:
  SCREENSHOT_TESTS_CSV   Optional comma-separated selectors (same forms as --test)
  LANGUAGES_CSV          Optional comma-separated language list (same as --languages)
  DEVICE_NAMES_CSV       Optional comma-separated device selectors (same as --device)
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

strip_xcresult_attachment_suffix() {
  local value="$1"
  # xcresult may append "_<repetition>_<UUID>" to suggested names.
  printf '%s' "$value" | sed -E 's/_[0-9]+_[0-9A-Fa-f-]{36}(\.[[:alnum:]]+)$/\1/'
}

method_name_from_test_identifier() {
  local test_identifier="$1"
  local method="${test_identifier##*/}"
  method="${method%%(*}"
  printf '%s' "$method"
}

sanitize_filename_preserving_extension() {
  local filename="$1"
  local extension=""
  local stem="$filename"
  if [[ "$filename" == *.* ]]; then
    extension=".${filename##*.}"
    stem="${filename%.*}"
  fi
  stem="$(sanitize_slug "$stem")"
  if [[ -z "$stem" ]]; then
    stem="screenshot"
  fi
  printf '%s%s' "$stem" "$extension"
}

build_screenshot_filename_from_attachment() {
  local suggested_name="$1"
  local test_identifier="$2"

  local cleaned_name
  cleaned_name="$(strip_xcresult_attachment_suffix "$suggested_name")"
  if [[ -z "$cleaned_name" || "$cleaned_name" == "null" ]]; then
    cleaned_name="screenshot.png"
  fi

  local method_name
  method_name="$(method_name_from_test_identifier "$test_identifier")"
  if [[ -n "$method_name" ]]; then
    cleaned_name="$(sanitize_slug "$method_name")__$cleaned_name"
  fi

  sanitize_filename_preserving_extension "$cleaned_name"
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

list_supported_languages() {
  echo
  echo "Supported language selectors:"
  local lang
  for lang in "${SUPPORTED_LANGUAGES[@]}"; do
    echo "  - $lang"
  done
}

list_available_devices() {
  echo
  printf "%-3s %-26s %s\n" "Nr" "Device Slug" "Device Name"
  printf "%-3s %-26s %s\n" "---" "--------------------------" "------------------------------"
  local i=1
  local spec device_name _ slug
  for spec in "${device_specs[@]}"; do
    IFS='|' read -r device_name _ <<< "$spec"
    slug="$(sanitize_slug "$device_name")"
    printf "%-3s %-26s %s\n" "$i" "$slug" "$device_name"
    i=$((i + 1))
  done
}

is_supported_language() {
  local candidate="$1"
  local candidate_lower
  candidate_lower="$(printf '%s' "$candidate" | tr '[:upper:]' '[:lower:]')"
  local lang
  for lang in "${SUPPORTED_LANGUAGES[@]}"; do
    local lang_lower
    lang_lower="$(printf '%s' "$lang" | tr '[:upper:]' '[:lower:]')"
    if [[ "$lang_lower" == "$candidate_lower" ]]; then
      printf '%s' "$lang"
      return
    fi
  done
  printf ''
}

append_language_if_missing() {
  local language="$1"
  local existing
  for existing in "${selected_languages[@]-}"; do
    if [[ "$existing" == "$language" ]]; then
      return
    fi
  done
  selected_languages+=("$language")
  selected_language_count=$((selected_language_count + 1))
}

append_device_spec_if_missing() {
  local spec="$1"
  local existing
  for existing in "${selected_device_specs[@]-}"; do
    if [[ "$existing" == "$spec" ]]; then
      return
    fi
  done
  selected_device_specs+=("$spec")
  selected_device_count=$((selected_device_count + 1))
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
      --languages|-L)
        if [[ $# -lt 2 ]]; then
          echo "Missing value for $1" >&2
          usage >&2
          exit 1
        fi
        selected_language_inputs+=("$2")
        shift 2
        ;;
      --device|-d)
        if [[ $# -lt 2 ]]; then
          echo "Missing value for $1" >&2
          usage >&2
          exit 1
        fi
        selected_device_inputs+=("$2")
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

resolve_device_selector() {
  local selector="$1"
  local selector_lower
  selector_lower="$(printf '%s' "$selector" | tr '[:upper:]' '[:lower:]')"
  local spec device_name device_type slug index=1

  for spec in "${device_specs[@]}"; do
    IFS='|' read -r device_name device_type <<< "$spec"
    slug="$(sanitize_slug "$device_name")"
    local slug_lower
    slug_lower="$(printf '%s' "$slug" | tr '[:upper:]' '[:lower:]')"
    if [[ "$selector" == "$device_name" || "$selector_lower" == "$slug_lower" || "$selector" == "$index" ]]; then
      printf '%s' "$spec"
      return
    fi
    index=$((index + 1))
  done

  printf ''
}

resolve_selected_tests() {
  local input selector resolved
  if [[ -n "${SCREENSHOT_TESTS_CSV:-}" ]]; then
    selected_inputs+=("$SCREENSHOT_TESTS_CSV")
  fi

  # Keep loops nounset-safe across Bash variants when the array is empty.
  for input in "${selected_inputs[@]-}"; do
    IFS=',' read -r -a parts <<< "$input"
    local selector_raw
    for selector_raw in "${parts[@]-}"; do
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

resolve_selected_languages() {
  local input language_raw language normalized
  if [[ -n "${LANGUAGES_CSV:-}" ]]; then
    selected_language_inputs+=("$LANGUAGES_CSV")
  fi

  for input in "${selected_language_inputs[@]-}"; do
    IFS=',' read -r -a parts <<< "$input"
    for language_raw in "${parts[@]-}"; do
      language="$(trim_whitespace "$language_raw")"
      if [[ -z "$language" ]]; then
        continue
      fi
      normalized="$(is_supported_language "$language")"
      if [[ -z "$normalized" ]]; then
        echo "Unknown language selector: $language" >&2
        list_supported_languages >&2
        exit 1
      fi
      append_language_if_missing "$normalized"
    done
  done

  if (( selected_language_count > 0 )); then
    LANGUAGES=("${selected_languages[@]}")
  fi
}

resolve_selected_devices() {
  local input selector_raw selector resolved
  if [[ -n "${DEVICE_NAMES_CSV:-}" ]]; then
    selected_device_inputs+=("$DEVICE_NAMES_CSV")
  fi

  for input in "${selected_device_inputs[@]-}"; do
    IFS=',' read -r -a parts <<< "$input"
    for selector_raw in "${parts[@]-}"; do
      selector="$(trim_whitespace "$selector_raw")"
      if [[ -z "$selector" ]]; then
        continue
      fi
      resolved="$(resolve_device_selector "$selector")"
      if [[ -z "$resolved" ]]; then
        echo "Unknown device selector: $selector" >&2
        list_available_devices >&2
        exit 1
      fi
      append_device_spec_if_missing "$resolved"
    done
  done

  if (( selected_device_count > 0 )); then
    EFFECTIVE_DEVICE_SPECS=("${selected_device_specs[@]}")
  else
    EFFECTIVE_DEVICE_SPECS=("${device_specs[@]}")
  fi
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
  list_supported_languages
  list_available_devices
  exit 0
fi
resolve_selected_tests
resolve_selected_languages
resolve_selected_devices
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

apple_language_for_language() {
  case "$1" in
    zh-Hans) echo "zh-Hans" ;;
    *) echo "${1%%-*}" ;;
  esac
}

apple_locale_for_language_region() {
  local language="$1"
  local region="$2"
  case "$language" in
    zh-Hans) echo "zh_Hans_${region}" ;;
    *) echo "${language//-/_}_${region}" ;;
  esac
}

configure_simulator_locale() {
  local udid="$1"
  local language="$2"
  local region="$3"
  local apple_language
  apple_language="$(apple_language_for_language "$language")"
  local apple_locale
  apple_locale="$(apple_locale_for_language_region "$language" "$region")"

  echo "Configuring simulator locale: language=$apple_language locale=$apple_locale ($udid)" >&2

  xcrun simctl boot "$udid" >/dev/null 2>&1 || true
  xcrun simctl bootstatus "$udid" -b >/dev/null
  xcrun simctl spawn "$udid" defaults write NSGlobalDomain AppleLanguages -array "$apple_language"
  xcrun simctl spawn "$udid" defaults write NSGlobalDomain AppleLocale -string "$apple_locale"
  xcrun simctl terminate "$udid" com.miataru.ios >/dev/null 2>&1 || true
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

screenshot_simulator_name() {
  local device_name="$1"
  printf '%s%s' "$SCREENSHOT_SIMULATOR_PREFIX" "$device_name"
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
  configure_simulator_locale "$udid" "$language" "$region"

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
  SCREENSHOT_REGION="$region" \
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
  local export_manifest
  export_manifest="$export_dir/manifest.json"
  if [[ -f "$export_manifest" ]] && command -v jq >/dev/null 2>&1; then
    local exported_file suggested_name test_identifier source_path destination_file destination_path unique_index stem extension
    while IFS=$'\t' read -r exported_file suggested_name test_identifier; do
      [[ -z "$exported_file" ]] && continue
      case "$exported_file" in
        *.png|*.PNG) ;;
        *) continue ;;
      esac

      source_path="$export_dir/$exported_file"
      if [[ ! -f "$source_path" ]]; then
        source_path="$(find "$export_dir" -type f -name "$exported_file" -print -quit)"
      fi
      if [[ -z "$source_path" || ! -f "$source_path" ]]; then
        echo "Warning: exported attachment file not found: $exported_file" >&2
        continue
      fi

      if [[ -z "$suggested_name" || "$suggested_name" == "null" ]]; then
        suggested_name="$exported_file"
      fi
      destination_file="$(build_screenshot_filename_from_attachment "$suggested_name" "$test_identifier")"
      destination_path="$target_dir/$destination_file"
      unique_index=2
      while [[ -e "$destination_path" ]]; do
        if [[ "$destination_file" == *.* ]]; then
          stem="${destination_file%.*}"
          extension=".${destination_file##*.}"
        else
          stem="$destination_file"
          extension=""
        fi
        destination_path="$target_dir/${stem}-${unique_index}${extension}"
        unique_index=$((unique_index + 1))
      done

      cp "$source_path" "$destination_path"
      copied=$((copied + 1))
    done < <(jq -r '.[] | .testIdentifier as $test_id | .attachments[] | [.exportedFileName, .suggestedHumanReadableName, $test_id] | @tsv' "$export_manifest")
  else
    if [[ -f "$export_manifest" ]]; then
      echo "Warning: jq not found, falling back to exported attachment GUID names." >&2
    fi
    while IFS= read -r -d '' png_path; do
      local filename
      filename="$(basename "$png_path")"
      cp "$png_path" "$target_dir/$filename"
      copied=$((copied + 1))
    done < <(find "$export_dir" -type f -name '*.png' -print0 | sort -z)
  fi

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

if (( selected_language_count > 0 )); then
  echo "Running selected languages only: ${LANGUAGES[*]}" >&2
fi

if (( selected_device_count > 0 )); then
  echo "Running selected devices only:" >&2
  selected_device_line=""
  for selected_device_line in "${EFFECTIVE_DEVICE_SPECS[@]}"; do
    IFS='|' read -r selected_device_name _ <<< "$selected_device_line"
    echo "  - $selected_device_name" >&2
  done
fi

for language in "${LANGUAGES[@]}"; do
  region="$(region_for_language "$language")"
  for spec in "${EFFECTIVE_DEVICE_SPECS[@]}"; do
    IFS='|' read -r device_name type_id <<< "$spec"
    udid="$(ensure_simulator "$(screenshot_simulator_name "$device_name")" "$type_id")"
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
