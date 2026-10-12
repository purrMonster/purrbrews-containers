"""lldap-bootstrap.sh: credentials never reach command arguments, traces or logs."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class LldapBootstrap(unittest.TestCase):
    def test_lldap_credentials_stay_out_of_arguments_and_logs(self):
        for missing_user in ("0", "1"):
            with self.subTest(missing_user=missing_user), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                script = root / "stacks/percolator/lldap-bootstrap.sh"
                script.parent.mkdir(parents=True)
                shutil.copy(ROOT / "stacks/percolator/lldap-bootstrap.sh", script)
                library = root / "stacks/_lib"
                library.mkdir()
                (library / "common.sh").write_text('''
env_get() {
  case "$2" in
    LLDAP_ADMIN_GROUP) echo admins ;;
    LLDAP_HOUSEHOLD_GROUP) echo household ;;
    DOMAIN) echo example.invalid ;;
    LLDAP_ADMIN_PASSWORD) echo test-admin-credential ;;
  esac
}
die() { echo "$*" >&2; exit 1; }
log() { echo "$*"; }
''')
                binary = root / "bin"
                binary.mkdir()
                trace = root / "arguments"
                curl = binary / "curl"
                curl.write_text('''#!/usr/bin/env python3
import json, os, sys
from pathlib import Path
with open(os.environ["TRACE"], "a") as log:
    log.write(json.dumps(sys.argv) + "\\n")
body = json.load(sys.stdin)
if any("/auth/simple/login" in arg for arg in sys.argv):
    assert body["password"] == "test-admin-credential"
    print('{"token":"test-session-credential"}')
else:
    header = next(arg for arg in sys.argv if arg.startswith("@/dev/fd/"))
    assert Path(header[1:]).read_text().strip() == "Authorization: Bearer test-session-credential"
    if "query { groups" in body["query"]:
        print('{"data":{"groups":[{"id":1,"displayName":"admins"},{"id":2,"displayName":"household"}]}}')
    elif os.environ["MISSING_USER"] == "1":
        print('{"errors":[{"message":"test-session-credential"}]}')
    else:
        print('{"data":{"user":{"groups":[{"id":1},{"id":2}]}}}')
''')
                curl.chmod(0o755)
                env = dict(os.environ, PATH=str(binary) + os.pathsep + os.environ["PATH"],
                           TRACE=str(trace), MISSING_USER=missing_user)
                result = subprocess.run(["bash", "-x", str(script)], env=env,
                                        capture_output=True, text=True)
                self.assertEqual(result.returncode, int(missing_user), result.stderr)
                visible = trace.read_text() + result.stdout + result.stderr
                self.assertNotIn("test-admin-credential", visible)
                self.assertNotIn("test-session-credential", visible)
                if missing_user == "1":
                    self.assertIn("requires an interactive terminal", result.stderr)

    def test_lldap_password_tool_receives_credentials_only_inside_container(self):
        source = (ROOT / "stacks/percolator/lldap-bootstrap.sh").read_text()
        self.assertNotIn('--admin-password "$ADMIN_PASSWORD"', source)
        self.assertNotIn('--password "$password"', source)
        self.assertIn('sudo docker exec -i lldap sh -c', source)
        self.assertIn('export LLDAP_USER_PASSWORD', source)
        self.assertIn('exec 3>/dev/tty', source)
        container_script = source.split("sudo docker exec -i lldap sh -c '\n", 1)[1].split("\n    ' sh", 1)[0]
        with tempfile.TemporaryDirectory() as directory:
            tool = Path(directory) / "set-password"
            tool.write_text('''#!/usr/bin/env python3
import os, sys
assert os.environ["LLDAP_USER_PASSWORD"] == "test-new-password"
assert sys.argv[sys.argv.index("--token") + 1] == "test-session-token"
assert sys.argv[sys.argv.index("--username") + 1] == "barista"
assert "test-new-password" not in sys.argv
''')
            tool.chmod(0o755)
            result = subprocess.run(
                ["sh", "-c", container_script.replace("/app/lldap_set_password", str(tool)), "sh", "barista"],
                input="test-session-token\ntest-new-password\n", capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout + result.stderr, "")


if __name__ == '__main__':
    unittest.main()
