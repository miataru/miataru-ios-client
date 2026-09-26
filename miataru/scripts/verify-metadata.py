#!/usr/bin/env python3
"""Check the version contract shared by the app and its WidgetKit extension."""

from __future__ import annotations

import json
from pathlib import Path
import plistlib
import subprocess
import sys


ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT / "miataru.xcodeproj" / "project.pbxproj"


def configurations(objects: dict, owner: dict) -> dict[str, dict]:
    config_list = objects[owner["buildConfigurationList"]]
    return {
        objects[identifier]["name"]: objects[identifier]["buildSettings"]
        for identifier in config_list["buildConfigurations"]
    }


def check(project: Path = PROJECT) -> tuple[str, str]:
    payload = subprocess.check_output(["plutil", "-convert", "json", "-o", "-", str(project)])
    objects = json.loads(payload)["objects"]
    root = next(value for value in objects.values() if value.get("isa") == "PBXProject")
    targets = {
        value.get("name"): value
        for value in objects.values()
        if value.get("isa") == "PBXNativeTarget"
    }
    project_configs = configurations(objects, root)
    app_configs = configurations(objects, targets["miataru"])
    widget_configs = configurations(objects, targets["miataruWidgets"])
    resolved: set[tuple[str, str]] = set()
    for name in ("Debug", "Release"):
        if name not in project_configs or name not in app_configs or name not in widget_configs:
            raise ValueError(f"missing {name} configuration")
        project_values = project_configs[name]
        app_values = {**project_values, **app_configs[name]}
        widget_values = {**project_values, **widget_configs[name]}
        app_pair = (str(app_values.get("MARKETING_VERSION", "")), str(app_values.get("CURRENT_PROJECT_VERSION", "")))
        widget_pair = (str(widget_values.get("MARKETING_VERSION", "")), str(widget_values.get("CURRENT_PROJECT_VERSION", "")))
        if app_pair != widget_pair:
            raise ValueError(f"{name}: app {app_pair} differs from widget {widget_pair}")
        if not app_pair[0] or not app_pair[1].isdigit() or int(app_pair[1]) < 1:
            raise ValueError(f"{name}: invalid version/build {app_pair}")
        resolved.add(app_pair)
    if len(resolved) != 1:
        raise ValueError(f"Debug and Release metadata differ: {resolved}")
    widget_plist = project.parent.parent / "miataruWidgets" / "Info.plist"
    with widget_plist.open("rb") as handle:
        info = plistlib.load(handle)
    if info.get("CFBundleVersion") != "$(CURRENT_PROJECT_VERSION)":
        raise ValueError("widget CFBundleVersion must inherit CURRENT_PROJECT_VERSION")
    if info.get("CFBundleShortVersionString") != "$(MARKETING_VERSION)":
        raise ValueError("widget CFBundleShortVersionString must inherit MARKETING_VERSION")
    return resolved.pop()


def main() -> int:
    try:
        version, build = check()
    except (OSError, KeyError, ValueError, subprocess.CalledProcessError) as error:
        print(f"FAIL metadata: {error}", file=sys.stderr)
        return 1
    print(f"PASS metadata: app/widget version={version} build={build} Debug/Release")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
