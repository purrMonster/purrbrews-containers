"""stacks/_lib/groom-record.py: a record for every backup run, and never a failure."""
from datetime import datetime, timezone
import importlib.util
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("groom", ROOT / "stacks/_lib/groom-record.py")
groom = importlib.util.module_from_spec(spec)
spec.loader.exec_module(groom)


class GroomRecord(unittest.TestCase):
    def test_a_bad_start_override_falls_back_to_now(self):
        now = datetime.now(timezone.utc)
        for value in ("not-a-number", "99999999999999999999"):
            with self.subTest(value=value), patch.dict(os.environ, {"GROOM_START": value}):
                self.assertEqual(groom.startedAt("example.service", now), now)

    def test_record_is_written_whole_and_leaves_no_temporary_file(self):
        start = datetime(2026, 10, 12, 1, 30, tzinfo=timezone.utc)
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for attempt in (1, 2):  # the same job and start twice: the second replaces the first
                path = groom.write(root, "nightly", start, {"schema": 1, "attempt": attempt})
            self.assertEqual(json.loads(path.read_text()), {"schema": 1, "attempt": 2})
            self.assertEqual(sorted(p.name for p in path.parent.iterdir()), [path.name])
            if os.name == "posix":
                self.assertEqual(path.stat().st_mode & 0o777, 0o644)

    def test_main_never_fails_the_job(self):
        with tempfile.TemporaryDirectory() as directory, \
                patch.dict(os.environ, {"GROOM_DIR": directory, "GROOM_START": "garbage"}), \
                patch.object(groom, "logTail", return_value=""):
            self.assertEqual(groom.main(["nightly", "cellar", "purrbrews-backup.service"]), 0)
            self.assertEqual(len(list(Path(directory, "nightly").glob("*.json"))), 1)


if __name__ == "__main__":
    unittest.main()
