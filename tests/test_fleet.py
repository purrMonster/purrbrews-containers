"""Offline checks: deployment ordering, refusal, failure recovery and locking."""
import argparse
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("fleet", ROOT / "scripts/fleet.py")
fleet = importlib.util.module_from_spec(spec)
spec.loader.exec_module(fleet)


class Fleet(unittest.TestCase):
    def test_inventory_and_optional_services(self):
        nodes = fleet.inventory(ROOT)
        self.assertEqual(len(nodes), 6)
        self.assertEqual(nodes["sieve"]["apps"][:2], ["unbound", "pihole"])
        self.assertNotIn("smb", fleet.selected_apps(nodes["cellar"], []))
        self.assertIn("smb", fleet.selected_apps(nodes["cellar"], ["smb"]))
        with self.assertRaises(ValueError):
            fleet.selected_apps(nodes["cellar"], ["typo"])

    def test_plan_preserves_order_without_creating_files(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            plan = fleet.command_plan(root, "sieve", fleet.inventory(ROOT)["sieve"], [], 90)
            self.assertEqual([phase for phase, _ in plan][:4],
                             ["configure", "firewall", "deploy:unbound", "deploy:pihole"])
            self.assertEqual(plan[2][1][-3:], ["--wait", "--wait-timeout", "90"])
            self.assertEqual(list(root.iterdir()), [])

    def test_release_requires_exact_commit_and_clean_checkout(self):
        commit = "a" * 40
        with patch.object(fleet, "git_output", side_effect=[commit, ""]):
            self.assertEqual(fleet.require_release(ROOT, commit), commit)
        for outputs in (["b" * 40], [commit, " M file"]):
            with patch.object(fleet, "git_output", side_effect=outputs), self.assertRaises(ValueError):
                fleet.require_release(ROOT, commit)
        with self.assertRaises(ValueError):
            fleet.require_release(ROOT, "main")

    def test_lock_rejects_concurrent_deploy_and_releases(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "lock"
            with fleet.deployment_lock(path):
                with self.assertRaises((ValueError, OSError)):
                    with fleet.deployment_lock(path):
                        self.fail("Second deployment acquired lock")
            with fleet.deployment_lock(path):
                pass

    @unittest.skipUnless(os.name == "posix", "Linux deploy policy")
    def test_failure_stops_later_phases_and_records_progress(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            args = argparse.Namespace(release="a" * 40, acknowledge_prerequisites=True,
                                      include_optional=[], wait_timeout=10)
            node = {"platform": "linux", "apps": ["demo"], "optional": []}
            with patch.object(fleet.socket, "gethostname", return_value="example"), \
                 patch.object(fleet.os, "geteuid", return_value=1000), \
                 patch.object(fleet.Path, "home", return_value=root), \
                 patch.object(fleet.shutil, "which", return_value="/fake/bin"), \
                 patch.object(fleet, "require_release", return_value=args.release), \
                 patch.object(fleet.subprocess, "run", side_effect=[None, subprocess.CalledProcessError(1, "firewall")]) as run:
                with self.assertRaises(subprocess.CalledProcessError):
                    fleet.deploy(root, "example", node, args)
                self.assertEqual(run.call_count, 2)
            state = json.loads((root / ".fleet/example.json").read_text())
            self.assertEqual(state["status"], "failed")
            self.assertEqual(state["phase"], "firewall")
            self.assertEqual(state["completed_phases"], ["configure"])
            self.assertNotIn("output", state)

    def test_atomic_state_replacement_leaves_no_temporary_files(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "state.json"
            fleet.save_state(path, {"status": "running"})
            fleet.save_state(path, {"status": "succeeded"})
            self.assertEqual(json.loads(path.read_text()), {"status": "succeeded"})
            self.assertEqual(list(path.parent.iterdir()), [path])

    @unittest.skipUnless(os.name == "posix", "Linux deploy policy")
    def test_successful_repeat_records_completion_and_retains_images(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            args = argparse.Namespace(release="a" * 40, acknowledge_prerequisites=True,
                                      include_optional=[], wait_timeout=10)
            node = {"platform": "linux", "apps": ["demo"], "optional": []}
            with patch.object(fleet.socket, "gethostname", return_value="example"), \
                 patch.object(fleet.os, "geteuid", return_value=1000), \
                 patch.object(fleet.Path, "home", return_value=root), \
                 patch.object(fleet.shutil, "which", return_value="/fake/bin"), \
                 patch.object(fleet, "require_release", return_value=args.release), \
                 patch.object(fleet.subprocess, "run") as run:
                for _ in range(2):
                    fleet.deploy(root, "example", node, args)
                    state = json.loads((root / ".fleet/example.json").read_text())
                    self.assertEqual(state["status"], "succeeded")
                    self.assertEqual(state["completed_phases"], ["configure", "firewall", "deploy:demo"])
                self.assertEqual(run.call_count, 6)
                self.assertTrue(all(call.kwargs["env"]["PURRBREWS_KEEP_IMAGES"] == "1"
                                    for call in run.call_args_list))

    @unittest.skipUnless(os.name == "posix", "Linux deploy policy")
    def test_wrong_host_refuses_before_any_command(self):
        node = {"platform": "linux"}
        with patch.object(fleet.socket, "gethostname", return_value="other"), \
             patch.object(fleet.subprocess, "run") as run, self.assertRaises(ValueError):
            fleet.deploy(ROOT, "example", node, argparse.Namespace())
        run.assert_not_called()


class DailyFetch(unittest.TestCase):
    """init/lib/purrbrews-pull.sh fetches; it never moves the checkout."""

    def test_daily_fetch_does_not_move_checkout_or_print_transport_errors(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / ".git").mkdir()
            binary = root / "bin"
            binary.mkdir()
            trace = root / "calls"
            git = binary / "git"
            git.write_text('#!/bin/sh\nprintf "%s\\n" "$*" >> "$TRACE"\n'
                           'case "$1" in\n rev-parse) printf "%040d\\n" 1 ;;\n'
                           ' fetch) if [ "$FAIL_FETCH" = 1 ]; then echo private-transport-detail >&2; exit 1; fi ;;\nesac\n')
            git.chmod(0o755)
            env = dict(os.environ, PROJECT_DIR=str(root), TRACE=str(trace),
                       PATH=str(binary) + os.pathsep + os.environ["PATH"], PULL_HEALTHCHECK_URL="")
            for failure in ("0", "1"):
                result = subprocess.run(["bash", str(ROOT / "init/lib/purrbrews-pull.sh")],
                                        env=dict(env, FAIL_FETCH=failure), capture_output=True, text=True)
                self.assertEqual(result.returncode, int(failure))
                self.assertNotIn("private-transport-detail", result.stdout + result.stderr)
            calls = trace.read_text()
            self.assertIn("fetch --quiet origin", calls)
            self.assertNotIn("pull", calls)
            self.assertNotIn("checkout", calls)


if __name__ == "__main__":
    unittest.main()
