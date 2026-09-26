#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCHEME="${SCHEME:-miataru-FunctionalUI}"
# shellcheck source=./_test-common.sh
source "$SCRIPT_DIR/_test-common.sh"

run_tests "miataruTests" -testPlan "${TEST_PLAN:-FunctionalSerial}" -parallel-testing-enabled NO "$@"
