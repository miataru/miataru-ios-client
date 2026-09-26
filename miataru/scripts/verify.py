#!/usr/bin/env python3
"""Miataru's risk-based, evidence-retaining test entry point."""

from __future__ import annotations

import argparse
import fnmatch
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
from datetime import datetime, timezone


ROOT = Path(__file__).resolve().parents[2]
APP = ROOT / "miataru"
SCRIPTS = APP / "scripts"
ARTIFACTS = APP / "artifacts" / "verification"
MAP = SCRIPTS / "verification-map.json"


def command(*args: str, cwd: Path = ROOT) -> bytes:
    return subprocess.check_output(args, cwd=cwd)


def changed_paths(base: str | None = None) -> list[str]:
    paths: set[str] = set()
    if base:
        paths.update(filter(None, command("git", "diff", "--name-only", "-z", f"{base}...HEAD").decode().split("\0")))
    paths.update(filter(None, command("git", "diff", "--name-only", "-z", "HEAD").decode().split("\0")))
    paths.update(filter(None, command("git", "ls-files", "--others", "--exclude-standard", "-z").decode().split("\0")))
    return sorted(paths)


def matches(path: str, patterns: list[str]) -> bool:
    return any(fnmatch.fnmatchcase(path, pattern) for pattern in patterns)


def available_suites(target: str) -> set[str]:
    folder = APP / target
    return {path.stem for path in folder.glob("*Tests.swift")}


def select(paths: list[str], config: dict, semantic_paths: list[str] | None = None) -> dict:
    unit: set[str] = set()
    ui: set[str] = set()
    reasons: list[str] = []
    release = False
    full_unit = False
    full_ui = False
    for path in paths:
        if matches(path, config["fullReleasePaths"]):
            release = True
            reasons.append(f"release infrastructure: {path}")
        if matches(path, config["fullUIPaths"]):
            full_ui = True
            reasons.append(f"shared UI/test fixture: {path}")
        if path.startswith("miataru/miataruTests/") and path.endswith(".swift"):
            suite = Path(path).stem
            if (ROOT / path).exists() and suite in available_suites("miataruTests"):
                unit.add(suite)
                reasons.append(f"changed unit suite: {suite}")
            else:
                full_unit = True
                reasons.append(f"deleted or unrecognized unit test: {path}")
        elif path.startswith("miataru/miataruUITests/") and path.endswith(".swift"):
            full_ui = True
            reasons.append(f"changed UI test: {path}")
        elif path.startswith("miataru/miataruScreenshotUITests/") and path.endswith(".swift"):
            reasons.append(f"screenshot capture changed; review screenshot lane: {path}")
        mapped = False
        for rule in config["rules"]:
            if matches(path, rule["paths"]):
                mapped = True
                unit.update(rule.get("unit", []))
                ui.update(rule.get("ui", []))
                full_ui |= rule.get("fullUI", False)
                reasons.append(f"{rule['name']}: {path}")
        if matches(path, config["productivePaths"]) and not mapped:
            full_unit = True
            full_ui = True
            reasons.append(f"unmapped productive source: {path}")
    for path in semantic_paths or []:
        if path.startswith("miataru/miataruTests/"):
            unit.add(Path(path).stem)
            reasons.append(f"semantic dependant: {path}")
        elif path.startswith("miataru/miataruUITests/"):
            ui.add(Path(path).stem)
            reasons.append(f"semantic dependant: {path}")
    known_unit = available_suites("miataruTests")
    known_ui = available_suites("miataruUITests")
    unknown = (unit - known_unit) | (ui - known_ui)
    if unknown:
        raise ValueError(f"verification map references absent suites: {sorted(unknown)}")
    if known_unit and len(unit) / len(known_unit) >= config["fullUnitThreshold"]:
        full_unit = True
        reasons.append("selected at least 25% of unit suites")
    if release:
        full_unit = full_ui = True
    return {
        "release": release,
        "fullUnit": full_unit,
        "fullUI": full_ui,
        "unit": [] if full_unit else sorted(unit),
        "ui": [] if full_ui else sorted(ui),
        "reasons": reasons,
        "paths": paths,
    }


def fingerprint(paths: list[str]) -> str:
    digest = hashlib.sha256()
    digest.update(command("git", "rev-parse", "HEAD"))
    digest.update(command("git", "diff", "--binary", "HEAD"))
    tracked = set(command("git", "ls-files", "--cached").decode().splitlines())
    for path in paths:
        file = ROOT / path
        if file.is_file() and path not in tracked:
            digest.update(path.encode())
            digest.update(file.read_bytes())
    return digest.hexdigest()[:16]


def prepare_graph() -> None:
    graph = ROOT / "tools" / "SwiftProjectGraph" / "run.sh"
    subprocess.run([str(graph), "build", "--quiet"], cwd=ROOT, check=True)
    subprocess.run([str(graph), "test"], cwd=ROOT, check=True)


def semantic_test_paths(paths: list[str]) -> list[str]:
    sources = [path for path in paths if path.endswith(".swift") and (ROOT / path).exists()]
    if not sources:
        return []
    graph = ROOT / "tools" / "SwiftProjectGraph" / "run.sh"
    try:
        payload = json.loads(command(str(graph), "impact", "--format", "json", "--targets-json", json.dumps(sources)))
        return sorted({row["path"] for row in payload.get("tests", []) if row.get("path")})
    except (OSError, KeyError, ValueError, subprocess.CalledProcessError, json.JSONDecodeError):
        print("Graph impact unavailable; using versioned path fallbacks", file=sys.stderr)
        return []


def write_status(lane: str, data: dict) -> None:
    ARTIFACTS.mkdir(parents=True, exist_ok=True)
    destination = ARTIFACTS / f"{lane}-status.json"
    temporary = destination.with_suffix(".tmp")
    temporary.write_text(json.dumps(data, indent=2, sort_keys=True) + "\n")
    temporary.replace(destination)


def validate_result(bundle: Path) -> dict:
    payload = json.loads(command("xcrun", "xcresulttool", "get", "test-results", "summary", "--path", str(bundle), "--compact"))
    count = int(payload.get("totalTestCount", 0))
    failures = int(payload.get("failedTests", 0))
    if payload.get("result") != "Passed" or count < 1 or failures:
        raise ValueError(f"result={payload.get('result')} tests={count} failed={failures}")
    return {
        "tests": count,
        "passed": int(payload.get("passedTests", 0)),
        "skipped": int(payload.get("skippedTests", 0)),
        "failed": failures,
    }


def run_xcode(lane: str, selectors: list[str], paths: list[str]) -> bool:
    subprocess.run([sys.executable, str(SCRIPTS / "verify-metadata.py")], check=True, cwd=ROOT)
    ARTIFACTS.mkdir(parents=True, exist_ok=True)
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    bundle = ARTIFACTS / f"{lane}-{stamp}-{os.getpid()}.xcresult"
    if lane == "unit":
        script = SCRIPTS / "test-unit.sh"
    elif lane == "ui":
        script = SCRIPTS / "test-ui.sh"
    else:
        raise ValueError(lane)
    args = [str(script)]
    for selector in selectors:
        args.append(f"-only-testing:{'miataruTests' if lane == 'unit' else 'miataruUITests'}/{selector}")
    env = {**os.environ, "RESULT_BUNDLE_PATH": str(bundle), "TEST_OUTPUT": "summary"}
    status = {
        "lane": lane, "result": "running", "pid": os.getpid(), "startedAt": stamp,
        "head": command("git", "rev-parse", "HEAD").decode().strip(),
        "fingerprint": fingerprint(paths), "selectors": selectors, "resultBundle": str(bundle),
    }
    write_status(lane, status)
    print(f"START {lane}: {bundle}", flush=True)
    result = subprocess.run(args, cwd=APP, env=env, check=False)
    try:
        evidence = validate_result(bundle)
        if result.returncode:
            raise ValueError(f"xcodebuild exit={result.returncode} despite result bundle")
        status.update(evidence)
        status["result"] = "passed"
    except (OSError, ValueError, subprocess.CalledProcessError, json.JSONDecodeError) as error:
        status["result"] = "failed"
        status["error"] = str(error)
    status["finishedAt"] = datetime.now(timezone.utc).isoformat()
    write_status(lane, status)
    print(f"{status['result'].upper()} {lane}: tests={status.get('tests', '?')} skipped={status.get('skipped', '?')} bundle={bundle}")
    return status["result"] == "passed"


def run_release(paths: list[str]) -> bool:
    """Retain separate complete bundles so each serial Xcode lane can finish."""
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    status = {
        "lane": "release", "result": "running", "pid": os.getpid(), "startedAt": stamp,
        "head": command("git", "rev-parse", "HEAD").decode().strip(),
        "fingerprint": fingerprint(paths), "resultBundles": [], "tests": 0,
        "passed": 0, "skipped": 0, "failed": 0,
    }
    write_status("release", status)
    for lane in ("unit", "ui"):
        passed = run_xcode(lane, [], paths)
        evidence = json.loads((ARTIFACTS / f"{lane}-status.json").read_text())
        status["resultBundles"].append(evidence["resultBundle"])
        for key in ("tests", "passed", "skipped", "failed"):
            status[key] += evidence.get(key, 0)
        if not passed:
            status["result"] = "failed"
            status["error"] = f"{lane} lane failed: {evidence.get('error', 'unknown error')}"
            break
        write_status("release", status)
    else:
        status["result"] = "passed"
    status["finishedAt"] = datetime.now(timezone.utc).isoformat()
    write_status("release", status)
    print(f"{status['result'].upper()} release: tests={status['tests']} skipped={status['skipped']} bundles={status['resultBundles']}")
    return status["result"] == "passed"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("mode", choices=("affected", "unit", "ui", "release", "tooling", "status"))
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--explain", action="store_true")
    parser.add_argument("--base")
    parser.add_argument("--lane", choices=("unit", "ui", "release"))
    parser.add_argument("--only", action="append", default=[])
    args = parser.parse_args()
    if args.mode == "status":
        if not args.lane:
            parser.error("status requires --lane")
        path = ARTIFACTS / f"{args.lane}-status.json"
        if not path.exists():
            print(f"STATUS {args.lane}: unavailable")
            return 3
        print(path.read_text() if args.explain else json.dumps({k: json.loads(path.read_text()).get(k) for k in ("lane", "result", "tests", "error", "resultBundle", "resultBundles")}))
        return 0
    config = json.loads(MAP.read_text())
    paths = changed_paths(args.base)
    if args.mode == "tooling":
        subprocess.run(["bash", "-n", str(SCRIPTS / "verify.sh"), str(SCRIPTS / "_test-common.sh")], check=True)
        subprocess.run([sys.executable, "-m", "unittest", "discover", "-s", str(SCRIPTS), "-p", "test_verify.py"], check=True)
        subprocess.run([sys.executable, str(SCRIPTS / "verify-metadata.py")], check=True)
        subprocess.run([sys.executable, str(SCRIPTS / "documentation-inventory.py"), "--check"], check=True)
        subprocess.run([sys.executable, str(SCRIPTS / "check-doc-links.py")], check=True)
        subprocess.run([sys.executable, str(ROOT / "scripts" / "test-codex-hooks.py")], check=True)
        subprocess.run([sys.executable, str(ROOT / "scripts" / "test-project-graph-post-patch.py")], check=True)
        prepare_graph()
        print("PASS tooling")
        return 0
    if args.mode == "affected":
        prepare_graph()
        plan = select(paths, config, semantic_test_paths(paths))
        print(json.dumps(plan if args.explain or args.dry_run else {key: plan[key] for key in ("release", "fullUnit", "fullUI", "unit", "ui")}, indent=2))
        if args.dry_run:
            return 0
        if plan["release"]:
            return 0 if run_release(paths) else 1
        if not plan["fullUnit"] and not plan["fullUI"] and not plan["unit"] and not plan["ui"]:
            print("PASS affected: documentation/configuration only; no app tests selected")
            return 0
        if (plan["fullUnit"] or plan["unit"]) and not run_xcode("unit", plan["unit"], paths):
            return 1
        if (plan["fullUI"] or plan["ui"]) and not run_xcode("ui", plan["ui"], paths):
            return 1
        return 0
    if args.dry_run or args.explain or args.base:
        parser.error("--dry-run, --explain and --base are only valid with affected (or status --explain)")
    if args.mode == "release" and args.only:
        parser.error("release requires complete Unit and UI lanes; use unit or ui for focused selectors")
    prepare_graph()
    if args.mode == "release":
        return 0 if run_release(paths) else 1
    return 0 if run_xcode(args.mode, args.only, paths) else 1


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (ValueError, subprocess.CalledProcessError, OSError) as error:
        print(f"FAIL verification: {error}", file=sys.stderr)
        raise SystemExit(1)
