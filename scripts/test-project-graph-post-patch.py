#!/usr/bin/env python3
"""Focused tests for post-patch graph evaluation and pooled request state."""

import importlib.util
import fcntl
import sys
import tempfile
import threading
import time
from pathlib import Path

sys.dont_write_bytecode = True

SCRIPT = Path(__file__).with_name("project-graph-post-patch.py")
SPEC = importlib.util.spec_from_file_location("project_graph_post_patch", SCRIPT)
MODULE = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(MODULE)


def event(patch: str, session: str = "test-session") -> dict:
    return {"session_id": session, "tool_name": "apply_patch", "tool_input": patch}


def patch(paths: list[str], changed_lines: int = 2) -> str:
    blocks = ["*** Begin Patch"]
    for path in paths:
        blocks.extend([f"*** Update File: {path}", "@@", "-old", "+new"])
    blocks.extend(
        f"+line {index}" for index in range(max(0, changed_lines - 2 * len(paths)))
    )
    blocks.append("*** End Patch")
    return "\n".join(blocks)


def main() -> None:
    rebuild, reason, _, _ = MODULE.decision(event(patch(["README.md"])))
    assert not rebuild and "low-impact" in reason
    rebuild, reason, _, _ = MODULE.decision(event(patch(["miataru/miataru/miataruApp.swift"])))
    assert rebuild and "code graph" in reason
    rebuild, reason, _, _ = MODULE.decision(
        event(patch(["miataru/miataru.xcodeproj/project.pbxproj"]))
    )
    assert rebuild and "project structure" in reason
    rebuild, reason, _, _ = MODULE.decision(
        event(patch([f"docs/{index}.md" for index in range(8)]))
    )
    assert rebuild and "broad patch" in reason
    rebuild, reason, _, lines = MODULE.decision(
        event(patch(["README.md"], changed_lines=400))
    )
    assert rebuild and "large patch" in reason and lines >= 400
    rebuild, reason, _, lines = MODULE.decision(
        {
            "tool_name": "Write",
            "tool_input": {
                "file_path": "notes.md",
                "content": "\n".join(f"line {index}" for index in range(400)),
            },
        }
    )
    assert rebuild and "large patch" in reason and lines == 400
    rebuild, reason, _, _ = MODULE.decision(
        {"tool_name": "apply_patch", "tool_input": {}}
    )
    assert not rebuild and "commit verification" in reason

    with tempfile.TemporaryDirectory() as directory:
        MODULE.STATE_ROOT = Path(directory)
        first = MODULE.register_request(event("patch", "alpha"), "code", ["A.swift"])
        second = MODULE.register_request(event("patch", "beta"), "code", ["B.swift"])
        assert (first, second, MODULE.state_generation()) == (1, 2, 2)
        MODULE.mark_completed(first)
        state = MODULE.locked_state_update(lambda value: dict(value))
        assert state["completedGeneration"] == 1
        assert state["lastRequester"] == "beta"

        leader_ready = threading.Event()

        def finish_existing_build() -> None:
            builder_lock = MODULE.STATE_ROOT / "builder.lock"
            with builder_lock.open("a+", encoding="utf-8") as lock_file:
                fcntl.flock(lock_file.fileno(), fcntl.LOCK_EX)
                leader_ready.set()
                time.sleep(0.05)
                MODULE.mark_completed(second)

        leader = threading.Thread(target=finish_existing_build)
        leader.start()
        assert leader_ready.wait(timeout=1)
        assert MODULE.pooled_refresh(second) == 0
        leader.join(timeout=1)
        assert not leader.is_alive()
    print("PASS project graph post-patch evaluator and request pool")


if __name__ == "__main__":
    main()
