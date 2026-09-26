#!/usr/bin/env python3
"""Check local Markdown destinations in living repository documents."""

from __future__ import annotations

import csv
from pathlib import Path
import re
import sys
from urllib.parse import unquote


ROOT = Path(__file__).resolve().parents[2]
INVENTORY = ROOT / "documentation/DOCUMENTATION_INVENTORY.tsv"
LINK = re.compile(r"(?<!!)\[[^\]]+\]\((<[^>]+>|[^)]+)\)")


def main() -> int:
    failures: list[str] = []
    checked = 0
    with INVENTORY.open(newline="") as handle:
        for row in csv.DictReader(handle, delimiter="\t"):
            path = row["Path"]
            if row["Status"] != "Current" or not path.endswith(".md"):
                continue
            if path.startswith("miataru/Libraries/") and "MiataruClientSwift/README.md" not in path:
                continue
            source = ROOT / path
            if not source.is_file():
                failures.append(f"missing living document: {path}")
                continue
            body = re.sub(r"(?ms)^```.*?^```", "", source.read_text(errors="replace"))
            for match in LINK.finditer(body):
                value = match.group(1).strip("<>").split("#", 1)[0]
                if not value or re.match(r"^[a-z][a-z0-9+.-]*:", value, re.I):
                    continue
                checked += 1
                target = (source.parent / unquote(value)).resolve()
                if not target.is_relative_to(ROOT) or not target.exists():
                    failures.append(f"{path}: {value}")
    for item in failures:
        print(f"FAIL link: {item}", file=sys.stderr)
    print(f"Checked {checked} local links in Current Markdown documents")
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
