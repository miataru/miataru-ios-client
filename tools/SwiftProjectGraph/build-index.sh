#!/bin/bash
set -euo pipefail

TOOL_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
ROOT="$(CDPATH= cd -- "$TOOL_DIR/../.." && pwd)"
DERIVED_DATA="$ROOT/.build/swiftgraph-index"
INDEX_STORE="$DERIVED_DATA/Index.noindex/DataStore"

mkdir -p "$ROOT/.build"
xcodebuild build \
  -quiet \
  -project "$ROOT/miataru/miataru.xcodeproj" \
  -scheme miataru \
  -destination 'generic/platform=iOS' \
  -derivedDataPath "$DERIVED_DATA" \
  CODE_SIGNING_ALLOWED=NO \
  COMPILER_INDEX_STORE_ENABLE=YES

if [[ ! -d "$INDEX_STORE" ]]; then
  echo "SwiftProjectGraph: Xcode build succeeded without an IndexStore at $INDEX_STORE" >&2
  exit 1
fi
echo "SwiftProjectGraph IndexStore ready: $INDEX_STORE"
