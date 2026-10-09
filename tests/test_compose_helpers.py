"""Offline regression checks for wrapper side effects and command dispatch."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
BASH = shutil.which('bash')


@unittest.skipUnless(os.name == 'posix' and BASH, 'needs POSIX Bash and executable fixtures')
class ComposeHelpers(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.lib = self.root / 'stacks/_lib'
        shutil.copytree(ROOT / 'stacks/_lib', self.lib)
        self.node = self.root / 'stacks/example'
        self.node.mkdir()
        (self.node / 'node.conf').write_text('APPS=(demo extra)\nNEEDS_INIT=false\nNETWORK=example\n')
        (self.node / '.env.local').write_text('NODE=example\n')
        for app in ('demo', 'extra'):
            directory = self.node / app
            directory.mkdir()
            (directory / 'docker-compose.yml').write_text('services: {}\n')
            (directory / 'prepare.sh').write_text('touch "$PREPARED"\n')
        self.trace = self.root / 'docker.log'
        self.prepared = self.root / 'prepared'
        binary = self.root / 'bin'
        binary.mkdir()
        docker = binary / 'docker'
        docker.write_text('#!/bin/sh\nprintf "%s\\n" "$*" >> "$TRACE"\n'
                          'case "$*" in\n'
                          '  "network inspect "*) exit 1 ;;\n'
                          '  *"config --format json"*) printf \'{"services":{}}\\n\' ;;\n'
                          'esac\nexit 0\n')
        docker.chmod(0o755)
        self.env = dict(os.environ, TRACE=str(self.trace), PREPARED=str(self.prepared),
                        PATH=str(binary) + os.pathsep + os.environ['PATH'])

    def run_compose(self, *args):
        result = subprocess.run([BASH, str(self.lib / 'compose.sh'), str(self.node), *args],
                                env=self.env, text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        return self.trace.read_text() if self.trace.exists() else ''

    def test_inspection_and_preview_do_not_prepare(self):
        for arguments in [('demo', 'config'), ('demo', '--dry-run', 'up'),
                          ('demo', '--help', 'up')]:
            with self.subTest(arguments=arguments):
                before = (self.node / '.env.local').read_bytes()
                log = self.run_compose(*arguments)
                self.assertNotIn('network ', log)
                self.assertNotIn('config --format json', log)
                self.assertFalse(self.prepared.exists())
                self.assertEqual(before, (self.node / '.env.local').read_bytes())

    def test_profile_value_does_not_hide_startup(self):
        log = self.run_compose('demo', '--profile', 'stop', 'up')
        self.assertIn('network create', log)
        self.assertIn('config --format json', log)
        self.assertTrue(self.prepared.exists())

    def test_teardown_order_depends_on_command_not_option_value(self):
        log = self.run_compose('--all', '--project-name', 'up', 'down')
        calls = [line for line in log.splitlines() if line.startswith('compose ')]
        self.assertIn(str(self.node / 'extra'), calls[0])
        self.assertIn(str(self.node / 'demo'), calls[1])

    def test_invalid_target_never_calls_docker(self):
        result = subprocess.run([BASH, str(self.lib / 'compose.sh'), str(self.node), 'missing', 'up'],
                                env=self.env, text=True, capture_output=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(self.trace.exists())


if __name__ == '__main__':
    unittest.main()
