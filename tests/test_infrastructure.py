"""Offline regression checks: python3 -m unittest discover -s tests -v."""
import importlib.util
import io
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


def load(name, filename):
    spec = importlib.util.spec_from_file_location(name, ROOT / 'stacks/_lib' / filename)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


dns = load('dns', 'dns-records.py')
renderer = load('renderer', 'render-template.py')
FLEET = 'name,ip,mac\nsieve,192.168.0.10,x\npercolator,192.168.0.11,x\ncellar,192.168.0.12,x\nmochaPot,192.168.0.13,x\ngrinder,192.168.0.14,x\n'


class DNS(unittest.TestCase):
    def test_actual_routes(self):
        lines, hosts = dns.records(ROOT, 'example.test', io.StringIO(FLEET))
        for host, ip in [('authelia', 11), ('komodo', 12), ('homeassistant', 13), ('n8n', 14), ('pihole', 10)]:
            self.assertIn(f'address=/{host}.example.test/192.168.0.{ip}', lines)
            self.assertIn(f'local=/{host}.example.test/', lines)
        self.assertIn('filter-AAAA', lines)
        self.assertNotIn('local=/example.test/', lines)  # public ACME remains resolvable
        self.assertEqual(len(hosts), 5)

    def test_missing_node_is_error(self):
        with self.assertRaisesRegex(ValueError, 'missing from NODE_IPS'):
            dns.records(ROOT, 'example.test', io.StringIO(FLEET.replace('percolator,192.168.0.11,x\n', '')))

    def test_conflicting_route_is_error(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            for node in ['sieve', 'cellar']:
                file = root / f'stacks/{node}/app/docker-compose.yml'
                file.parent.mkdir(parents=True)
                file.write_text(' - "traefik.http.routers.x.rule=Host(`same.${DOMAIN}`)"\n')
            with self.assertRaisesRegex(ValueError, 'Conflicting'):
                dns.records(root, 'example.test', io.StringIO(FLEET))

    def test_primary_secondary_cli_parity_and_dhcp(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            shutil.copytree(ROOT / 'stacks', root / 'stacks', ignore=shutil.ignore_patterns('*.env.local', '__pycache__'))
            outputs = {}
            for node in ['sieve', 'mochaPot']:
                directory = root / 'stacks' / node
                path = directory / '.env.local'
                path.write_text('DOMAIN=example.test\nPIHOLE_DNS_EXTRA_HOSTS="192.168.0.20 workstation"\n')
                result = subprocess.run(['python3', str(ROOT / 'stacks/_lib/dns-records.py'), '--node-dir', str(directory)], input=FLEET, text=True, capture_output=True)
                self.assertEqual(result.returncode, 0, result.stderr)
                outputs[node] = dns.read_env(path)
                self.assertEqual(path.stat().st_mode & 0o777, 0o600)
            primary = outputs['sieve']['PIHOLE_DNSMASQ_LINES'].split(';')
            secondary = outputs['mochaPot']['PIHOLE_DNSMASQ_LINES'].split(';')
            self.assertEqual(primary[:-1], secondary)
            self.assertEqual(primary[-1], 'dhcp-option=option:dns-server,192.168.0.10,192.168.0.13')
            self.assertEqual(outputs['sieve']['PIHOLE_DNS_HOSTS'], outputs['mochaPot']['PIHOLE_DNS_HOSTS'])


class Render(unittest.TestCase):
    def test_failed_render_preserves_existing(self):
        for value in [None, '', 'REPLACE_ME.example.test']:
            with tempfile.TemporaryDirectory() as tmp:
                template = Path(tmp) / 'config.yml.template'
                template.write_text('url: https://${DOMAIN}\n')
                output = template.with_suffix('')
                output.write_text('known-good')
                with self.assertRaises(ValueError):
                    renderer.render(template, {} if value is None else {'DOMAIN': value})
                self.assertEqual(output.read_text(), 'known-good')

    def test_modes_and_literal_runtime_variables(self):
        with tempfile.TemporaryDirectory() as tmp:
            template = Path(tmp) / 'config.template'
            template.write_text('# render-mode: 0644\n# $DOCUMENTATION_ONLY\n${DOMAIN}\n${SSH_CONNECTION:-}\n')
            renderer.render(template, {'DOMAIN': 'example.test'})
            output = template.with_suffix('')
            self.assertIn('${SSH_CONNECTION:-}', output.read_text())
            self.assertEqual(output.stat().st_mode & 0o777, 0o644)
            template.write_text('secret: ${SECRET}\n')
            renderer.render(template, {'SECRET': 'abc$literal'})
            self.assertEqual(output.read_text(), 'secret: abc$literal\n')
            self.assertEqual(output.stat().st_mode & 0o777, 0o600)

    @unittest.skipIf(os.geteuid() == 0, 'renderer intentionally rejects root')
    def test_shell_isolates_apps_and_load_failures(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            shutil.copytree(ROOT / 'stacks/_lib', root / 'stacks/_lib')
            node = root / 'stacks/test'
            for app in ['a', 'b', 'c']:
                directory = node / app / 'config'
                directory.mkdir(parents=True)
                (directory / 'config.template').write_text('value: ${APP_SECRET}\n')
                (directory / 'config').write_text('old')
            (node / 'a/secrets.env.local').write_text('APP_SECRET=alpha\n')
            (node / 'c/secrets.env.local').write_text('return 1\n')
            env = os.environ.copy()
            env.pop('APP_SECRET', None)
            result = subprocess.run(['bash', str(root / 'stacks/_lib/render-configs.sh'), str(node)], env=env, capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual((node / 'a/config/config').read_text(), 'value: alpha\n')
            self.assertEqual((node / 'b/config/config').read_text(), 'old')
            self.assertEqual((node / 'c/config/config').read_text(), 'old')
            self.assertIn('Cannot load', result.stderr)

    @unittest.skipIf(os.geteuid() == 0, 'renderer intentionally rejects root')
    def test_direct_app_template_loads_own_secrets(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            shutil.copytree(ROOT / 'stacks/_lib', root / 'stacks/_lib')
            app = root / 'stacks/test/restic'
            app.mkdir(parents=True)
            (app / 'rclone.conf.template').write_text('client_secret=${RESTIC_TEST_SECRET}\n')
            (app / 'secrets.env.local').write_text('RESTIC_TEST_SECRET=correct\n')
            result = subprocess.run(['bash', str(root / 'stacks/_lib/render-configs.sh'), str(app.parent)], capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual((app / 'rclone.conf').read_text(), 'client_secret=correct\n')

    def test_all_repository_templates_render_with_fixture_values(self):
        for template in ROOT.glob('stacks/*/**/*.template'):
            text = template.read_text()
            values = {a or b: 'fixture' for a, b in renderer.VARIABLE.findall(text)}
            with tempfile.TemporaryDirectory() as tmp:
                fixture = Path(tmp) / template.name
                fixture.write_text(text)
                renderer.render(fixture, values)
                self.assertTrue(fixture.with_suffix('').is_file())


class Shell(unittest.TestCase):
    def test_shell_syntax(self):
        for file in ROOT.rglob('*.sh'):
            if '.git' not in file.parts:
                result = subprocess.run(['bash', '-n', str(file)], capture_output=True, text=True)
                self.assertEqual(result.returncode, 0, f'{file}: {result.stderr}')

    def test_firewall_bridge_paths(self):
        for node, ports in [('mochaPot', [8123, 8095, 8081]), ('grinder', [6052])]:
            with tempfile.TemporaryDirectory() as tmp:
                directory = Path(tmp)
                shutil.copy(ROOT / f'stacks/{node}/firewall.sh', directory)
                (directory / '.env.local').write_text('LAN_CIDR=192.168.0.0/24\nPROXY_SUBNET=172.30.13.0/24\n')
                env = dict(os.environ, PROXY_SUBNET='172.30.13.0/24')
                result = subprocess.run(['bash', str(directory / 'firewall.sh'), '--dry-run'], env=env, capture_output=True, text=True)
                self.assertEqual(result.returncode, 0, result.stderr)
                for port in ports:
                    self.assertIn(f'allow proto tcp from 172.30.13.0/24 to any port {port}', result.stdout)


if __name__ == '__main__':
    unittest.main()
