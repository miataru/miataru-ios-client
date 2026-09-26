#!/bin/bash

set -euo pipefail

if [[ "${1:-}" == "benchmark-suite" ]]; then
  shift
  exec /usr/bin/python3 "$(cd "$(dirname "$0")" && pwd)/benchmark.py" "$@"
fi

TOOL_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
PROJECT_ROOT="$(CDPATH= cd -- "$TOOL_DIR/../.." && pwd)"
GRAPH_DIR="$TOOL_DIR/graph"
BIN="$GRAPH_DIR/bin/swift-project-graph"
SHIM="$GRAPH_DIR/bin/index-store-shim.o"
HOST_LIB="$(xcrun --find swiftc | sed 's#/usr/bin/swiftc$#/usr/lib/swift/host#')"
TOOLCHAIN_LIB="$(xcode-select -p)/Toolchains/XcodeDefault.xctoolchain/usr/lib"

mkdir -p "$GRAPH_DIR/bin"

needs_build=0
[[ -x "$BIN" ]] || needs_build=1
if [[ "$needs_build" -eq 0 ]] && [[ -n "$(find "$TOOL_DIR/Sources" \( -name '*.swift' -o -name '*.c' \) -newer "$BIN" -print -quit)" ]]; then
  needs_build=1
fi

if [[ "$needs_build" -eq 1 ]]; then
  xcrun clang -O2 -c "$TOOL_DIR/Sources/IndexStoreShim.c" -o "$SHIM"
  swiftc -O -parse-as-library \
    "$TOOL_DIR"/Sources/*.swift \
    "$SHIM" \
    -I "$HOST_LIB" \
    -L "$HOST_LIB" \
    -lSwiftSyntax \
    -lSwiftParser \
    -L "$TOOLCHAIN_LIB" \
    -lIndexStore \
    -lsqlite3 \
    -Xlinker -rpath -Xlinker "$HOST_LIB" \
    -Xlinker -rpath -Xlinker "$TOOLCHAIN_LIB" \
    -o "$BIN"
fi

if [[ "${1:-}" == "enrich" ]]; then
  has_index=0
  while IFS= read -r index_path; do
    [[ -d "$PROJECT_ROOT/$index_path" ]] && has_index=1 && break
  done < <(/usr/bin/python3 -c 'import json,sys; print("\n".join(json.load(open(sys.argv[1])).get("indexStorePaths", [])))' "$TOOL_DIR/project.json")
  if [[ "$has_index" -eq 0 ]]; then
    "$TOOL_DIR/build-index.sh"
  fi
fi

exec "$BIN" --root "$PROJECT_ROOT" "$@"
