"""Offline regression checks for verification selection and result validation."""

from __future__ import annotations

import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch


SCRIPT = Path(__file__).with_name("verify.py")
SPEC = importlib.util.spec_from_file_location("miataru_verify", SCRIPT)
verify = importlib.util.module_from_spec(SPEC)
assert SPEC and SPEC.loader
SPEC.loader.exec_module(verify)
META_SPEC = importlib.util.spec_from_file_location("miataru_metadata", SCRIPT.with_name("verify-metadata.py"))
metadata = importlib.util.module_from_spec(META_SPEC)
assert META_SPEC and META_SPEC.loader
META_SPEC.loader.exec_module(metadata)


class SelectionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.config = json.loads(verify.MAP.read_text())

    def test_documentation_only_selects_no_app_tests(self) -> None:
        plan = verify.select(["documentation/README.md"], self.config)
        self.assertFalse(plan["release"] or plan["fullUnit"] or plan["fullUI"])
        self.assertEqual(plan["unit"], [])

    def test_location_change_selects_existing_regressions(self) -> None:
        plan = verify.select(["miataru/miataru/LocationManagers/LocationManager.swift"], self.config)
        self.assertIn("LocationSamplePolicyTests", plan["unit"])
        self.assertFalse(plan["release"])

    def test_project_change_requires_full_release(self) -> None:
        plan = verify.select(["miataru/miataru.xcodeproj/project.pbxproj"], self.config)
        self.assertTrue(plan["release"])
        self.assertTrue(plan["fullUnit"] and plan["fullUI"])

    def test_unmapped_productive_view_expands_both_lanes(self) -> None:
        plan = verify.select(["miataru/miataru/views/Common/NewView.swift"], self.config)
        self.assertTrue(plan["fullUnit"] and plan["fullUI"])

    def test_unmapped_asset_expands_both_lanes(self) -> None:
        plan = verify.select(["miataru/miataru/Assets/NewIcon.png"], self.config)
        self.assertTrue(plan["fullUnit"] and plan["fullUI"])

    def test_deleted_test_expands_unit_lane(self) -> None:
        plan = verify.select(["miataru/miataruTests/RemovedTests.swift"], self.config)
        self.assertTrue(plan["fullUnit"])

    def test_map_rejects_nonexistent_suite(self) -> None:
        config = dict(self.config)
        config["rules"] = [{"name": "broken", "paths": ["foo/**"], "unit": ["AbsentTests"]}]
        with self.assertRaisesRegex(ValueError, "absent suites"):
            verify.select(["foo/bar.swift"], config)

    def test_zero_test_result_is_failure(self) -> None:
        with patch.object(verify, "command", return_value=b'{"result":"Passed","totalTestCount":0,"failedTests":0}'):
            with self.assertRaisesRegex(ValueError, "tests=0"):
                verify.validate_result(Path("unused.xcresult"))

    def test_real_map_suite_names_exist(self) -> None:
        unit = verify.available_suites("miataruTests")
        ui = verify.available_suites("miataruUITests")
        for rule in self.config["rules"]:
            self.assertFalse(set(rule.get("unit", [])) - unit, rule["name"])
            self.assertFalse(set(rule.get("ui", [])) - ui, rule["name"])

    def test_metadata_rejects_app_widget_build_mismatch(self) -> None:
        raw = metadata.subprocess.check_output(["plutil", "-convert", "json", "-o", "-", str(metadata.PROJECT)])
        project = json.loads(raw)
        objects = project["objects"]
        widget = next(value for value in objects.values() if value.get("isa") == "PBXNativeTarget" and value.get("name") == "miataruWidgets")
        config_list = objects[widget["buildConfigurationList"]]
        objects[config_list["buildConfigurations"][0]]["buildSettings"]["CURRENT_PROJECT_VERSION"] = "999"
        with patch.object(metadata.subprocess, "check_output", return_value=json.dumps(project).encode()):
            with self.assertRaisesRegex(ValueError, "differs from widget"):
                metadata.check()

    def test_release_runs_complete_lanes_in_sequence_and_aggregates_evidence(self) -> None:
        calls: list[str] = []
        with tempfile.TemporaryDirectory() as directory, \
             patch.object(verify, "ARTIFACTS", Path(directory)), \
             patch.object(verify, "command", return_value=b"head"), \
             patch.object(verify, "fingerprint", return_value="scope"):
            def fake_run(lane: str, selectors: list[str], paths: list[str]) -> bool:
                calls.append(lane)
                self.assertEqual(selectors, [])
                count = 359 if lane == "unit" else 12
                verify.write_status(lane, {
                    "resultBundle": f"/{lane}.xcresult", "tests": count,
                    "passed": count, "skipped": 0, "failed": 0,
                })
                return True

            with patch.object(verify, "run_xcode", side_effect=fake_run):
                self.assertTrue(verify.run_release(["miataru/miataru.xcodeproj/project.pbxproj"]))
            status = json.loads((Path(directory) / "release-status.json").read_text())
        self.assertEqual(calls, ["unit", "ui"])
        self.assertEqual(status["result"], "passed")
        self.assertEqual(status["tests"], 371)
        self.assertEqual(status["resultBundles"], ["/unit.xcresult", "/ui.xcresult"])


if __name__ == "__main__":
    unittest.main()
