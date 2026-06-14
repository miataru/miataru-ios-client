#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GIT_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)"
cd "$GIT_ROOT"

pathspec=("$@")

run_git() {
  if [[ ${#pathspec[@]} -gt 0 ]]; then
    git "$@" -- "${pathspec[@]}"
  else
    git "$@"
  fi
}

print_section() {
  printf "\n== %s ==\n" "$1"
}

print_section "Status"
run_git status --short

print_section "Changed Files"
changed_files="$(
  {
    run_git diff --name-only
    run_git diff --name-only --cached
    if [[ ${#pathspec[@]} -gt 0 ]]; then
      git ls-files --others --exclude-standard -- "${pathspec[@]}"
    else
      git ls-files --others --exclude-standard
    fi
  } | sort -u
)"

if [[ -n "$changed_files" ]]; then
  printf "%s\n" "$changed_files"
else
  echo "No changed files."
fi

print_section "Changed Tests"
test_files="$(printf "%s\n" "$changed_files" | rg '(^|/)(miataruTests|miataruUITests|miataruScreenshotUITests)/|Tests?\.swift$|\.xctestplan$|(^|/)scripts/test-' || true)"

if [[ -n "$test_files" ]]; then
  printf "%s\n" "$test_files"
else
  echo "No changed test files detected."
fi

print_section "Documentation Hits"
if [[ -n "$test_files" ]]; then
  keywords="$(
    printf "%s\n" "$test_files" |
      awk -F/ '{print $NF}' |
      sed -E 's/\.(swift|xctestplan|sh)$//; s/[^[:alnum:]_]+/|/g' |
      awk 'NF { print }' |
      paste -sd'|' -
  )"

  if [[ -n "$keywords" ]]; then
    set +e
    rg -n --max-count 4 "$keywords" documentation/test-katalog.md documentation/test-gap-matrix.md | head -n 40
    status="${PIPESTATUS[0]}"
    set -e
    if [[ "$status" -ne 0 ]]; then
      echo "No matching test documentation hits."
    fi
  else
    echo "No useful test keywords found."
  fi
else
  set +e
  rg -n --max-count 4 'test-katalog|test-gap-matrix|xcodebuild|TEST_OUTPUT|Token Discipline' miataru/AGENTS.md miataru/DEVELOPMENT.md documentation/README.md | head -n 40
  status="${PIPESTATUS[0]}"
  set -e
  if [[ "$status" -ne 0 ]]; then
    echo "No documentation hits."
  fi
fi
