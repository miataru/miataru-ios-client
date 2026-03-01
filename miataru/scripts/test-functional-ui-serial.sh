#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCHEME="${SCHEME:-miataru-FunctionalUI}"
# shellcheck source=./_test-common.sh
source "$SCRIPT_DIR/_test-common.sh"

run_tests "" \
  -testPlan "${TEST_PLAN:-FunctionalSerial}" \
  -parallel-testing-enabled NO \
  -parallel-testing-worker-count 1 \
  -maximum-parallel-testing-workers 1 \
  -maximum-concurrent-test-simulator-destinations 1 \
  "$@"
