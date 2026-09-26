#!/usr/bin/env python3
"""Evaluate and pool post-patch SwiftProjectGraph refreshes across agents."""

import fcntl
import json
import os
import re
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
GRAPH_COMMAND = ROOT / "tools" / "SwiftProjectGraph" / "run.sh"
STATE_ROOT = Path(
    os.environ.get(
        "MIATARU_GRAPH_COORDINATION_ROOT",
        ROOT / "miataru" / "artifacts" / "project-graph-refresh",
    )
)
FILE_THRESHOLD = 8
LINE_THRESHOLD = 400
MAX_PASSES = 3
CODE_SUFFIXES = {".swift", ".c", ".cc", ".cpp", ".h", ".hpp", ".m", ".mm"}
STRUCTURAL_NAMES = {"Package.swift", "project.pbxproj", "project.json"}
STRUCTURAL_SUFFIXES = {".xctestplan", ".xcconfig"}
PATCH_PATH = re.compile(r"^\*\*\* (?:Add|Update|Delete) File: (.+)$", re.MULTILINE)


def tool_input(event: dict) -> object:
    for key in ("tool_input", "input", "arguments"):
        if key in event:
            return event[key]
    return None


def patch_text(value: object) -> str:
    if isinstance(value, str):
        return value
    if isinstance(value, dict):
        for key in ("patch", "input", "content", "code"):
            candidate = value.get(key)
            if isinstance(candidate, str):
                return candidate
    return ""


def changed_paths(value: object) -> list[str]:
    paths = PATCH_PATH.findall(patch_text(value))
    if isinstance(value, dict):
        for key in ("path", "file_path", "filePath"):
            candidate = value.get(key)
            if isinstance(candidate, str):
                paths.append(candidate)
    normalized = []
    for raw in paths:
        path = Path(raw.strip())
        try:
            path = path.resolve().relative_to(ROOT)
        except (OSError, ValueError):
            pass
        normalized.append(path.as_posix())
    return sorted(set(normalized))


def changed_line_count(value: object) -> int:
    text = patch_text(value)
    if PATCH_PATH.search(text):
        return sum(
            1
            for line in text.splitlines()
            if line.startswith(("+", "-")) and not line.startswith(("+++", "---"))
        )
    return len(text.splitlines())


def decision(event: dict) -> tuple[bool, str, list[str], int]:
    value = tool_input(event)
    paths = changed_paths(value)
    lines = changed_line_count(value)
    if not paths:
        return False, "unrecognized payload; defer to commit verification", paths, lines
    if len(paths) >= FILE_THRESHOLD:
        return True, f"broad patch ({len(paths)} files)", paths, lines
    if lines >= LINE_THRESHOLD:
        return True, f"large patch ({lines} changed lines)", paths, lines
    for raw in paths:
        path = Path(raw)
        if path.name in STRUCTURAL_NAMES or path.suffix in STRUCTURAL_SUFFIXES:
            return True, f"project structure changed ({raw})", paths, lines
        if path.suffix in CODE_SUFFIXES:
            return True, f"code graph changed ({raw})", paths, lines
        if raw.startswith("tools/SwiftProjectGraph/"):
            return True, f"graph implementation changed ({raw})", paths, lines
    return False, "low-impact patch; defer to commit verification", paths, lines


def locked_state_update(transform):
    STATE_ROOT.mkdir(parents=True, exist_ok=True)
    lock_path = STATE_ROOT / "requests.lock"
    state_path = STATE_ROOT / "state.json"
    with lock_path.open("a+") as handle:
        fcntl.flock(handle, fcntl.LOCK_EX)
        try:
            try:
                state = json.loads(state_path.read_text())
            except (OSError, ValueError):
                state = {"generation": 0, "completedGeneration": 0}
            result = transform(state)
            temporary = state_path.with_suffix(".tmp")
            temporary.write_text(json.dumps(state, sort_keys=True) + "\n")
            os.replace(temporary, state_path)
            return result
        finally:
            fcntl.flock(handle, fcntl.LOCK_UN)


def register_request(event: dict, reason: str, paths: list[str]) -> int:
    session_id = str(event.get("session_id", "unknown"))

    def update(state):
        state["generation"] = int(state.get("generation", 0)) + 1
        state["lastRequester"] = session_id
        state["lastReason"] = reason
        state["lastPaths"] = paths
        return state["generation"]

    return locked_state_update(update)


def state_generation() -> int:
    return locked_state_update(lambda state: int(state.get("generation", 0)))


def completed_generation() -> int:
    return locked_state_update(
        lambda state: int(state.get("completedGeneration", 0))
    )


def mark_completed(generation: int) -> None:
    def update(state):
        state["completedGeneration"] = max(
            int(state.get("completedGeneration", 0)), generation
        )

    locked_state_update(update)


def pooled_refresh(request_generation: int) -> int:
    STATE_ROOT.mkdir(parents=True, exist_ok=True)
    with (STATE_ROOT / "builder.lock").open("a+") as builder:
        try:
            fcntl.flock(builder, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            print(f"GRAPH_EVAL pooled: request={request_generation}")
            fcntl.flock(builder, fcntl.LOCK_EX)
        if completed_generation() >= request_generation:
            return 0
        for pass_index in range(1, MAX_PASSES + 1):
            time.sleep(0.2)
            target_generation = state_generation()
            result = subprocess.run(
                [str(GRAPH_COMMAND), "hook", "--quiet"],
                cwd=ROOT,
                check=False,
            )
            if result.returncode != 0:
                return result.returncode
            mark_completed(target_generation)
            if state_generation() <= target_generation:
                print(
                    "GRAPH_EVAL rebuilt: "
                    f"requests={target_generation} passes={pass_index}"
                )
                return 0
        print("GRAPH_EVAL deferred: new requests remain for commit verification")
        return 0


def main() -> int:
    try:
        event = json.load(sys.stdin) if not sys.stdin.isatty() else {}
    except json.JSONDecodeError:
        event = {}
    rebuild, reason, paths, lines = decision(event)
    if not rebuild:
        if os.environ.get("KIKUTANA_GRAPH_EVALUATOR_VERBOSE") == "1":
            print(f"GRAPH_EVAL skip: {reason}; files={len(paths)} lines={lines}")
        return 0
    generation = register_request(event, reason, paths)
    print(
        f"GRAPH_EVAL request: {reason}; generation={generation} "
        f"files={len(paths)} lines={lines}"
    )
    if os.environ.get("KIKUTANA_GRAPH_EVALUATOR_DRY_RUN") == "1":
        return 0
    return pooled_refresh(generation)


if __name__ == "__main__":
    raise SystemExit(main())
