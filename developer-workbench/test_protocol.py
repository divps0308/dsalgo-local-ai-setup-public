"""Focused tests for the Developer Workbench model protocol boundary."""

from __future__ import annotations

import importlib.util
import sys
import unittest
from pathlib import Path


MODULE_PATH = Path(__file__).with_name("app.py")
SPEC = importlib.util.spec_from_file_location("developer_workbench_app", MODULE_PATH)
assert SPEC and SPEC.loader
APP = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = APP
SPEC.loader.exec_module(APP)


class WorkbenchProtocolTests(unittest.TestCase):
    def test_model_tool_schemas_are_closed(self) -> None:
        for tool in APP.TOOLS:
            self.assertIs(tool["function"]["parameters"]["additionalProperties"], False)

    def test_accepts_canonical_search_call(self) -> None:
        call, error = APP.normalize_and_validate_tool_call({
            "name": "search_files",
            "arguments": {"query": "main(", "path": "src", "max_results": 25},
        })
        self.assertIsNone(error)
        self.assertEqual(call["function"]["arguments"]["query"], "main(")

    def test_repairs_known_deepseek_search_aliases(self) -> None:
        call, error = APP.normalize_and_validate_tool_call({
            "name": "search_files",
            "arguments": {
                "pattern": "*.java",
                "content_pattern": r"public static void main\(",
                "base_dir": "src",
            },
        })
        self.assertIsNone(error)
        self.assertEqual(
            call["function"]["arguments"],
            {"query": "public static void main(", "path": "src"},
        )

    def test_reports_missing_required_argument_without_execution(self) -> None:
        call, error = APP.normalize_and_validate_tool_call({
            "name": "search_files",
            "arguments": {"path": "src"},
        })
        self.assertIsNone(call)
        self.assertEqual(error["code"], "invalid_arguments")
        self.assertEqual(error["missing"], ["query"])

    def test_coerces_unambiguous_scalar_values(self) -> None:
        call, error = APP.normalize_and_validate_tool_call({
            "name": "list_files",
            "arguments": {"recursive": "true", "max_entries": "50"},
        })
        self.assertIsNone(error)
        self.assertIs(call["function"]["arguments"]["recursive"], True)
        self.assertEqual(call["function"]["arguments"]["max_entries"], 50)

    def test_rejects_unknown_arguments(self) -> None:
        call, error = APP.normalize_and_validate_tool_call({
            "name": "read_file",
            "arguments": {"path": "README.md", "execute": True},
        })
        self.assertIsNone(call)
        self.assertEqual(error["unsupported"], ["execute"])

    def test_completion_requires_verification_after_last_write(self) -> None:
        task = {"events": [{"kind": "action", "time": 1, "content": "Wrote x"}]}
        valid, reason = APP.completion_quality(task, "Implemented and completed.")
        self.assertFalse(valid)
        self.assertIn("not inspected", reason)

        task["events"].append({"kind": "tool", "time": 2, "content": {"name": "git_diff", "result": "diff"}})
        valid, reason = APP.completion_quality(task, "Implemented and completed.")
        self.assertTrue(valid)
        self.assertEqual(reason, "")

    def test_claim_only_commands_are_not_verification(self) -> None:
        for command in (
            "echo task complete",
            "echo the task is fully complete",
            'Write-Host "changes completed"',
        ):
            self.assertTrue(APP.is_claim_only_command(command))
            self.assertIsNone(APP.verification_kind(command))

    def test_semantic_command_fingerprints_match_completion_variants(self) -> None:
        self.assertEqual(
            APP.command_fingerprint("echo task complete"),
            APP.command_fingerprint("Write-Host 'changes completed'"),
        )

    def test_compilation_request_requires_build_evidence(self) -> None:
        task = {
            "events": [
                {"kind": "action", "time": 1, "content": "Wrote x"},
                {"kind": "tool", "time": 2, "content": {"name": "git_diff", "result": "diff"}},
                {"kind": "command", "time": 3, "content": {"command": "git diff", "exitCode": 0}},
            ]
        }
        valid, reason = APP.completion_quality(task, "Implemented and completed.", "verify compilation")
        self.assertFalse(valid)
        self.assertIn("not inspected", reason)

        task["events"].append(
            {"kind": "command", "time": 4, "content": {"command": "mvnw.cmd clean compile", "exitCode": 0}}
        )
        valid, reason = APP.completion_quality(task, "Implemented and completed.", "verify compilation")
        self.assertTrue(valid)
        self.assertEqual(reason, "")


if __name__ == "__main__":
    unittest.main()
