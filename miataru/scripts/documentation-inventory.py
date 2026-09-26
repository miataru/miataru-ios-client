#!/usr/bin/env python3
"""Inventory every repository document without reading historical chat content."""

from __future__ import annotations

import argparse
from pathlib import Path
import subprocess
import sys


ROOT = Path(__file__).resolve().parents[2]
OUTPUT = "documentation/DOCUMENTATION_INVENTORY.tsv"
HEADER = "Path\tPurpose\tStatus\tAuthority\tAction\n"
EXTENSIONS = (".md", ".mdc", ".txt", ".rst", ".adoc", ".rtf", ".pdf", ".graffle", ".webloc")


def documents() -> list[str]:
    tracked = subprocess.check_output(["git", "ls-files", "-z"], cwd=ROOT).decode().split("\0")
    untracked = subprocess.check_output(["git", "ls-files", "--others", "--exclude-standard", "-z"], cwd=ROOT).decode().split("\0")
    paths = set(filter(None, tracked + untracked)) | {OUTPUT}
    return sorted(path for path in paths if path.endswith(EXTENSIONS) or path.endswith(".cursorrules") or path == "LICENSE")


def clean(value: str) -> str:
    return " ".join(value.replace("\t", " ").replace("\n", " ").replace("|", "/").split())


def heading(path: str) -> str:
    if path.startswith("miataru/.specstory/history/"):
        return "Historical chat record"
    file = ROOT / path
    if not file.exists() or file.suffix not in (".md", ".mdc"):
        return clean(file.stem.replace("-", " ").replace("_", " "))
    with file.open(errors="replace") as handle:
        for _ in range(24):
            line = handle.readline()
            if not line:
                break
            if line.startswith("# "):
                return clean(line[2:])
    return clean(file.stem.replace("-", " ").replace("_", " "))


def classify(path: str) -> tuple[str, str, str]:
    if path == OUTPUT:
        return "Current", "Tracked repository documents", "Regenerate after documentation changes"
    if path.startswith("miataru/.specstory/history/"):
        return "historisch", "Git history", "Retain; never require new chat records"
    if path.startswith("miataru/.cursor/plans/"):
        return "historisch", "Current code and living topic docs", "Keep as evidence; see documentation index"
    if path.startswith("Assets/UI Wireframes/") or path.startswith("Assets/App Icons/"):
        return "historisch", "Original design/reference assets", "Retain as historical visual or external reference"
    if path.startswith("miataru/Libraries/") and not path.startswith("miataru/Libraries/MiataruClientSwift/"):
        return "Current", "Vendored upstream snapshot", "Retain external text; recheck on dependency update"
    if path.startswith("documentation/audits/") or path in {
        "documentation/rotation-lock-deprecation-fix-2026-03-03.md",
        "documentation/settings-advanced-options-hitbox-2026-06-11.md",
        "documentation/test-build-repair-report-2026-02-27.md",
    }:
        return "historisch", "Dated implementation evidence", "Retain; do not cite as Current without recheck"
    if path.startswith("documentation/Intent-Sprint/"):
        name = Path(path).name
        if name.startswith(("00-", "05-")):
            return "P0 target", "App Intents code and living reference", "Keep implemented and planned stages distinct"
        return "historisch", "App Intents code and living reference", "Retain stage evidence; check live status in current reference"
    if path.startswith("documentation/Places-Sprint/"):
        return "P0 target", "Place store and App Intents code", "Retain future visible-UI contract"
    if path in ("miataru/APP_STORE_DESCRIPTION.md",):
        return "Current", "Verified app behavior and release record", "Update copy only for accepted capabilities"
    if path in ("miataru/CHANGELOG.md",):
        return "Current", "Completed commits and release evidence", "Append completed changes under project version"
    if path in ("documentation/test-katalog.md", "documentation/test-gap-matrix.md"):
        return "Current", "Active test sources, schemes, result bundles", "Synchronize when tests change"
    if path.startswith("documentation/"):
        return "Current", "App code and project settings", "Keep topic facts and links verified"
    if path.startswith("tools/SwiftProjectGraph/"):
        return "Current", "SwiftProjectGraph source and project.json", "Keep Miataru commands and limits accurate"
    if path == "3rd party licenses.md" or path == "LICENSE":
        return "Current", "License files and dependency manifests", "Review when dependencies change"
    if path.endswith("AGENTS.md") or path.endswith(".cursorrules") or path.endswith(".mdc"):
        return "Current", "Active repository workflow", "Keep requirements consistent across tools"
    return "Current", "App code and project settings", "Keep verified against current implementation"


def render() -> str:
    rows = [HEADER]
    for path in documents():
        status, authority, action = classify(path)
        rows.append("\t".join(map(clean, (path, heading(path), status, authority, action))) + "\n")
    return "".join(rows)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--write", action="store_true")
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    if args.write == args.check:
        parser.error("choose exactly one of --write or --check")
    output = ROOT / OUTPUT
    expected = render()
    if args.write:
        output.write_text(expected)
        print(f"Wrote {OUTPUT}: {expected.count(chr(10)) - 1} entries")
        return 0
    if not output.exists() or output.read_text() != expected:
        print(f"FAIL documentation inventory: run miataru/scripts/documentation-inventory.py --write", file=sys.stderr)
        return 1
    print(f"PASS documentation inventory: {expected.count(chr(10)) - 1} entries")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
