"""Failure-path checks for local upgrade gates, scheduled fetch and status records."""
from datetime import datetime, timezone
import importlib.util
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]


class GroomRecords(unittest.TestCase):
    def setUp(self):
        spec = importlib.util.spec_from_file_location("groom", ROOT / "stacks/_lib/groom-record.py")
        self.groom = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(self.groom)

    def test_logs_are_not_copied_by_default(self):
        with patch.dict(os.environ, {}, clear=True), patch.object(self.groom.subprocess, "run") as run:
            self.assertEqual(self.groom.log_tail("example.service", datetime.now(timezone.utc)), "")
            run.assert_not_called()

    def test_bad_timestamp_falls_back_and_record_is_atomic(self):
        now = datetime.now(timezone.utc)
        with patch.dict(os.environ, {"GROOM_START": "not-a-number"}):
            self.assertEqual(self.groom.started_at("example.service", now), now)
        with tempfile.TemporaryDirectory() as directory:
            path = self.groom.write_record(Path(directory), "nightly", now, {"schema": 1})
            self.groom.write_record(Path(directory), "nightly", now, {"schema": 1})
            self.assertEqual(list(path.parent.iterdir()), [path])


@unittest.skipUnless(os.name == "posix", "POSIX scripts")
class UpgradeGates(unittest.TestCase):
    def test_existing_data_requires_acknowledgement(self):
        cases = (("percolator", "nextcloud", "nextcloud/html/config/config.php", "NEXTCLOUD_UPGRADE_READY", "35.0.1"),
                 ("grinder", "karakeep", "karakeep-meilisearch/data.ms", "KARAKEEP_SEARCH_UPGRADE_READY", "1.54.3"))
        for node, app, marker, key, version in cases:
            with self.subTest(app=app), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                shutil.copytree(ROOT / "stacks/_lib", root / "stacks/_lib")
                app_dir = root / "stacks" / node / app
                app_dir.mkdir(parents=True)
                (app_dir.parent / "node.conf").write_text(f"APPS=({app})\n")
                script = app_dir / "prepare.sh"
                shutil.copy(ROOT / "stacks" / node / app / "prepare.sh", script)
                binary = root / "bin"
                binary.mkdir()
                sudo = binary / "sudo"
                sudo.write_text('#!/bin/sh\nexec "$@"\n')
                sudo.chmod(0o755)
                env = dict(os.environ, PATH=str(binary) + os.pathsep + os.environ["PATH"])
                data = root / "data"
                def invoke():
                    return subprocess.run(["bash", str(script), str(data)], env=env,
                                          text=True, capture_output=True)
                self.assertEqual(invoke().returncode, 0)
                existing = data / marker
                existing.parent.mkdir(parents=True)
                existing.touch()
                self.assertNotEqual(invoke().returncode, 0)
                (app_dir.parent / ".env.local").write_text(f"{key}={version}\n")
                self.assertEqual(invoke().returncode, 0)

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
