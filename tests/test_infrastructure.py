"""Offline checks for the repo: python3 -m unittest discover -s tests -v

Nothing here needs Docker or a real node. Where a script wants docker or sudo,
a fake one on PATH answers instead. A few tests are skipped under root,
because the scripts refuse to run as root on purpose.
"""
import importlib.util
import io
import os
from pathlib import Path
import re
import shutil
import stat
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
STACKS = ROOT / 'stacks'
NODES = ['sieve', 'percolator', 'cellar', 'mochaPot', 'grinder', 'roastery']
LINUX_NODES = NODES[:-1]
AS_ROOT = os.geteuid() == 0


def load(name, filename):
    spec = importlib.util.spec_from_file_location(name, STACKS / '_lib' / filename)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


dns = load('dns', 'dns-records.py')
renderer = load('renderer', 'render-template.py')
FLEET = 'name,ip,mac\nsieve,192.168.0.10,02:00:00:00:00:10\npercolator,192.168.0.11,x\ncellar,192.168.0.12,x\nmochaPot,192.168.0.13,x\ngrinder,192.168.0.14,x\n'


def node_conf(node):
    """APPS, NETWORK etc. from a node.conf, read the way bash would."""
    out = subprocess.run(['bash', '-c', f'source "{STACKS / node / "node.conf"}"; '
                          'echo "${APPS[*]}"; echo "$NETWORK"; echo "$NETWORK_SUBNET_KEY"; echo "$RESOLVER"'],
                         capture_output=True, text=True, check=True).stdout.split('\n')
    return {'APPS': out[0].split(), 'NETWORK': out[1], 'NETWORK_SUBNET_KEY': out[2], 'RESOLVER': out[3]}


def fake_bin(directory):
    """docker and sudo stand-ins: docker answers `info` and prints a plausible hash."""
    directory.mkdir(parents=True, exist_ok=True)
    docker = directory / 'docker'
    docker.write_text('#!/usr/bin/env bash\n'
                      'case "$*" in\n'
                      '  info*) exit 0 ;;\n'
                      '  *"user hash"*) cat >/dev/null; echo "\\$2a\\$10\\$' + 'a' * 53 + '" ;;\n'
                      '  *"hash generate"*) echo "Digest: \\$pbkdf2-sha512\\$310000\\$fixture" ;;\n'
                      'esac\n')
    sudo = directory / 'sudo'
    sudo.write_text('#!/usr/bin/env bash\nexec "$@"\n')
    for f in (docker, sudo):
        f.chmod(f.stat().st_mode | stat.S_IEXEC)
    return directory


def copy_repo(tmp):
    """The parts of the repo the node scripts read, without anything node-local."""
    root = Path(tmp) / 'repo'
    ignore = shutil.ignore_patterns('.env.local', '*.env.local', '__pycache__', 'model-cache',
                                    'traefik.exe', 'keys', 'data')
    shutil.copytree(STACKS, root / 'stacks', ignore=ignore)
    shutil.copytree(ROOT / 'init', root / 'init', ignore=ignore)
    return root


class DNS(unittest.TestCase):
    def test_fixed_dhcp_roles_ignore_legacy_env_switch(self):
        primary = (STACKS / 'sieve/pihole/docker-compose.yml').read_text()
        secondary = (STACKS / 'mochaPot/pihole/docker-compose.yml').read_text()
        self.assertIn('FTLCONF_dhcp_active: "true"', primary)
        self.assertIn('FTLCONF_dhcp_active: "false"', secondary)
        self.assertNotIn('${PIHOLE_DHCP_ACTIVE', primary)
        self.assertNotIn('${PIHOLE_DHCP_ACTIVE', secondary)

    def test_actual_routes(self):
        lines, hosts = dns.records(ROOT, 'example.test', io.StringIO(FLEET), '192.168.0.20 roastery')
        for host, ip in [('authelia', 11), ('komodo', 12), ('homeassistant', 13), ('n8n', 14), ('pihole', 10), ('ollama', 20)]:
            self.assertIn(f'address=/{host}.example.test/192.168.0.{ip}', lines)
            self.assertIn(f'local=/{host}.example.test/', lines)
        self.assertIn('filter-AAAA', lines)
        self.assertNotIn('local=/example.test/', lines)  # public ACME remains resolvable
        self.assertEqual(len(hosts), 6)

    def test_roastery_can_come_from_fleet(self):
        lines, _ = dns.records(ROOT, 'example.test', io.StringIO(FLEET + 'roastery,192.168.0.21,x\n'))
        self.assertIn('address=/ollama.example.test/192.168.0.21', lines)

    def test_missing_roastery_is_error(self):
        with self.assertRaisesRegex(ValueError, 'Router node roastery'):
            dns.records(ROOT, 'example.test', io.StringIO(FLEET))

    def test_existing_native_host_survives_repeated_generation(self):
        existing = '192.168.0.20 roastery;192.168.0.99 sieve'
        for _ in range(2):
            lines, hosts = dns.records(ROOT, 'example.test', io.StringIO(FLEET), existing_hosts=existing)
            self.assertIn('address=/ollama.example.test/192.168.0.20', lines)
            self.assertIn('address=/pihole.example.test/192.168.0.10', lines)
            self.assertIn('192.168.0.20 roastery', hosts)
            existing = ';'.join(hosts)

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
            root = copy_repo(tmp)
            outputs = {}
            for node, role in [('sieve', 'primary'), ('mochaPot', 'secondary')]:
                directory = root / 'stacks' / node
                path = directory / '.env.local'
                path.write_text('DOMAIN=example.test\nPIHOLE_DNS_HOSTS="192.168.0.20 roastery"\n'
                                'PIHOLE_DNS_EXTRA_HOSTS="192.168.0.30 workstation"\n'
                                'PIHOLE_DHCP_EXTRA_HOSTS=aa:bb:cc:dd:ee:ff,192.168.0.30,workstation\n')
                result = subprocess.run(['python3', str(STACKS / '_lib/dns-records.py'), '--node-dir', str(directory), '--role', role],
                                        input=FLEET, text=True, capture_output=True,
                                        env=dict(os.environ, DNS_SERVERS='192.168.0.10,192.168.0.13'))
                self.assertEqual(result.returncode, 0, result.stderr)
                outputs[node] = dns.read_env(path)
                self.assertEqual(path.stat().st_mode & 0o777, 0o600)
            primary = outputs['sieve']['PIHOLE_DNSMASQ_LINES'].split(';')
            secondary = outputs['mochaPot']['PIHOLE_DNSMASQ_LINES'].split(';')
            self.assertEqual(primary[:-1], secondary)
            self.assertEqual(primary[-1], 'dhcp-option=option:dns-server,192.168.0.10,192.168.0.13')
            self.assertEqual(outputs['sieve']['PIHOLE_DNS_HOSTS'], outputs['mochaPot']['PIHOLE_DNS_HOSTS'])
            leases = outputs['sieve']['PIHOLE_DHCP_HOSTS'].split(';')
            self.assertIn('02:00:00:00:00:10,192.168.0.10,sieve', leases)
            self.assertIn('aa:bb:cc:dd:ee:ff,192.168.0.30,workstation', leases)
            self.assertNotIn('PIHOLE_DHCP_HOSTS', outputs['mochaPot'])


class Render(unittest.TestCase):
    def node(self, root, name, conf='APPS=()\n'):
        node = root / 'stacks' / name
        node.mkdir(parents=True, exist_ok=True)
        (node / 'node.conf').write_text(conf)
        return node

    @unittest.skipIf(AS_ROOT, 'the scripts refuse to run as root')
    def test_resolver_render_refreshes_dns_and_stops_on_failure(self):
        for name, role in [('sieve', 'primary'), ('mochaPot', 'secondary')]:
            with self.subTest(node=name), tempfile.TemporaryDirectory() as tmp:
                root = Path(tmp)
                lib = root / 'stacks/_lib'
                shutil.copytree(STACKS / '_lib', lib)
                node = self.node(root, name, f'RESOLVER={role}\n')
                app = node / 'pihole'
                app.mkdir()
                template = app / 'config.template'
                template.write_text('dns=${PIHOLE_DNSMASQ_LINES}\n')
                refresh = lib / 'refresh-dns.sh'
                refresh.write_text('#!/usr/bin/env bash\nset -eu\n'
                                   'printf "PIHOLE_DNSMASQ_LINES=\'address=/ollama.example.test/192.168.0.20\'\\n" > "$1/.env.local"\n')
                command = ['bash', str(lib / 'render-configs.sh'), str(node)]
                result = subprocess.run(command, text=True, capture_output=True)
                self.assertEqual(result.returncode, 0, result.stderr)
                output = template.with_suffix('')
                self.assertEqual(output.read_text(), 'dns=address=/ollama.example.test/192.168.0.20\n')
                output.write_text('last-good')
                refresh.write_text('exit 1\n')
                result = subprocess.run(command, text=True, capture_output=True)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(output.read_text(), 'last-good')

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

    @unittest.skipIf(AS_ROOT, 'the scripts refuse to run as root')
    def test_shell_isolates_apps_and_load_failures(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            shutil.copytree(STACKS / '_lib', root / 'stacks/_lib')
            node = self.node(root, 'test')
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

    @unittest.skipIf(AS_ROOT, 'the scripts refuse to run as root')
    def test_layering_fleet_then_node_then_app(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            shutil.copytree(STACKS / '_lib', root / 'stacks/_lib')
            (root / 'stacks/fleet.env').write_text('A=fleet\nB=fleet\nC=fleet\n')
            node = self.node(root, 'test')
            (node / '.env.local').write_text('B=node\nC=node\n')
            app = node / 'restic'
            app.mkdir()
            (app / 'secrets.env.local').write_text('C=app\n')
            (app / 'x.conf.template').write_text('${A} ${B} ${C}\n')
            result = subprocess.run(['bash', str(root / 'stacks/_lib/render-configs.sh'), str(node)], capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual((app / 'x.conf').read_text(), 'fleet node app\n')

    def test_all_repository_templates_render_with_fixture_values(self):
        for template in STACKS.glob('*/**/*.template'):
            text = template.read_text()
            values = {a or b: 'fixture' for a, b in renderer.VARIABLE.findall(text)}
            with tempfile.TemporaryDirectory() as tmp:
                fixture = Path(tmp) / template.name
                fixture.write_text(text)
                renderer.render(fixture, values)
                self.assertTrue(fixture.with_suffix('').is_file())

    @unittest.skipUnless(shutil.which('pwsh') and not AS_ROOT, 'needs PowerShell, and not root')
    def test_powershell_renders_like_bash(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            shutil.copytree(STACKS / '_lib', root / 'stacks/_lib')
            (root / 'stacks/fleet.env').write_text('A=fleet\nB=fleet\n')
            outputs = {}
            for side in ['bash', 'pwsh']:
                node = self.node(root, side)
                (node / '.env.local').write_text("B='node $literal'\n")
                app = node / 'traefik' / 'config' / 'dynamic'
                app.mkdir(parents=True)
                (node / 'traefik/secrets.env.local').write_text('C=app\n')
                (app / 'x.yml.template').write_text('# $IGNORED in a comment\na: ${A}\nb: ${B}\nc: $C\n')
                if side == 'bash':
                    cmd = ['bash', str(root / 'stacks/_lib/render-configs.sh'), str(node)]
                else:
                    cmd = ['pwsh', '-NoProfile', '-c', f". '{root / 'stacks/_lib/purrbrews.ps1'}'; if (-not (Invoke-Render (Get-Node '{node}'))) {{ exit 1 }}"]
                result = subprocess.run(cmd, capture_output=True, text=True)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                outputs[side] = (app / 'x.yml').read_text()
            self.assertEqual(outputs['bash'], outputs['pwsh'])
            self.assertIn('b: node $literal', outputs['bash'])


class ComposeConfig(unittest.TestCase):
    def check(self, content):
        return subprocess.run(['python3', str(STACKS / '_lib/check-compose-config.py')], input=content, text=True, capture_output=True)

    def test_placeholder_rejected_without_secret_disclosure(self):
        result = self.check('{"services":{"app":{"labels":["Host(`komodo.REPLACE_ME.example.com`)"],"password":"private-value"}}}')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('services.app.labels', result.stderr)
        self.assertNotIn('private-value', result.stderr)
        self.assertNotIn('komodo.REPLACE_ME', result.stderr)

    def test_real_config_accepted(self):
        self.assertEqual(self.check('{"services":{"app":{"labels":["Host(`komodo.example.test`)"],"enabled":true}}}').returncode, 0)

    def test_invalid_config_rejected(self):
        self.assertNotEqual(self.check('').returncode, 0)


class Layout(unittest.TestCase):
    """The things that make every node work the same way."""

    def test_shell_syntax(self):
        for file in ROOT.rglob('*.sh'):
            if '.git' not in file.parts:
                result = subprocess.run(['bash', '-n', str(file)], capture_output=True, text=True)
                self.assertEqual(result.returncode, 0, f'{file}: {result.stderr}')

    def test_node_scripts_are_identical_wrappers(self):
        for script in ['compose.sh', 'setup-secrets.sh', 'render-configs.sh', 'firewall.sh']:
            copies = {(STACKS / node / script).read_text() for node in NODES if (STACKS / node / script).exists()}
            self.assertEqual(len(copies), 1, f'{script} differs between nodes')
            self.assertIn('../_lib/', copies.pop())

    def test_node_conf_matches_the_app_folders(self):
        for node in NODES:
            conf = node_conf(node)
            on_disk = {p.parent.name for p in (STACKS / node).glob('*/docker-compose.yml')}
            self.assertEqual(set(conf['APPS']), on_disk, f'{node}: node.conf APPS vs folders')
            self.assertEqual(len(conf['APPS']), len(set(conf['APPS'])), f'{node}: an app is listed twice')

    def test_fleet_env_matches_init_node_ips(self):
        init = (ROOT / 'init/purrbrews-init.env.example').read_text()
        pairs = dict(p.split('=') for p in re.search(r'^NODE_IPS=(.*)$', init, re.M).group(1).split())
        fleet = dict(line.split('=', 1) for line in (STACKS / 'fleet.env').read_text().splitlines()
                     if re.match(r'^[A-Z_]+=', line))
        for name, ip in pairs.items():
            self.assertEqual(fleet[f'{name.upper()}_LAN_IP'], ip, name)
        self.assertEqual(fleet['LAN_CIDR'], re.search(r'^LAN_CIDR=(.*)$', init, re.M).group(1))
        self.assertEqual(fleet['GATEWAY'], re.search(r'^GATEWAY=(.*)$', init, re.M).group(1))

    def test_every_rendered_file_is_gitignored(self):
        for template in STACKS.glob('*/**/*.template'):
            output = template.with_suffix('').relative_to(ROOT)
            ignored = subprocess.run(['git', '-C', str(ROOT), 'check-ignore', '-q', '--no-index', str(output)])
            self.assertEqual(ignored.returncode, 0, f'{output} must be in .gitignore: it can hold secrets')

    def test_node_local_files_are_gitignored(self):
        for path in ['stacks/sieve/.env.local', 'stacks/sieve/ntfy/secrets.env.local',
                     'stacks/roastery/traefik/secrets.env.local', 'stacks/grinder/komodo-periphery/keys/core.pub',
                     'stacks/roastery/komodo-periphery/keys/periphery.key', 'stacks/cellar/restic/cache/x',
                     'stacks/roastery/immich-ml/model-cache/x', 'stacks/roastery/traefik/traefik.exe']:
            ignored = subprocess.run(['git', '-C', str(ROOT), 'check-ignore', '-q', '--no-index', path])
            self.assertEqual(ignored.returncode, 0, path)

    def test_secrets_conf_kinds(self):
        kinds = {'hex', 'base64', 'value', 'prompt', 'copy', 'mirror', 'hash', 'rsa'}
        for spec in STACKS.glob('*/*/secrets.conf'):
            for line in spec.read_text().splitlines():
                fields = line.split()
                if not fields or fields[0].startswith('#') or fields[0] == 'NOTE':
                    continue
                self.assertRegex(fields[0], r'^[A-Z_][A-Z0-9_]*$', f'{spec}: {line}')
                self.assertIn(fields[1], kinds, f'{spec}: {line}')
                if fields[1] in ('copy', 'mirror'):
                    self.assertTrue((spec.parent.parent / fields[2]).is_dir(), f'{spec}: {line}')

    def test_no_references_to_docs_that_are_not_here(self):
        for file in ROOT.rglob('*'):
            if not file.is_file() or '.git' in file.parts or file.suffix in ('.pyc', '.exe') or file.name == 'test_infrastructure.py':
                continue
            if file.name == 'runbook.md':
                continue  # dated history is allowed to mention what was true then
            text = file.read_text(errors='ignore')
            for stale in ['infrastructure.md', 'edge-and-automation.md', 'generate-secrets.sh', 'second-brain', 'Second brain']:
                self.assertNotIn(stale, text, f'{file.relative_to(ROOT)} mentions {stale}')


class Firewall(unittest.TestCase):
    def dry_run(self, node, env_local, network_subnet=None):
        with tempfile.TemporaryDirectory() as tmp:
            root = copy_repo(tmp)
            (root / 'stacks' / node / '.env.local').write_text(env_local)
            env = dict(os.environ)
            if network_subnet:
                env['NETWORK_SUBNET'] = network_subnet
            result = subprocess.run(['bash', str(root / 'stacks' / node / 'firewall.sh'), '--dry-run'],
                                    env=env, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            return result.stdout

    def test_sieve(self):
        out = self.dry_run('sieve', 'EDGE_SUBNET=172.31.10.0/24\n')
        self.assertIn('ufw allow proto udp from 192.168.0.0/24 to any port 53', out)
        self.assertIn('ufw allow proto udp from any to any port 67', out)
        self.assertIn('ufw allow proto tcp from 172.31.10.0/24 to any port 8080', out)
        self.assertIn('ufw route allow proto tcp from 192.168.0.0/24 to 172.31.10.0/24 port 443', out)
        self.assertIn('purrbrews\\ sieve:\\ dns\\ from\\ LAN', out)
        # only Docker's own subnets may skip the rules, not the whole LAN
        self.assertIn('ufw-docker install --docker-subnets', out)

    def test_percolator_forward_auth_clients(self):
        out = self.dry_run('percolator', 'FORWARD_AUTH_CLIENTS=192.168.0.10 192.168.0.12\nPROXY_SUBNET=172.30.0.0/24\n')
        self.assertIn('ufw route allow proto tcp from 192.168.0.0/24 to any port 443', out)
        self.assertIn('ufw route allow proto tcp from 192.168.0.10 to any port 9091', out)
        self.assertIn('ufw route allow proto tcp from 192.168.0.12 to any port 9091', out)
        self.assertIn('forward-auth\\ from\\ 192.168.0.12', out)

    def test_host_networked_apps_allow_the_proxy_network(self):
        out = self.dry_run('mochaPot', 'PROXY_SUBNET=172.30.13.0/24\n')
        for port in [8123, 8095, 8081]:
            self.assertIn(f'allow proto tcp from 172.30.13.0/24 to any port {port}', out)
        self.assertNotIn('port 67', out)
        out = self.dry_run('grinder', '', network_subnet='172.18.0.0/16')
        self.assertIn('allow proto tcp from 172.18.0.0/16 to any port 6052', out)
        # published ports are matched after DNAT, on the container's port
        self.assertIn('route allow proto tcp from 192.168.0.0/24 to any port 5000', out)
        self.assertNotIn('port 5001', out)

    def test_cellar_and_bad_tokens(self):
        out = self.dry_run('cellar', '')
        for port in [80, 443, 9120, 8080]:
            self.assertIn(f'route allow proto tcp from 192.168.0.0/24 to any port {port}', out)
        self.assertNotIn('port 445', out)  # smb stays closed until its rule is uncommented
        with tempfile.TemporaryDirectory() as tmp:
            root = copy_repo(tmp)
            (root / 'stacks/percolator/.env.local').write_text('FORWARD_AUTH_CLIENTS=REPLACE_ME\n')
            result = subprocess.run(['bash', str(root / 'stacks/percolator/firewall.sh'), '--dry-run'], capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)


@unittest.skipIf(AS_ROOT, 'the scripts refuse to run as root')
class Secrets(unittest.TestCase):
    """Generate every node's secrets with a fake docker, then check nothing a
    compose file or template needs is left undefined."""

    VAR = re.compile(r'\$\{([A-Za-z_][A-Za-z0-9_]*)(:?[-?][^}]*)?\}|\$([A-Za-z_][A-Za-z0-9_]*)')

    def generate(self, node):
        tmp = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, tmp)
        root = copy_repo(tmp)
        (root / '.env').write_text(f'NODE={node}\nNODE_IP=192.168.0.99\nTZ=Asia/Kolkata\nPUID=1000\nPGID=1000\n'
                                   'PROJECT_DIR=/opt/purrbrews\nDATA_DIR=/srv/data\nMEDIA_DIR=/srv/media\n')
        directory = root / 'stacks' / node
        shutil.copy(directory / 'local.env.example', directory / '.env.local')
        path = str(fake_bin(Path(tmp) / 'bin')) + os.pathsep + os.environ['PATH']
        script = (f'source "{root}/stacks/_lib/common.sh"; source "{root}/stacks/_lib/secrets.sh"; '
                  f'load_node "{directory}"; use_docker; generate_secrets; echo "failed=$SECRETS_FAILED"')
        result = subprocess.run(['bash', '-c', script], env=dict(os.environ, PATH=path), stdin=subprocess.DEVNULL,
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('failed=0', result.stdout)
        return root, directory

    def defined(self, root, directory, app_dir):
        keys = set()
        for f in [root / 'stacks/fleet.env', root / '.env', directory / '.env.local', app_dir / 'secrets.env.local']:
            if f.exists():
                keys |= {m.group(1) for m in re.finditer(r'^([A-Za-z_][A-Za-z0-9_]*)=', f.read_text(), re.M)}
        return keys

    def test_every_variable_is_defined_somewhere(self):
        for node in LINUX_NODES + ['roastery']:
            with self.subTest(node=node):
                root, directory = self.generate(node)
                for source in list(directory.glob('*/docker-compose.yml')) + list(directory.glob('*/**/*.template')):
                    app_dir = directory / source.relative_to(directory).parts[0]
                    have = self.defined(root, directory, app_dir)
                    for line in source.read_text().splitlines():
                        if line.lstrip().startswith('#'):
                            continue
                        for m in self.VAR.finditer(line.replace('$$', '')):
                            name, default = m.group(1) or m.group(3), m.group(2) or ''
                            if default.startswith((':-', '-')) or name in ('SSH_CONNECTION',):
                                continue
                            if source.name == 'docker-compose.yml' and m.group(3):
                                continue  # bare $NAME in compose is the container's own shell
                            self.assertIn(name, have, f'{source.relative_to(root)} uses {name}, which nothing defines')

    def test_generated_values_and_idempotence(self):
        root, directory = self.generate('percolator')
        authelia = (directory / 'authelia/secrets.env.local').read_text()
        self.assertRegex(authelia, r'(?m)^AUTHELIA_SESSION_SECRET=[0-9a-f]{64}$')
        self.assertRegex(authelia, r"(?m)^VAULTWARDEN_OIDC_CLIENT_SECRET_HASH='\$pbkdf2")
        self.assertRegex(authelia, r"(?m)^AUTHELIA_OIDC_JWK_PRIVATE_KEY='-----BEGIN PRIVATE KEY-----\\n")
        lldap = (directory / 'lldap/secrets.env.local').read_text()
        password = re.search(r'^LLDAP_ADMIN_PASSWORD=(.*)$', lldap, re.M).group(1)
        self.assertIn(f'AUTHELIA_LDAP_PASSWORD={password}', authelia)
        traefik = (directory / 'traefik/secrets.env.local').read_text()
        self.assertIn('CF_DNS_API_TOKEN=REPLACE_ME', traefik)
        self.assertEqual((directory / 'vaultwarden/secrets.env.local').stat().st_mode & 0o777, 0o600)
        before = {f: f.read_text() for f in directory.glob('*/secrets.env.local')}
        path = str(Path(root).parent / 'bin') + os.pathsep + os.environ['PATH']
        script = (f'source "{root}/stacks/_lib/common.sh"; source "{root}/stacks/_lib/secrets.sh"; '
                  f'load_node "{directory}"; use_docker; generate_secrets')
        subprocess.run(['bash', '-c', script], env=dict(os.environ, PATH=path), stdin=subprocess.DEVNULL, check=True)
        self.assertEqual(before, {f: f.read_text() for f in directory.glob('*/secrets.env.local')})

    def test_sieve_ntfy_lists_and_mirror(self):
        _, directory = self.generate('sieve')
        ntfy = (directory / 'ntfy/secrets.env.local').read_text()
        self.assertRegex(ntfy, r"(?m)^NTFY_AUTH_USERS='barista:\$2a\$10\$a{53}:admin,gatus:\$2a\$10\$a{53}:user'$")
        token = re.search(r'^GATUS_NTFY_TOKEN=(tk_[0-9a-f]{29})$', ntfy, re.M).group(1)
        self.assertIn(f'NTFY_AUTH_TOKENS=gatus:{token}:gatus', ntfy)
        gatus = (directory / 'gatus/secrets.env.local').read_text()
        self.assertIn(f'GATUS_NTFY_TOKEN={token}', gatus)
        self.assertRegex(gatus, r'(?m)^NTFY_CRITICAL_TOPIC=purrbrews-[0-9a-f]{24}$')
        self.assertIn('PERIPHERY_ONBOARDING_KEY=\n', (directory / 'komodo-periphery/secrets.env.local').read_text())

    def test_renamed_keys_are_carried_over(self):
        tmp = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, tmp)
        root = copy_repo(tmp)
        directory = root / 'stacks/percolator'
        (directory / '.env.local').write_text("ACME_EMAIL=me@example.test\nPERCOLATOR_DISK_DEVICE_NVME=/dev/nvme0\n")
        subprocess.run(['bash', '-c', f'source "{root}/stacks/_lib/common.sh"; load_node "{directory}"; migrate_renamed_keys'],
                       check=True, capture_output=True)
        text = (directory / '.env.local').read_text()
        self.assertIn('TRAEFIK_ACME_EMAIL=me@example.test', text)
        self.assertIn('DISK_DEVICE=/dev/nvme0', text)
        self.assertIn('ACME_EMAIL=me@example.test', text)  # the old line stays


if __name__ == '__main__':
    unittest.main()
