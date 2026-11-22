"""Offline checks for the repo: python3 -m unittest discover -s tests -v

Layout since the 2026-11 rebuild: an app lives once under stacks/<group>/<app>,
a node is nodes/<node>/ (node.conf, local.env.example, wrappers). app() finds
an app's folder by name, the way stacks/_lib/common.sh's app_dir does.

Nothing here needs Docker or a real node. Where a script wants docker or sudo,
a fake one on PATH answers instead. A few tests are skipped under root,
because the scripts refuse to run as root on purpose.
"""
import importlib.util
import io
import json
import os
from pathlib import Path
import re
import shutil
import stat
import subprocess
import sys
import tempfile
import unittest

try:  # only two tests need it; without it they skip, like the root-only ones
    import yaml
except ImportError:
    yaml = None

ROOT = Path(__file__).resolve().parents[1]
STACKS = ROOT / 'stacks'
NODE_DIRS = ROOT / 'nodes'
NODES = ['sieve', 'percolator', 'cellar', 'mochaPot', 'grinder']
LINUX_NODES = NODES
AS_ROOT = os.geteuid() == 0


def load(name, filename):
    spec = importlib.util.spec_from_file_location(name, STACKS / '_lib' / filename)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


dns = load('dns', 'dns-records.py')
renderer = load('renderer', 'render-template.py')
FLEET = 'name,ip,mac\nsieve,192.168.1.10,02:00:00:00:00:10\npercolator,192.168.1.11,x\ncellar,192.168.1.12,x\nmochaPot,192.168.1.13,x\ngrinder,192.168.1.14,x\n'


def app(name, root=ROOT):
    """An app's folder, stacks/<group>/<name>: exactly one, or the test fails."""
    found = [d for d in (root / 'stacks').glob(f'*/{name}') if d.is_dir() and d.parent.name != '_lib']
    assert len(found) == 1, f'{name}: expected one stacks/<group>/{name}, found {found}'
    return found[0]


def node_conf(node):
    """APPS, NETWORK etc. from a node.conf, read the way bash would."""
    out = subprocess.run(['bash', '-c', f'TOOLS=(); BACKUP_HUB=false; source "{NODE_DIRS / node / "node.conf"}"; '
                          'echo "${APPS[*]}"; echo "$NETWORK"; echo "$NETWORK_SUBNET_KEY"; echo "$RESOLVER"; '
                          'echo "${TOOLS[*]}"; echo "$BACKUP_HUB"'],
                         capture_output=True, text=True, check=True).stdout.split('\n')
    return {'APPS': out[0].split(), 'NETWORK': out[1], 'NETWORK_SUBNET_KEY': out[2], 'RESOLVER': out[3],
            'TOOLS': out[4].split(), 'BACKUP_HUB': out[5]}


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
    shutil.copytree(NODE_DIRS, root / 'nodes', ignore=ignore)
    return root


class DNS(unittest.TestCase):
    def test_fixed_dhcp_roles_ignore_legacy_env_switch(self):
        primary = (app('pihole') / 'docker-compose.yml').read_text()
        secondary = (app('pihole-secondary') / 'docker-compose.yml').read_text()
        self.assertIn('FTLCONF_dhcp_active: "true"', primary)
        self.assertIn('FTLCONF_dhcp_active: "false"', secondary)
        self.assertNotIn('${PIHOLE_DHCP_ACTIVE', primary)
        self.assertNotIn('${PIHOLE_DHCP_ACTIVE', secondary)

    def test_actual_routes(self):
        # Which node answers for a name comes from node.conf: the node whose APPS runs the app.
        lines, hosts = dns.records(ROOT, 'example.test', io.StringIO(FLEET), '192.168.1.20 americano')
        for host, ip in [('authelia', 11), ('opencloud', 11), ('radicale', 11), ('komodo', 12), ('homeassistant', 12),
                         ('n8n', 14), ('llm', 14), ('pihole', 10), ('pihole-mochapot', 13)]:
            self.assertIn(f'address=/{host}.example.test/192.168.1.{ip}', lines)
            self.assertIn(f'local=/{host}.example.test/', lines)
        self.assertIn('filter-AAAA', lines)
        self.assertNotIn('local=/example.test/', lines)  # public ACME remains resolvable
        self.assertEqual(len(hosts), 6)
        self.assertIn('192.168.1.20 americano', hosts)   # an extra host gets a name, not a route

    def test_node_missing_from_the_fleet_list_keeps_its_existing_record(self):
        # A node that serves routes but isn't in the fleet list keeps the address
        # Pi-hole already has for it, run after run; a stale record for a node
        # that is in the list loses to the list.
        fleet = FLEET.replace('grinder,192.168.1.14,x\n', '')
        existing = '192.168.1.14 grinder;192.168.1.99 sieve'
        for _ in range(2):
            lines, hosts = dns.records(ROOT, 'example.test', io.StringIO(fleet), existing_hosts=existing)
            self.assertIn('address=/llm.example.test/192.168.1.14', lines)
            self.assertIn('address=/pihole.example.test/192.168.1.10', lines)
            self.assertIn('192.168.1.14 grinder', hosts)
            existing = ';'.join(hosts)

    def test_missing_node_is_error(self):
        with self.assertRaisesRegex(ValueError, 'missing from NODE_IPS'):
            dns.records(ROOT, 'example.test', io.StringIO(FLEET.replace('percolator,192.168.1.11,x\n', '')))

    def test_conflicting_route_is_error(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            file = root / 'stacks/group/app/docker-compose.yml'
            file.parent.mkdir(parents=True)
            file.write_text(' - "traefik.http.routers.x.rule=Host(`same.${DOMAIN}`)"\n')
            for node in ['sieve', 'cellar']:   # the same app, and so the same name, on two nodes
                conf = root / f'nodes/{node}/node.conf'
                conf.parent.mkdir(parents=True)
                conf.write_text('APPS=(app)\n')
            with self.assertRaisesRegex(ValueError, 'Conflicting'):
                dns.records(root, 'example.test', io.StringIO(FLEET))

    def test_primary_secondary_cli_parity_and_dhcp(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = copy_repo(tmp)
            outputs = {}
            for node, role in [('sieve', 'primary'), ('mochaPot', 'secondary')]:
                directory = root / 'nodes' / node
                path = directory / '.env.local'
                path.write_text('DOMAIN=example.test\nPIHOLE_DNS_HOSTS="192.168.1.20 roastery"\n'
                                'PIHOLE_DNS_EXTRA_HOSTS="192.168.1.30 workstation"\n'
                                'PIHOLE_DHCP_EXTRA_HOSTS=aa:bb:cc:dd:ee:ff,192.168.1.30,workstation\n')
                result = subprocess.run(['python3', str(STACKS / '_lib/dns-records.py'), '--node-dir', str(directory), '--role', role],
                                        input=FLEET, text=True, capture_output=True,
                                        env=dict(os.environ, DNS_SERVERS='192.168.1.10,192.168.1.13'))
                self.assertEqual(result.returncode, 0, result.stderr)
                outputs[node] = dns.read_env(path)
                self.assertEqual(path.stat().st_mode & 0o777, 0o600)
            primary = outputs['sieve']['PIHOLE_DNSMASQ_LINES'].split(';')
            secondary = outputs['mochaPot']['PIHOLE_DNSMASQ_LINES'].split(';')
            self.assertEqual(primary[:-1], secondary)
            self.assertEqual(primary[-1], 'dhcp-option=option:dns-server,192.168.1.10,192.168.1.13')
            self.assertEqual(outputs['sieve']['PIHOLE_DNS_HOSTS'], outputs['mochaPot']['PIHOLE_DNS_HOSTS'])
            leases = outputs['sieve']['PIHOLE_DHCP_HOSTS'].split(';')
            self.assertIn('02:00:00:00:00:10,192.168.1.10,sieve', leases)
            self.assertIn('aa:bb:cc:dd:ee:ff,192.168.1.30,workstation', leases)
            self.assertNotIn('PIHOLE_DHCP_HOSTS', outputs['mochaPot'])


class DHCPHandover(unittest.TestCase):
    # enable-dhcp.sh's range check read only the node's .env.local; LAN_CIDR
    # and GATEWAY moved to fleet.env in the restructure, and the handover died
    # on a KeyError (2026-11-19). Run its check as sieve would.
    def check(self, env_local):
        script = (app('pihole') / 'enable-dhcp.sh').read_text()
        block = re.search(r"^python3 - \"\$DIR\" \"\$LIB\" <<'PY'\n(.*?)^PY$", script, re.M | re.S).group(1)
        tmp = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, tmp)
        (tmp / '.env.local').write_text(env_local)
        return subprocess.run([sys.executable, '-c', block, str(tmp), str(STACKS / '_lib')],
                              capture_output=True, text=True)

    def test_sieves_range_passes_with_the_fleet_settings(self):
        example = (NODE_DIRS / 'sieve' / 'local.env.example').read_text()
        r = self.check(example)
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn('192.168.1.50–192.168.1.250; gateway 192.168.1.1', r.stdout)

    def test_a_range_over_the_gateway_is_refused(self):
        r = self.check('PIHOLE_DHCP_START=192.168.1.1\nPIHOLE_DHCP_END=192.168.1.250\n')
        self.assertNotEqual(r.returncode, 0)
        self.assertIn('refusing activation', r.stdout + r.stderr)


class Render(unittest.TestCase):
    def node(self, root, name, conf='APPS=()\n'):
        node = root / 'nodes' / name
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
                node = self.node(root, name, f'RESOLVER={role}\nAPPS=(pihole)\n')
                folder = root / 'stacks/network/pihole'
                folder.mkdir(parents=True)
                template = folder / 'config.template'
                template.write_text('dns=${PIHOLE_DNSMASQ_LINES}\n')
                refresh = lib / 'refresh-dns.sh'
                refresh.write_text('#!/usr/bin/env bash\nset -eu\n'
                                   'printf "PIHOLE_DNSMASQ_LINES=\'address=/ollama.example.test/192.168.1.20\'\\n" > "$1/.env.local"\n')
                command = ['bash', str(lib / 'render-configs.sh'), str(node)]
                result = subprocess.run(command, text=True, capture_output=True)
                self.assertEqual(result.returncode, 0, result.stderr)
                output = template.with_suffix('')
                self.assertEqual(output.read_text(), 'dns=address=/ollama.example.test/192.168.1.20\n')
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
            node = self.node(root, 'test', 'APPS=(a b c)\n')
            apps = root / 'stacks/group'
            for name in ['a', 'b', 'c', 'elsewhere']:   # `elsewhere` isn't in APPS: another node's app
                directory = apps / name / 'config'
                directory.mkdir(parents=True)
                (directory / 'config.template').write_text('value: ${APP_SECRET}\n')
                (directory / 'config').write_text('old')
            (apps / 'a/secrets.env.local').write_text('APP_SECRET=alpha\n')
            (apps / 'c/secrets.env.local').write_text('return 1\n')
            (apps / 'elsewhere/secrets.env.local').write_text('APP_SECRET=not-ours\n')
            env = os.environ.copy()
            env.pop('APP_SECRET', None)
            result = subprocess.run(['bash', str(root / 'stacks/_lib/render-configs.sh'), str(node)], env=env, capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual((apps / 'a/config/config').read_text(), 'value: alpha\n')
            self.assertEqual((apps / 'b/config/config').read_text(), 'old')
            self.assertEqual((apps / 'c/config/config').read_text(), 'old')
            self.assertEqual((apps / 'elsewhere/config/config').read_text(), 'old', "only this node's apps render")
            self.assertIn('Cannot load', result.stderr)

    @unittest.skipIf(AS_ROOT, 'the scripts refuse to run as root')
    def test_layering_fleet_then_node_then_app(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            shutil.copytree(STACKS / '_lib', root / 'stacks/_lib')
            (root / 'stacks/fleet.env').write_text('A=fleet\nB=fleet\nC=fleet\n')
            node = self.node(root, 'test', 'TOOLS=(restic)\n')
            (node / '.env.local').write_text('B=node\nC=node\n')
            app = root / 'stacks/backup/restic'
            app.mkdir(parents=True)
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
        for script in ['compose.sh', 'setup-secrets.sh', 'render-configs.sh', 'firewall.sh', 'backup.sh']:
            copies = {(NODE_DIRS / node / script).read_text() for node in NODES}
            self.assertEqual(len(copies), 1, f'{script} differs between nodes')
            self.assertIn('/../../stacks/_lib/', copies.pop())

    def test_the_nodes_are_the_folders_under_nodes(self):
        self.assertEqual(sorted(NODES), sorted(d.name for d in NODE_DIRS.iterdir() if (d / 'node.conf').is_file()))
        # Nothing node-shaped is left under stacks/: only _lib and the stack groups.
        self.assertEqual(list(STACKS.glob('*/node.conf')), [])

    def test_every_app_has_one_home_and_a_node_that_runs_it(self):
        homes = {}
        for compose in STACKS.glob('*/*/docker-compose.yml'):
            self.assertNotIn(compose.parent.name, homes, f'two folders are called {compose.parent.name}')
            homes[compose.parent.name] = compose.parent
        run = set()
        for node in NODES:
            conf = node_conf(node)
            self.assertEqual(len(conf['APPS']), len(set(conf['APPS'])), f'{node}: an app is listed twice')
            for name in conf['APPS']:
                self.assertIn(name, homes, f'{node}: node.conf lists {name}, which has no stacks/<group>/{name}/docker-compose.yml')
            for name in conf['TOOLS']:
                self.assertTrue(app(name).is_dir(), f'{node}: TOOLS lists {name}')
                self.assertNotIn(name, homes, f'{node}: {name} has a compose file, so it belongs in APPS')
            run |= set(conf['APPS'])
        self.assertEqual(sorted(set(homes) - run), [], 'apps no node.conf runs: add them to a node or move them to deprecated/')

    def test_voice_runs_on_the_three_thinkcentres(self):
        # One room each (owner, 2026-11-17): engines and satellite together.
        voice = {'whisper', 'piper', 'voice-satellite'}
        for node in NODES:
            apps = set(node_conf(node)['APPS'])
            if node in ('sieve', 'percolator', 'cellar'):
                self.assertLessEqual(voice, apps, node)
            else:
                self.assertFalse(voice & apps, node)
        fleet = (STACKS / 'fleet.env').read_text()
        for key in ['VOICE_LANGUAGE', 'VOICE_WHISPER_MODEL', 'VOICE_PIPER_VOICE']:
            self.assertRegex(fleet, rf'(?m)^{key}=\S+$')
        satellite = (app('voice-satellite') / 'docker-compose.yml').read_text()
        self.assertIn('DISABLE_PERIPHERAL_API: "1"', satellite)
        self.assertIn('network_mode: host', satellite)

    def test_every_node_uses_the_same_network_name_with_a_fixed_subnet(self):
        # One name everywhere, so an app can move between nodes without an edit,
        # and a pinned subnet, so firewall.sh works before any container has run.
        for node in NODES:
            conf = node_conf(node)
            self.assertEqual((conf['NETWORK'], conf['NETWORK_SUBNET_KEY']), ('proxy', 'PROXY_SUBNET'), node)
            example = (NODE_DIRS / node / 'local.env.example').read_text()
            self.assertRegex(example, r'(?m)^PROXY_SUBNET=172\.\d+\.\d+\.0/24$', node)
        for compose in STACKS.glob('*/*/docker-compose.yml'):
            self.assertNotRegex(compose.read_text(), r'\b(sieve_edge|cellar_net|grinder_net|mochapot_net)\b', str(compose))

    def test_fleet_env_addresses_are_consistent(self):
        import ipaddress
        fleet = dict(line.split('=', 1) for line in (STACKS / 'fleet.env').read_text().splitlines()
                     if re.match(r'^[A-Z_]+=', line))
        lan = ipaddress.ip_network(fleet['LAN_CIDR'])
        ips = {k[:-len('_LAN_IP')]: ipaddress.ip_address(v) for k, v in fleet.items() if k.endswith('_LAN_IP')}
        self.assertEqual(sorted(ips), sorted(n.upper() for n in NODES), 'one <NODE>_LAN_IP per folder under nodes/')
        self.assertEqual(len(set(ips.values())), len(ips), 'two nodes share an address')
        for name, ip in ips.items():
            self.assertIn(ip, lan, name)
        self.assertIn(ipaddress.ip_address(fleet['GATEWAY']), lan)
        self.assertNotIn(ipaddress.ip_address(fleet['GATEWAY']), ips.values())
        resolvers = {node_conf(n)['RESOLVER']: n for n in NODES if node_conf(n)['RESOLVER']}
        self.assertEqual(fleet['DNS_PRIMARY'], str(ips[resolvers['primary'].upper()]))
        self.assertEqual(fleet['DNS_SECONDARY'], str(ips[resolvers['secondary'].upper()]))
        hub = [n for n in NODES if node_conf(n)['BACKUP_HUB'] == 'true']
        self.assertEqual(len(hub), 1, 'exactly one backup hub')
        self.assertEqual(fleet['DUMP_STORE_HOST'], str(ips[hub[0].upper()]), 'the hub is the dump store')

    def test_every_rendered_file_is_gitignored(self):
        for template in STACKS.glob('*/**/*.template'):
            output = template.with_suffix('').relative_to(ROOT)
            ignored = subprocess.run(['git', '-C', str(ROOT), 'check-ignore', '-q', '--no-index', str(output)])
            self.assertEqual(ignored.returncode, 0, f'{output} must be in .gitignore: it can hold secrets')

    def test_node_local_files_are_gitignored(self):
        for path in ['nodes/sieve/.env.local', 'stacks/monitoring/ntfy/secrets.env.local',
                     'stacks/fleet-management/komodo-periphery/keys/core.pub', 'stacks/backup/restic/cache/x',
                     'stacks/backup/restic/backup.keys', 'stacks/backup/restic/secrets.env.local',
                     'stacks/ai/litellm/secrets.env.local', '.env', '.fleet/sieve.json',
                     'deprecated/stacks/roastery/traefik/secrets.env.local',
                     'deprecated/stacks/roastery/backup-target/authorized_keys']:
            ignored = subprocess.run(['git', '-C', str(ROOT), 'check-ignore', '-q', '--no-index', path])
            self.assertEqual(ignored.returncode, 0, path)

    def test_secrets_conf_kinds(self):
        kinds = {'hex', 'base64', 'value', 'prompt', 'copy', 'mirror', 'hash', 'rsa'}
        for spec in STACKS.glob('*/*/secrets*.conf'):
            for line in spec.read_text().splitlines():
                fields = line.split()
                if not fields or fields[0].startswith('#') or fields[0] == 'NOTE':
                    continue
                self.assertRegex(fields[0], r'^[A-Z_][A-Z0-9_]*$', f'{spec}: {line}')
                self.assertIn(fields[1], kinds, f'{spec}: {line}')
                if fields[1] in ('copy', 'mirror'):
                    self.assertTrue(app(fields[2]).is_dir(), f'{spec}: {line}')

    # Every registry image by tag and digest: the tag says what it is, the digest
    # makes a routine pull change nothing (a `main` or `latest` included), and
    # Dependabot moves both together. Only images built here (:local) are exempt.
    IMAGE_SOURCES = [
        *STACKS.glob('*/*/docker-compose.yml'),
        ROOT / 'stacks/automation/embedding-worker/Dockerfile',
        ROOT / 'stacks/backup/restic/restore-test.sh',
    ]

    def images(self):
        for source in self.IMAGE_SOURCES:
            for image in re.findall(r'^(?:\s*(?:image|x-image):\s*(?:&\w+\s+)?|FROM\s+|PG_IMAGE=)(\S+)',
                                    source.read_text(), re.M):
                if not image.startswith('*') and not image.endswith(':local'):
                    yield source, image

    def test_images_are_pinned(self):
        found = 0
        for source, image in self.images():
            found += 1
            with self.subTest(image=image, file=str(source.relative_to(ROOT))):
                self.assertRegex(image, r'^[^@\s]+:[^@/\s]+@sha256:[0-9a-f]{64}$',
                                 'pin a tag and its digest (python3 scripts/images.py <image:tag>)')
        self.assertGreater(found, 40)

    def test_one_digest_per_tag(self):
        seen = {}
        for source, image in self.images():
            tag, digest = image.split('@')
            with self.subTest(image=tag, file=str(source.relative_to(ROOT))):
                self.assertEqual(seen.setdefault(tag, digest), digest, 'the same tag pinned to two digests')

    def test_node_agents_are_one_folder_and_on_every_node(self):
        # Periphery and the Scrutiny collector used to be copied per node; now
        # each is one folder, and every node but the hub (which runs Komodo
        # Core and the Scrutiny hub itself) lists both.
        hub = [n for n in NODES if 'scrutiny' in node_conf(n)['APPS']]
        self.assertEqual(len(hub), 1)
        for node in NODES:
            apps = node_conf(node)['APPS']
            if node in hub:
                self.assertIn('komodo', apps)
                continue
            self.assertIn('komodo-periphery', apps, node)
            self.assertIn('scrutiny-collector', apps, node)
        collector = (app('scrutiny-collector') / 'docker-compose.yml').read_text()
        self.assertIn('${DISK_DEVICE_2:-/dev/null}', collector, 'a one-disk node must not need DISK_DEVICE_2')
        self.assertIn('${SCRUTINY_COLLECTOR_CONFIG:-./collector.yaml}', collector)
        # A node that overrides the collector's settings keeps the file in its own folder.
        for node in NODES:
            m = re.search(r'(?m)^SCRUTINY_COLLECTOR_CONFIG=/opt/purrbrews/(\S+)$', (NODE_DIRS / node / 'local.env.example').read_text())
            if m:
                self.assertTrue((ROOT / m.group(1)).is_file(), m.group(1))

    def test_paired_images_move_together(self):
        def versions(pattern):
            return {m.group(1) for _, image in self.images() if (m := re.search(pattern, image))}
        pairs = {
            'Immich server and machine learning': r'immich-app/immich-(?:server|machine-learning):(v[\d.]+)',
            'Komodo Core and every Periphery': r'moghtech/komodo-(?:core|periphery):([\d.]+)',
            'the Scrutiny hub and its collectors': r'analogj/scrutiny:(v[\d.]+)-',
            'Pi-hole on both DNS hosts': r'pihole/pihole:([\d.]+)',
        }
        for name, pattern in pairs.items():
            with self.subTest(name):
                self.assertEqual(len(versions(pattern)), 1, f'{name}: {sorted(versions(pattern))}')

    @unittest.skipUnless(yaml, 'needs PyYAML (apt install python3-yaml)')
    def test_dependabot_sees_every_compose_file_and_its_ignores_match(self):
        import fnmatch
        config = yaml.safe_load((ROOT / '.github/dependabot.yml').read_text())
        compose = next(u for u in config['updates'] if u['package-ecosystem'] == 'docker-compose')
        names = set()
        for file in STACKS.glob('*/*/docker-compose.yml'):
            folder = '/' + file.parent.relative_to(ROOT).as_posix()
            self.assertTrue(any(fnmatch.fnmatch(folder, d) for d in compose['directories']), folder)
            for service in (yaml.safe_load(file.read_text()).get('services') or {}).values():
                image = service.get('image')
                if isinstance(image, str):
                    path = image.split('@')[0].rsplit(':', 1)[0] if ':' in image.split('/')[-1] else image.split('@')[0]
                    first = path.split('/')[0]
                    # Dependabot names an image without its registry.
                    names.add(path.split('/', 1)[1] if ('.' in first or ':' in first) and '/' in path else path)
        for rule in compose.get('ignore', []):
            self.assertIn(rule['dependency-name'], names, 'an ignore rule that matches no image guards nothing')

    # Routes Gatus deliberately doesn't check end to end (the reasons would be in
    # stacks/monitoring/gatus/config/config.yaml). Everything else must have a check.
    NOT_WATCHED = set()

    @unittest.skipUnless(yaml, 'needs PyYAML (apt install python3-yaml)')
    def test_gatus_watches_only_what_exists(self):
        # A fresh fleet comes up one node at a time; with every GATUS_WATCH_*
        # false (sieve's local.env.example), only sieve's own core is checked,
        # so a node that isn't built yet sends no DOWN alert (2026-11-19).
        example = (NODE_DIRS / 'sieve' / 'local.env.example').read_text()
        switches = re.findall(r'(?m)^(GATUS_WATCH_[A-Z]+)=false$', example)
        compose = (app('gatus') / 'docker-compose.yml').read_text()
        for key in switches:
            self.assertIn(f'{key}: ${{{key}:-true}}', compose, key)
        text = (app('gatus') / 'config/config.yaml').read_text()
        used = set(re.findall(r'enabled: \$\{(GATUS_WATCH_[A-Z]+)\}', text))
        self.assertEqual(used, set(switches))
        env = dict.fromkeys(switches, 'false')
        config = yaml.safe_load(re.sub(r'\$\{([A-Z_]+)\}', lambda m: env.get(m.group(1), 'x'), text))
        on = {e['name'] for e in config['endpoints'] if e.get('enabled', True) is not False}
        self.assertEqual(on, {'healthchecks.io heartbeat', 'pihole → unbound (recursion)', 'pihole local override',
                              'dnssec validation', 'pihole web', 'traefik', 'ntfy', 'ntfy (public)', 'gateway',
                              'internet'})
        for e in config['endpoints']:
            if re.search(r'192\.168\.1\.1[1-4]\b', str(e.get('url', ''))):
                self.assertIs(e.get('enabled'), False, f'{e["name"]} watches another node without a switch')

    @unittest.skipUnless(yaml, 'needs PyYAML (apt install python3-yaml)')
    def test_every_route_has_an_end_to_end_check(self):
        routed = set()
        for file in STACKS.rglob('*'):
            if file.is_file() and file.suffix in ('.yml', '.yaml', '.template') and '.git' not in file.parts:
                active = '\n'.join(l for l in file.read_text().splitlines() if not l.lstrip().startswith('#'))
                routed |= set(re.findall(r'Host\(`([a-z0-9-]+)\.(?:\$\{DOMAIN\}|\{\{ env "DOMAIN" \}\})`\)', active))
        config = yaml.safe_load((app('gatus') / 'config/config.yaml').read_text())
        checks = {}
        for endpoint in config['endpoints']:
            m = re.match(r'https://([a-z0-9-]+)\.\$\{DOMAIN\}(/\S*)?$', endpoint['url'])
            if m:
                checks.setdefault(m.group(1), []).append(endpoint)
        self.assertEqual(sorted(routed - set(checks) - self.NOT_WATCHED), [],
                         'routes with no Gatus check: add one under "Every app, end to end"')
        authelia = (app('authelia') / 'config/configuration.yml.template').read_text()
        admin = set(re.findall(r"'([a-z0-9-]+)\.\$\{DOMAIN\}'",
                               re.search(r'domain: &admin_hosts\n(.*?)\n\s+subject:', authelia, re.S).group(1)))
        for host in sorted((admin & set(checks)) - self.NOT_WATCHED):
            with self.subTest(host=host):
                # At least one check must prove the login is required (fail on a
                # 200); a host may also have a deliberately open path (perch's
                # /healthz), so not every check has to.
                proves_login = [e for e in checks[host]
                                if any(c.startswith('[STATUS]') and '200' not in c for c in e['conditions'])]
                self.assertTrue(proves_login, f'{host} is admin-only: a check must fail on a 200 (a skipped login)')

    def test_no_references_to_docs_that_are_not_here(self):
        for file in ROOT.rglob('*'):
            if not file.is_file() or '.git' in file.parts or file.suffix in ('.pyc', '.exe') or file.name == 'test_infrastructure.py':
                continue
            if 'deprecated' in file.relative_to(ROOT).parts:
                continue  # the archive is kept as it was
            if file.name == 'runbook.md':
                continue  # dated history is allowed to mention what was true then
            text = file.read_text(errors='ignore')
            for stale in ['infrastructure.md', 'edge-and-automation.md', 'generate-secrets.sh', 'second-brain', 'Second brain']:
                self.assertNotIn(stale, text, f'{file.relative_to(ROOT)} mentions {stale}')


class Firewall(unittest.TestCase):
    def dry_run(self, node, env_local, network_subnet=None):
        with tempfile.TemporaryDirectory() as tmp:
            root = copy_repo(tmp)
            (root / 'nodes' / node / '.env.local').write_text(env_local)
            env = dict(os.environ)
            if network_subnet:
                env['NETWORK_SUBNET'] = network_subnet
            result = subprocess.run(['bash', str(root / 'nodes' / node / 'firewall.sh'), '--dry-run'],
                                    env=env, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            return result.stdout

    def test_sieve(self):
        out = self.dry_run('sieve', 'PROXY_SUBNET=172.31.10.0/24\n')
        self.assertIn('ufw allow proto udp from 192.168.1.0/24 to any port 53', out)
        self.assertIn('ufw allow proto udp from any to any port 67', out)
        self.assertIn('ufw allow proto tcp from 172.31.10.0/24 to any port 8080', out)
        self.assertIn('ufw route allow proto tcp from 192.168.1.0/24 to 172.31.10.0/24 port 443', out)
        self.assertIn('purrbrews\\ sieve:\\ dns\\ from\\ LAN', out)
        # only Docker's own subnets may skip the rules, not the whole LAN
        self.assertIn('ufw-docker install --docker-subnets', out)

    def test_percolator_forward_auth_clients(self):
        out = self.dry_run('percolator', 'FORWARD_AUTH_CLIENTS=192.168.1.10 192.168.1.12\nPROXY_SUBNET=172.30.0.0/24\n'
                                         "MAIL_RELAY_CLIENTS='192.168.1.13 192.168.1.14'\n")
        self.assertIn('ufw route allow proto tcp from 192.168.1.0/24 to any port 443', out)
        # The mail relay: the listed nodes, and not the whole LAN.
        self.assertIn('ufw route allow proto tcp from 192.168.1.14 to any port 587', out)
        self.assertNotIn('from 192.168.1.0/24 to any port 587', out)
        self.assertIn('ufw route allow proto tcp from 192.168.1.10 to any port 9091', out)
        self.assertIn('ufw route allow proto tcp from 192.168.1.12 to any port 9091', out)
        self.assertIn('forward-auth\\ from\\ 192.168.1.12', out)

    def test_host_networked_apps_allow_the_proxy_network(self):
        out = self.dry_run('mochaPot', 'PROXY_SUBNET=172.30.13.0/24\n')
        for port in [8095, 8081]:
            self.assertIn(f'allow proto tcp from 172.30.13.0/24 to any port {port}', out)
        self.assertNotIn('port 8123', out)  # Home Assistant is on cellar now
        self.assertNotIn('port 67', out)
        out = self.dry_run('grinder', '', network_subnet='172.18.0.0/16')
        self.assertIn('allow proto tcp from 172.18.0.0/16 to any port 6052', out)
        # published ports are matched after DNAT, on the container's port
        self.assertIn('route allow proto tcp from 192.168.1.0/24 to any port 5000', out)
        self.assertNotIn('port 5001', out)

    def test_voice_answers_home_assistant_only(self):
        # Wyoming and the ESPHome API have no authentication: cellar (Home
        # Assistant) is the only address let in, on every voice node.
        extra = {'percolator': "FORWARD_AUTH_CLIENTS=192.168.1.10\nMAIL_RELAY_CLIENTS='192.168.1.13'\n"}
        for node in ['sieve', 'percolator', 'cellar']:
            out = self.dry_run(node, 'PROXY_SUBNET=172.31.10.0/24\n' + extra.get(node, ''))
            for rule in ['route allow proto tcp from 192.168.1.12 to any port 10300',
                         'route allow proto tcp from 192.168.1.12 to any port 10200',
                         'allow proto tcp from 192.168.1.12 to any port 6053',
                         'allow proto udp from 192.168.1.12 to any port 5353']:
                self.assertIn(rule, out, node)
            self.assertNotIn('from 192.168.1.13 to any port 10300', out, node)  # mochaPot no longer
            for port in [10300, 10200, 6053]:
                self.assertNotRegex(out, rf'from 192\.168\.1\.0/24 to any port {port}\b', node)

    def test_cellar_and_bad_tokens(self):
        out = self.dry_run('cellar', 'PROXY_SUBNET=172.30.12.0/24\n')
        for port in [80, 443, 9120, 8080]:
            self.assertIn(f'route allow proto tcp from 192.168.1.0/24 to any port {port}', out)
        # Home Assistant (host-networked) from the LAN and from this node's Traefik
        self.assertIn('allow proto tcp from 192.168.1.0/24 to any port 8123', out)
        self.assertIn('allow proto tcp from 172.30.12.0/24 to any port 8123', out)
        self.assertNotIn('port 445', out)  # smb stays closed until its rule is uncommented
        with tempfile.TemporaryDirectory() as tmp:
            root = copy_repo(tmp)
            (root / 'nodes/percolator/.env.local').write_text('FORWARD_AUTH_CLIENTS=REPLACE_ME\n')
            result = subprocess.run(['bash', str(root / 'nodes/percolator/firewall.sh'), '--dry-run'], capture_output=True, text=True)
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
        (root / '.env').write_text(f'NODE={node}\nNODE_IP=192.168.1.99\nTZ=Asia/Kolkata\nPUID=1000\nPGID=1000\n'
                                   'PROJECT_DIR=/opt/purrbrews\nDATA_DIR=/srv/data\nMEDIA_DIR=/srv/media\n')
        directory = root / 'nodes' / node
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
        for node in NODES:
            with self.subTest(node=node):
                root, directory = self.generate(node)
                conf = node_conf(node)
                sources = []
                for name in conf['APPS'] + conf['TOOLS']:
                    folder = app(name, root)
                    sources += [(folder, f) for f in [folder / 'docker-compose.yml', *folder.rglob('*.template')] if f.is_file()]
                self.assertTrue(sources)
                for app_dir, source in sources:
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
        authelia = (app('authelia', root) / 'secrets.env.local').read_text()
        self.assertRegex(authelia, r'(?m)^AUTHELIA_SESSION_SECRET=[0-9a-f]{64}$')
        self.assertRegex(authelia, r"(?m)^VAULTWARDEN_OIDC_CLIENT_SECRET_HASH='\$pbkdf2")
        self.assertRegex(authelia, r"(?m)^AUTHELIA_OIDC_JWK_PRIVATE_KEY='-----BEGIN PRIVATE KEY-----\\n")
        lldap = (app('lldap', root) / 'secrets.env.local').read_text()
        password = re.search(r'^LLDAP_ADMIN_PASSWORD=(.*)$', lldap, re.M).group(1)
        self.assertIn(f'AUTHELIA_LDAP_PASSWORD={password}', authelia)
        traefik = (app('traefik-ingress', root) / 'secrets.env.local').read_text()
        self.assertIn('CF_DNS_API_TOKEN=REPLACE_ME', traefik)
        self.assertEqual((app('vaultwarden', root) / 'secrets.env.local').stat().st_mode & 0o777, 0o600)
        # Only percolator's apps got a secrets file: another node's are untouched.
        self.assertFalse((app('pihole', root) / 'secrets.env.local').exists())
        before = {f: f.read_text() for f in (root / 'stacks').glob('*/*/secrets.env.local')}
        self.assertGreater(len(before), 10)
        path = str(Path(root).parent / 'bin') + os.pathsep + os.environ['PATH']
        script = (f'source "{root}/stacks/_lib/common.sh"; source "{root}/stacks/_lib/secrets.sh"; '
                  f'load_node "{directory}"; use_docker; generate_secrets')
        subprocess.run(['bash', '-c', script], env=dict(os.environ, PATH=path), stdin=subprocess.DEVNULL, check=True)
        self.assertEqual(before, {f: f.read_text() for f in (root / 'stacks').glob('*/*/secrets.env.local')})

    def test_sieve_ntfy_lists_and_mirror(self):
        root, directory = self.generate('sieve')
        ntfy = (app('ntfy', root) / 'secrets.env.local').read_text()
        self.assertRegex(ntfy, r"(?m)^NTFY_AUTH_USERS='barista:\$2a\$10\$a{53}:admin,gatus:\$2a\$10\$a{53}:user'$")
        token = re.search(r'^GATUS_NTFY_TOKEN=(tk_[0-9a-f]{29})$', ntfy, re.M).group(1)
        self.assertIn(f'NTFY_AUTH_TOKENS=gatus:{token}:gatus', ntfy)
        gatus = (app('gatus', root) / 'secrets.env.local').read_text()
        self.assertIn(f'GATUS_NTFY_TOKEN={token}', gatus)
        self.assertRegex(gatus, r'(?m)^NTFY_CRITICAL_TOPIC=purrbrews-[0-9a-f]{24}$')
        self.assertIn('PERIPHERY_ONBOARDING_KEY=\n', (app('komodo-periphery', root) / 'secrets.env.local').read_text())

    def test_the_hub_makes_the_backup_password_and_the_others_are_asked_for_it(self):
        # restic's secrets.hook picks the spec from node.conf's BACKUP_HUB.
        root, _ = self.generate('cellar')
        hub = (app('restic', root) / 'secrets.env.local').read_text()
        self.assertRegex(hub, r'(?m)^RESTIC_PASSWORD=[0-9a-f]{64}$')
        self.assertRegex(hub, r'(?m)^RCLONE_CRYPT_PASSWORD=[0-9a-f]{64}$')
        root, _ = self.generate('sieve')
        client = (app('restic', root) / 'secrets.env.local').read_text()
        self.assertIn('RESTIC_PASSWORD=REPLACE_ME\n', client)
        self.assertNotIn('RCLONE_', client)

    def test_renamed_keys_are_carried_over(self):
        tmp = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, tmp)
        root = copy_repo(tmp)
        directory = root / 'nodes/percolator'
        (directory / '.env.local').write_text("ACME_EMAIL=me@example.test\nPERCOLATOR_DISK_DEVICE_NVME=/dev/nvme0\n")
        subprocess.run(['bash', '-c', f'source "{root}/stacks/_lib/common.sh"; load_node "{directory}"; migrate_renamed_keys'],
                       check=True, capture_output=True)
        text = (directory / '.env.local').read_text()
        self.assertIn('TRAEFIK_ACME_EMAIL=me@example.test', text)
        self.assertIn('DISK_DEVICE=/dev/nvme0', text)
        self.assertIn('ACME_EMAIL=me@example.test', text)  # the old line stays


class PastedValues(unittest.TestCase):
    """What a paste brings along (a \r, quotes, spaces) comes off before a secret is stored."""

    def clean(self, value):
        result = subprocess.run(['bash', '-c', 'source "$1" >/dev/null 2>&1; clean_pasted "$2"', '_',
                                 str(STACKS / '_lib' / 'common.sh'), value], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        return result.stdout

    def test_quotes_spaces_and_carriage_returns(self):
        cid = '123-abc.apps.googleusercontent.com'
        for pasted in [cid, f"'{cid}'", f'"{cid}"', f'  {cid} ', f'{cid}\r', f' "{cid}"\r']:
            self.assertEqual(self.clean(pasted), cid, repr(pasted))

    def test_a_typed_answer_comes_back_as_typed(self):
        # ask() only reads from a terminal, so give it one.
        import pty
        master, slave = pty.openpty()
        script = 'source "$1"; source "$2"; printf "[%s]" "$(ask Question)"'
        proc = subprocess.Popen(['bash', '-c', script, '_', str(STACKS / '_lib' / 'common.sh'),
                                 str(STACKS / '_lib' / 'secrets.sh')],
                                stdin=slave, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
        os.write(master, b'abc\n')
        out, _ = proc.communicate(timeout=10)
        os.close(master); os.close(slave)
        self.assertEqual(out.decode(), '[abc]')

    def test_quotes_inside_a_value_stay(self):
        self.assertEqual(self.clean('a"b'), 'a"b')
        self.assertEqual(self.clean("it's"), "it's")


class Backup(unittest.TestCase):
    """_lib/backup.sh and the apps' backup files."""

    def plan(self, node, root=None):
        base = root or ROOT
        return subprocess.run(['bash', str(base / 'nodes' / node / 'backup.sh'), 'plan'],
                              capture_output=True, text=True)

    def test_every_node_plans(self):
        for node in LINUX_NODES:
            with self.subTest(node=node):
                result = self.plan(node)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn('Files (restic --host', result.stdout)

    def test_backup_files_only_name_known_apps(self):
        run = {name for node in NODES for name in node_conf(node)['APPS']}
        for spec in STACKS.glob('*/*/backup'):
            name = spec.parent.name
            self.assertIn(name, run, f'{spec}: no node.conf runs {name}, so it would never be backed up')

    def test_every_node_has_the_backup_secrets(self):
        restic = app('restic')
        self.assertRegex((restic / 'secrets.conf').read_text(), r'(?m)^NTFY_URL\s+prompt optional')
        self.assertRegex((restic / 'secrets.hub.conf').read_text(), r'(?m)^RESTIC_PASSWORD\s+hex 64$')
        self.assertRegex((restic / 'secrets.client.conf').read_text(), r'(?m)^RESTIC_PASSWORD\s+prompt ')
        for node in NODES:
            self.assertIn('restic', node_conf(node)['TOOLS'], node)

    def test_the_repository_is_on_the_hub(self):
        fleet = {k: v for k, _, v in (l.partition('=') for l in (STACKS / 'fleet.env').read_text().splitlines())
                 if k and not k.startswith('#')}
        m = re.fullmatch(r'sftp:([a-z_][a-z0-9_-]*)@([0-9.]+):(/[A-Za-z0-9._/-]+)', fleet['BACKUP_REPOSITORY'])
        self.assertTrue(m, fleet['BACKUP_REPOSITORY'])
        self.assertEqual(m.group(2), fleet['CELLAR_LAN_IP'], 'the repository is on cellar, the hub')
        self.assertRegex(fleet['BACKUP_REPO_ROOT'], r'^/[A-Za-z0-9._/-]+$')

    def test_nothing_live_wakes_roastery(self):
        # The repository moved to cellar, which doesn't sleep (W2, 2026-11-18).
        files = [*STACKS.rglob('*.sh'), *STACKS.rglob('*.service'), *STACKS.rglob('*.timer'), *NODE_DIRS.rglob('*')]
        for file in files:
            if file.is_file():
                text = file.read_text(errors='replace')
                for word in ['wake_roastery', 'ROASTERY_WOL_MAC', 'PBROASTERY', 'send_magic_packet', 'roastery:']:
                    self.assertNotIn(word, text, f'{file.relative_to(ROOT)}: {word}')

    def repo_path(self, node, env_local):
        tmp = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, tmp)
        root = copy_repo(tmp)
        (root / 'nodes' / node / '.env.local').write_text(env_local)
        script = ('source "$1/stacks/_lib/common.sh"; source "$LIB/restic-env.sh"; '
                  'load_node "$1/nodes/$2"; repo_local_path')
        return subprocess.run(['bash', '-c', script, '_', str(root), node], capture_output=True, text=True,
                              env=dict(os.environ, RESTIC_PASSWORD='test'))

    def test_the_hub_finds_the_repository_inside_the_chroot(self):
        result = self.repo_path('cellar', '')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, '/srv/backup/restic')
        other = self.repo_path('percolator', '')
        self.assertNotEqual(other.returncode, 0)
        self.assertIn('only on disk on the backup hub', other.stderr)
        local = self.repo_path('percolator', 'BACKUP_REPOSITORY=/mnt/usb/restic\n')
        self.assertEqual(local.stdout, '/mnt/usb/restic', local.stderr)

    def repo_setup(self, keys):
        tmp = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, tmp)
        root = copy_repo(tmp)
        (root / '.env').write_text('NODE=cellar\nNODE_IP=192.168.1.12\n')
        key = tmp / 'purrbrews-backup'
        (tmp / 'purrbrews-backup.pub').write_text('ssh-ed25519 AAAAhub purrbrews-backup@cellar\n')
        (tmp / 'backup.keys').write_text(keys)
        env = dict(os.environ, BACKUP_KEY=str(key), BACKUP_KEYS_FILE=str(tmp / 'backup.keys'))
        return subprocess.run(['bash', str(app('restic', root) / 'repo-setup.sh'), '--check'],
                              capture_output=True, text=True, env=env)

    def test_repo_setup_pins_every_key_to_its_node(self):
        result = self.repo_setup('# a comment\n'
                                 'percolator from="192.168.1.11" ssh-ed25519 AAAAperc purrbrews-backup@percolator\n'
                                 'sieve from="192.168.1.10" ssh-ed25519 AAAAsieve purrbrews-backup@sieve  # trailing\n')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        lines = [line for line in result.stdout.splitlines() if line.startswith('from=')]
        self.assertEqual(lines, [
            'from="192.168.1.12",restrict ssh-ed25519 AAAAhub purrbrews-backup@cellar',
            'from="192.168.1.11",restrict ssh-ed25519 AAAAperc purrbrews-backup@percolator',
            'from="192.168.1.10",restrict ssh-ed25519 AAAAsieve purrbrews-backup@sieve'])
        self.assertIn('chroot /srv/backup, repository /srv/backup/restic', result.stdout)

    def test_repo_setup_refuses_bad_lines(self):
        for line, why in [('roastery from="192.168.1.20" ssh-ed25519 AAAA x', "isn't a node"),
                          ('cellar from="192.168.1.12" ssh-ed25519 AAAA x', 'is the hub'),
                          ('sieve ssh-ed25519 AAAA x', 'from='),
                          ('sieve from="192.168.1.10" ssh-rsa AAAA x', 'ssh-ed25519')]:
            result = self.repo_setup(line + '\n')
            self.assertNotEqual(result.returncode, 0, line)
            self.assertIn(why, result.stderr, line)

    def test_only_the_hub_installs_the_hub_timers(self):
        script = ('source "$1/stacks/_lib/common.sh"; load_node "$1/nodes/$2"; '
                  'eval "$(sed -n \'/^node_units()/,/^}/p\' "$1/stacks/_lib/backup.sh")"; node_units')
        units = {}
        for node in NODES:
            out = subprocess.run(['bash', '-c', script, '_', str(ROOT), node], capture_output=True, text=True, check=True).stdout
            units[node] = sorted(Path(line).name for line in out.split())
        self.assertIn('drive-sync.timer', units['cellar'])
        self.assertNotIn('purrbrews-wake-roastery.timer', units['cellar'])
        for node in NODES:
            if node != 'cellar':
                self.assertEqual(units[node], [], node)
        for unit in app('restic').glob('*.service'):
            self.assertNotIn('stacks/cellar', unit.read_text(), unit.name)

    def test_bad_lines_are_rejected(self):
        tmp = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, tmp)
        root = copy_repo(tmp)
        spec = root / 'stacks/automation/n8n/backup'
        for bad in ['tar n8n', 'path /etc', 'path ../../etc', 'sqlite n8n', 'pg a b c', 'exclude cache/../../x']:
            with self.subTest(line=bad):
                spec.write_text(bad + '\n')
                result = self.plan('grinder', root)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn('n8n/backup', result.stderr)

    def test_excludes_are_scoped_to_their_app(self):
        out = self.plan('percolator').stdout
        self.assertIn('/srv/data/vaultwarden/**/db.sqlite3*', out)
        self.assertIn('/srv/data/immich/library/thumbs', out)
        self.assertNotIn('/srv/data/immich/**/db.sqlite3', out)

    @unittest.skipUnless(AS_ROOT and shutil.which('restic') and shutil.which('sqlite3') and shutil.which('setpriv'),
                         'needs root, restic, sqlite3 and setpriv')
    def test_dump_and_files_into_a_local_repository(self):
        tmp = Path(tempfile.mkdtemp(dir='/tmp'))
        self.addCleanup(shutil.rmtree, tmp)
        tmp.chmod(0o755)
        root = copy_repo(tmp)
        data, repo, dumps = tmp / 'data', tmp / 'repo', tmp / 'dumps'
        (data / 'vaultwarden/icon_cache').mkdir(parents=True)
        subprocess.run(['sqlite3', str(data / 'vaultwarden/db.sqlite3'),
                        'pragma journal_mode=wal; create table c(x); insert into c values (42);'],
                       check=True, capture_output=True)
        (data / 'vaultwarden/rsa_key.pem').write_text('key')
        (data / 'vaultwarden/icon_cache/a.png').write_text('png')
        (root / '.env').write_text(f'NODE_IP=192.168.1.11\nDATA_DIR={data}\n')
        node = root / 'nodes/percolator'
        node.joinpath('node.conf').write_text('APPS=(vaultwarden)\n')
        (node / '.env.local').write_text(f'BACKUP_REPOSITORY={repo}\nDUMP_DIR={dumps}\nDUMP_STORE_HOST=192.168.1.11\n')
        (app('restic', root) / 'secrets.env.local').write_text('RESTIC_PASSWORD=test\n')
        env = dict(os.environ, BACKUP_KEY=str(tmp / 'key'), BACKUP_ETC=str(tmp / 'etc'),
                   BACKUP_CACHE=str(tmp / 'cache'), BACKUP_LOCK=str(tmp / 'lock'), RESTIC_PASSWORD='test',
                   PATH=f"{fake_bin(tmp / 'bin')}:{os.environ['PATH']}")
        subprocess.run(['restic', '-q', '-r', str(repo), 'init'], env=env, check=True, capture_output=True)
        result = subprocess.run(['bash', str(node / 'backup.sh'), 'nightly'], env=env, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        dump = dumps / 'percolator/vaultwarden/vault.sql.gz'
        self.assertIn('INSERT INTO c VALUES(42);', subprocess.run(['bash', '-c', f'gzip -dc {dump}'],
                                                                  capture_output=True, text=True).stdout)
        listing = subprocess.run(['restic', '-r', str(repo), 'ls', 'latest', '--tag', 'files'],
                                 env=env, capture_output=True, text=True, check=True).stdout
        self.assertIn('rsa_key.pem', listing)
        self.assertNotIn('db.sqlite3', listing)   # the live database: the dump has it
        self.assertNotIn('icon_cache', listing)
        self.assertIn('.env.local', listing)      # the node's own settings always go
        store = subprocess.run(['bash', str(node / 'backup.sh'), 'store'], env=env, capture_output=True, text=True)
        self.assertEqual(store.returncode, 0, store.stderr)

    @unittest.skipUnless(AS_ROOT and all(shutil.which(c) for c in ['restic', 'rclone', 'flock']),
                         'needs root, restic, rclone and flock')
    def test_drive_sync_never_mirrors_an_empty_or_different_repository(self):
        # cellar's drive-sync makes Drive match the repository on cellar's disk.
        # An empty or re-initialised repository there (roastery's was wiped
        # 2026-10-07) must stop the sync instead of replacing the offsite copy.
        tmp = Path(tempfile.mkdtemp(dir='/tmp'))
        self.addCleanup(shutil.rmtree, tmp)
        root = copy_repo(tmp)
        repo, drive, etc = tmp / 'restic-repo', tmp / 'drive', tmp / 'etc'
        etc.mkdir()
        (etc / 'rclone.conf').write_text(f'[drive-crypt]\ntype = alias\nremote = {drive}\n')
        # NODE: drive-sync.sh lives with restic now and finds its node from here.
        (root / '.env').write_text(f'NODE=cellar\nNODE_IP=192.168.1.12\nDATA_DIR={tmp / "data"}\n')
        node = root / 'nodes/cellar'
        (node / '.env.local').write_text(f'BACKUP_REPOSITORY={repo}\nDUMP_DIR={tmp / "dumps"}\n'
                                         'DUMP_STORE_HOST=192.168.1.12\n')
        (app('restic', root) / 'secrets.env.local').write_text('RESTIC_PASSWORD=test\n')
        env = dict(os.environ, BACKUP_ETC=str(etc), BACKUP_LOCK=str(tmp / 'lock'), BACKUP_CACHE=str(tmp / 'cache'),
                   RESTIC_PASSWORD='test', PATH=f"{fake_bin(tmp / 'bin')}:{os.environ['PATH']}")

        def init():
            subprocess.run(['restic', '-q', '-r', str(repo), 'init'], env=env, check=True, capture_output=True)

        def sync():
            return subprocess.run(['bash', str(app('restic', root) / 'drive-sync.sh')], env=env, capture_output=True, text=True)

        init()
        first = sync()
        self.assertEqual(first.returncode, 0, first.stdout + first.stderr)
        original = (drive / 'repo/config').read_bytes()
        files_before = sorted(p.relative_to(drive) for p in (drive / 'repo').rglob('*'))

        shutil.rmtree(repo)                    # wiped: the folder is back, empty
        repo.mkdir()
        wiped = sync()
        self.assertNotEqual(wiped.returncode, 0)
        self.assertIn('no restic repository', wiped.stdout + wiped.stderr)
        self.assertEqual((drive / 'repo/config').read_bytes(), original)

        shutil.rmtree(repo)                    # rebuilt with a fresh `restic init`
        init()
        other = sync()
        self.assertNotEqual(other.returncode, 0)
        self.assertIn('not the one on Drive', other.stdout + other.stderr)
        self.assertEqual(sorted(p.relative_to(drive) for p in (drive / 'repo').rglob('*')), files_before)

        shutil.rmtree(repo)                    # put back from Drive (the recovery kit)
        shutil.copytree(drive / 'repo', repo)
        back = sync()
        self.assertEqual(back.returncode, 0, back.stdout + back.stderr)

    @unittest.skipUnless(AS_ROOT and all(shutil.which(c) for c in ['restic', 'sqlite3', 'setpriv']),
                         'needs root, restic, sqlite3 and setpriv')
    def test_glob_dumps_are_named_by_path(self):
        # A restore needs to know which file a dump came from (which budget
        # group, which FreshRSS user), even when the glob matched only one.
        tmp = Path(tempfile.mkdtemp(dir='/tmp'))
        self.addCleanup(shutil.rmtree, tmp)
        tmp.chmod(0o755)
        root = copy_repo(tmp)
        data, repo, dumps = tmp / 'data', tmp / 'repo', tmp / 'dumps'
        sql = 'pragma journal_mode=wal; create table m(x); insert into m values ({});'
        files = {'actualbudget/server-files/account.sqlite': 1, 'actualbudget/user-files/group-abc.sqlite': 2,
                 'actualbudget/user-files/group-def.sqlite': 3, 'freshrss/data/users/alice/db.sqlite': 4}
        for rel, n in files.items():
            (data / rel).parent.mkdir(parents=True, exist_ok=True)
            subprocess.run(['sqlite3', str(data / rel), sql.format(n)], check=True, capture_output=True)
        (data / 'actualbudget/user-files/file-abc.blob').write_text('budget')
        (data / 'freshrss/extensions').mkdir(parents=True)
        (root / '.env').write_text(f'NODE_IP=192.168.1.11\nDATA_DIR={data}\n')
        node = root / 'nodes/percolator'
        node.joinpath('node.conf').write_text('APPS=(actualbudget freshrss)\n')
        (node / '.env.local').write_text(f'BACKUP_REPOSITORY={repo}\nDUMP_DIR={dumps}\nDUMP_STORE_HOST=192.168.1.11\n')
        (app('restic', root) / 'secrets.env.local').write_text('RESTIC_PASSWORD=test\n')
        env = dict(os.environ, BACKUP_KEY=str(tmp / 'key'), BACKUP_ETC=str(tmp / 'etc'),
                   BACKUP_CACHE=str(tmp / 'cache'), BACKUP_LOCK=str(tmp / 'lock'), RESTIC_PASSWORD='test',
                   PATH=f"{fake_bin(tmp / 'bin')}:{os.environ['PATH']}")
        subprocess.run(['restic', '-q', '-r', str(repo), 'init'], env=env, check=True, capture_output=True)
        result = subprocess.run(['bash', str(node / 'backup.sh'), 'nightly'], env=env, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        made = sorted(p.relative_to(dumps / 'percolator').as_posix() for p in dumps.rglob('*.sql.gz'))
        self.assertEqual(made, [
            'actualbudget/account.sql.gz',
            'actualbudget/groups-actualbudget_user-files_group-abc.sqlite.sql.gz',
            'actualbudget/groups-actualbudget_user-files_group-def.sqlite.sql.gz',
            'freshrss/users-freshrss_data_users_alice_db.sqlite.sql.gz'])
        group = subprocess.run(['bash', '-c', f"gzip -dc {dumps}/percolator/actualbudget/groups-*group-def*"],
                               capture_output=True, text=True).stdout
        self.assertIn('INSERT INTO m VALUES(3);', group)
        listing = subprocess.run(['restic', '-r', str(repo), 'ls', 'latest', '--tag', 'files'],
                                 env=env, capture_output=True, text=True, check=True).stdout
        self.assertIn('file-abc.blob', listing)
        self.assertNotIn('group-abc.sqlite', listing)   # live databases: the dumps have them
        self.assertNotIn('db.sqlite', listing)


class RemoteAccess(unittest.TestCase):
    """Tailscale: the tailnet policy (tailscale/README.md). The step that joined a
    node to the tailnet was part of init/, now under deprecated/; its checks come
    back with whatever replaces it (docs/migration-plan.md, phase 1)."""

    # Built at runtime so this file never contains something that looks like a key.
    FAKE_KEY = 'tskey-' + 'auth-' + 'kExample1CNTRL-abc'

    def policy(self):
        text = (ROOT / 'tailscale' / 'policy.hujson').read_text()
        text = re.sub(r'(^|\s)//[^\n]*', r'\1', text)        # HuJSON comments
        text = re.sub(r',(\s*[}\]])', r'\1', text)           # and trailing commas
        return json.loads(text)

    def test_policy_gives_the_nodes_ssh_only_and_nothing_outbound(self):
        policy = self.policy()
        self.assertNotIn('acls', policy)   # grants only, so there's one place to read
        self.assertNotIn('ssh', policy)    # OpenSSH on the nodes, not Tailscale SSH
        for grant in policy['grants']:
            self.assertFalse([s for s in grant['src'] if s.startswith('tag:')], f'a tag may not start anything: {grant}')
            if 'tag:purrbrews-node' in grant['dst']:
                self.assertEqual(grant['ip'], ['tcp:22'], grant)
            self.assertNotIn('*', grant['dst'] + grant['ip'], grant)
        self.assertNotRegex((ROOT / 'tailscale' / 'policy.hujson').read_text(), r'[\w.+-]+@[\w-]+\.[\w.]+',
                            'no email addresses in a public repo')

    def test_no_auth_key_anywhere_in_the_repo(self):
        pattern = re.compile(r'tskey-[a-z]+-[A-Za-z0-9]')
        for file in ROOT.rglob('*'):
            if file.is_file() and '.git' not in file.parts and file.suffix not in ('.pyc', '.exe', '.onnx'):
                self.assertNotRegex(file.read_text(errors='ignore'), pattern, str(file.relative_to(ROOT)))

    def fleet(self):
        return dict(line.split('=', 1) for line in (STACKS / 'fleet.env').read_text().splitlines()
                    if re.match(r'^[A-Z_]+=', line))

    def test_web_and_dns_grants_name_exactly_the_traefik_hosts_and_pi_holes(self):
        fleet = self.fleet()
        web = {f'{v}/32' for k, v in fleet.items() if k.endswith('_LAN_IP')}   # the five nodes
        dns = {f"{fleet['DNS_PRIMARY']}/32", f"{fleet['DNS_SECONDARY']}/32"}
        lan_grants = [g for g in self.policy()['grants'] if any('/' in d for d in g['dst'])]
        self.assertEqual({frozenset(g['dst']): sorted(g['ip']) for g in lan_grants},
                         {frozenset(web): ['tcp:443'], frozenset(dns): ['tcp:53', 'udp:53']})



class FileAndDAVReplacement(unittest.TestCase):
    """Retirement, public-client boundaries and safe first-start invariants."""

    def test_retired_app_name_only_occurs_in_runbook(self):
        # Git's authored inputs include new files but exclude local credentials,
        # caches and preserved artifacts from other branches. Split the needle
        # so the guard does not introduce the retired name itself.
        needle = b'next' + b'cloud'
        names = subprocess.check_output(
            ['git', '-C', str(ROOT), 'ls-files', '-co', '--exclude-standard', '-z'])
        for name in set(names.decode().split('\0')):
            path = ROOT / name
            if not name or name == 'runbook.md' or name.startswith('deprecated/') or not path.is_file():
                continue
            self.assertNotIn(needle, name.lower().encode(), name)
            self.assertNotIn(needle, path.read_bytes().lower(), name)

    @unittest.skipUnless(yaml, 'needs PyYAML')
    def test_public_clients_keep_pkce_and_bot_deny_precedence(self):
        config = yaml.safe_load((app('authelia') / 'config/configuration.yml.template').read_text())
        oidc = config['identity_providers']['oidc']
        clients = [c for c in oidc['clients'] if c['client_id'].startswith('opencloud')]
        self.assertEqual({c['client_id'] for c in clients},
                         {'opencloud', 'opencloud-ios', 'opencloud-desktop', 'opencloud-android'})
        for client in clients:
            self.assertTrue(client['public'])
            self.assertNotIn('client_secret', client)
            self.assertTrue(client['require_pkce'])
            self.assertEqual(client['pkce_challenge_method'], 'S256')
            self.assertEqual(client['token_endpoint_auth_method'], 'none')
            self.assertEqual(client['authorization_policy'], 'opencloud')
            self.assertEqual(set(client['grant_types']), {'authorization_code', 'refresh_token'})
        policies = oidc['authorization_policies']
        deny = policies['household']['rules'][0]
        self.assertEqual(deny, {'policy': 'deny', 'subject': ['group:opencloud_bot_accounts']})
        self.assertEqual(policies['opencloud']['default_policy'], 'deny')
        self.assertEqual(policies['opencloud']['rules'][1]['policy'], '${AUTH_POLICY}')
        mapping = yaml.safe_load((app('opencloud') / 'config/proxy.yaml.template').read_text())
        self.assertEqual(mapping['role_assignment']['oidc_role_mapper']['role_mapping'], [
            {'role_name': 'admin', 'claim_value': '${LLDAP_ADMIN_GROUP}'},
            {'role_name': 'user', 'claim_value': '${LLDAP_HOUSEHOLD_GROUP}'}])

    def test_raw_http_health_checks_speak_http_1_1(self):
        # Chrome's DevTools server rejects HTTP/1.0, so a raw 1.0 probe marks a
        # working browser unhealthy and blocks everything that depends on it.
        for path in STACKS.glob('*/*/docker-compose.yml'):
            for name, service in (yaml.safe_load(path.read_text()) or {}).get('services', {}).items():
                test = ' '.join((service.get('healthcheck') or {}).get('test') or [])
                if '/dev/tcp/' in test:
                    self.assertNotIn('HTTP/1.0', test, f'{path}: {name}')
                    self.assertIn('Connection: close', test, f'{path}: {name}')

    def test_ipv4_only_listeners_are_health_checked_on_ipv4(self):
        # localhost is ::1 first inside containers; an app bound to 0.0.0.0
        # refuses it, and the health check fails on a working service.
        for path in STACKS.glob('*/*/docker-compose.yml'):
            for name, service in (yaml.safe_load(path.read_text()) or {}).get('services', {}).items():
                env = service.get('environment') or {}
                ipv4_only = (isinstance(env, dict) and env.get('N8N_LISTEN_ADDRESS') == '0.0.0.0'
                             or 'fittrackee/fittrackee' in str(service.get('image', '')))  # gunicorn on 0.0.0.0
                if ipv4_only:
                    test = ' '.join(service['healthcheck']['test'])
                    self.assertNotIn('localhost', test, f'{path}: {name}')
                    self.assertIn('127.0.0.1', test, f'{path}: {name}')

    def test_tunnel_nodes_trust_only_sieves_forwarded_headers(self):
        # cloudflared on sieve fronts these Traefiks; without this every
        # tunnel visitor reaches the apps (and CrowdSec) as sieve.
        for name in ('traefik-ingress', 'traefik'):
            cfg = yaml.safe_load((app(name) / 'config/traefik.yml.template').read_text())
            trusted = cfg['entryPoints']['websecure']['forwardedHeaders']['trustedIPs']
            self.assertEqual(trusted, ['${SIEVE_LAN_IP}/32'], name)

    def test_dav_reader_is_separate_and_household_scoped(self):
        import configparser
        cfg = configparser.ConfigParser(interpolation=None)
        cfg.read(app('radicale') / 'config/config.template')
        auth = cfg['auth']
        self.assertEqual(auth['type'], 'ldap')
        self.assertTrue(auth['ldap_reader_dn'].startswith('uid=scottishfold,'))
        self.assertIn('(uid={0})', auth['ldap_filter'])
        self.assertIn('(memberOf=cn=${LLDAP_HOUSEHOLD_GROUP},ou=groups,${LDAP_BASE_DN})', auth['ldap_filter'])
        self.assertEqual(auth['ldap_user_attribute'], 'uid')
        self.assertNotIn('ldap_secret', auth)
        self.assertEqual(auth['ldap_secret_file'], '/run/secrets/ldap-password')
        self.assertGreaterEqual(float(auth['delay']), 1)
        self.assertEqual(cfg['rights']['type'], 'owner_only')

    def test_homeassistant_has_bluetooth_access(self):
        # Without raw HCI access HA runs its Bluetooth adapter in degraded mode.
        compose = yaml.safe_load((app('homeassistant') / 'docker-compose.yml').read_text())
        ha = compose['services']['homeassistant']
        self.assertEqual(ha['network_mode'], 'host')
        self.assertTrue({'NET_ADMIN', 'NET_RAW'} <= set(ha['cap_add']))
        self.assertIn('/run/dbus:/run/dbus:ro', ha['volumes'])

    def test_radicale_storage_parent_is_mounted(self):
        # The image's /data is radicale(2999) mode 770; running as PUID, a mount
        # of only /data/collections sits under a directory it can't traverse.
        compose = yaml.safe_load((app('radicale') / 'docker-compose.yml').read_text())
        volumes = compose['services']['radicale']['volumes']
        self.assertIn('${DATA_DIR}/radicale:/data', volumes)
        self.assertFalse([v for v in volumes if v.split(':')[1].startswith('/data/')])

    def test_initialization_never_replaces_existing_identity_state(self):
        source = (app('opencloud') / 'start.sh').read_text()
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            config_dir, data_dir = root / 'config', root / 'data'
            config_dir.mkdir()
            data_dir.mkdir()
            config = config_dir / 'opencloud.yaml'
            calls = root / 'calls'
            binary = root / 'opencloud'
            binary.write_text('#!/bin/sh\n'
                              'echo "$1" >> "$CALLS"\n'
                              'if [ "$1" = init ]; then\n'
                              '  [ "${FAIL_INIT:-0}" = 0 ] || exit 23\n'
                              '  echo preserved-identity > "$CONFIG"\n'
                              'fi\n')
            binary.chmod(0o755)
            script = root / 'start.sh'
            script.write_text(source.replace('/etc/opencloud', str(config_dir))
                              .replace('/var/lib/opencloud', str(data_dir)))
            env = dict(os.environ, PATH=f"{root}:{os.environ['PATH']}",
                       CALLS=str(calls), CONFIG=str(config))

            def run(**extra):
                return subprocess.run(['sh', str(script)], env=dict(env, **extra),
                                      capture_output=True, text=True)

            self.assertEqual(run().returncode, 0)
            self.assertEqual(calls.read_text().splitlines(), ['init', 'server'])
            self.assertEqual(run().returncode, 0)
            self.assertEqual(calls.read_text().splitlines(), ['init', 'server', 'server'])
            self.assertEqual(config.read_text(), 'preserved-identity\n')
            config.unlink()
            (data_dir / 'existing').touch()
            self.assertNotEqual(run().returncode, 0)
            self.assertFalse(config.exists())
            config.touch()
            self.assertNotEqual(run().returncode, 0)
            self.assertEqual(calls.read_text().splitlines(), ['init', 'server', 'server'])
            config.unlink()
            (data_dir / 'existing').unlink()
            self.assertEqual(run(FAIL_INIT='1').returncode, 23)
            self.assertEqual(calls.read_text().splitlines(), ['init', 'server', 'server', 'init'])


class Tunnel(unittest.TestCase):
    """sieve's cloudflared routes: every app except the admin-only ones (config.yml.template)."""

    TEMPLATE = app('cloudflared') / 'config' / 'config.yml.template'
    # Not admin-only in Authelia, but kept off the internet anyway (reasons in the template).
    NOT_PUBLIC = {'lldap', 'n8n', 'esphome', 'speedtest'}

    def routed_hosts(self):
        names = set()
        for file in STACKS.rglob('*'):
            if file.is_file() and file.suffix in ('.yml', '.yaml', '.template') and '.git' not in file.parts:
                active = '\n'.join(l for l in file.read_text().splitlines() if not l.lstrip().startswith('#'))
                names |= set(re.findall(r'Host\(`([a-z0-9-]+)\.(?:\$\{DOMAIN\}|\{\{ env "DOMAIN" \}\})`\)', active))
        return names

    def admin_hosts(self):
        text = (app('authelia') / 'config' / 'configuration.yml.template').read_text()
        block = re.search(r'domain: &admin_hosts\n(.*?)\n\s+subject:', text, re.S).group(1)
        return set(re.findall(r"'([a-z0-9-]+)\.\$\{DOMAIN\}'", block))

    def ingress(self):
        text = self.TEMPLATE.read_text()
        active = '\n'.join(line for line in text.splitlines() if not line.lstrip().startswith('#'))
        return re.findall(r'- hostname: ([a-z0-9-]+)\.\$\{DOMAIN\}\n\s+service: (\S+)', active), active

    def test_every_non_admin_route_is_published_and_no_admin_one_is(self):
        rules, _ = self.ingress()
        published = [host for host, _ in rules]
        self.assertEqual(len(published), len(set(published)), 'a hostname is listed twice')
        self.assertEqual(set(published), self.routed_hosts() - self.admin_hosts() - self.NOT_PUBLIC)
        self.assertFalse(set(published) & self.admin_hosts())

    def test_traefik_routes_use_https_with_their_own_name_as_sni(self):
        rules, active = self.ingress()
        for host, service in rules:
            if host == 'ntfy':
                self.assertEqual(service, 'http://ntfy:8080')
                continue
            self.assertRegex(service, r'^https://\$\{[A-Z]+_LAN_IP\}:443$', host)
            self.assertIn(f'originRequest: {{originServerName: {host}.${{DOMAIN}}}}', active)
        self.assertRegex(active.rstrip(), r'- service: http_status:404$', 'the last rule must be the 404 catch-all')
        self.assertNotIn('noTLSVerify', active)

    def test_renders_on_sieve_with_existing_settings_only(self):
        text = self.TEMPLATE.read_text()
        self.assertTrue(text.startswith('# render-mode: 0644\n'), 'cloudflared runs as non-root and must read it')
        active = '\n'.join(line for line in text.splitlines() if not line.lstrip().startswith('#'))
        needed = {a or b for a, b in renderer.VARIABLE.findall(active)}
        fleet = set(re.findall(r'(?m)^([A-Z_]+)=', (STACKS / 'fleet.env').read_text()))
        sieve = set(re.findall(r'(?m)^([A-Z_]+)=', (NODE_DIRS / 'sieve' / 'local.env.example').read_text()))
        self.assertEqual(needed - fleet - sieve, set(), 'a new setting would break the next render on sieve')


class AppsNeedTheRelayBundle(unittest.TestCase):
    """Without mail-relay's bundle, SSL_CERT_FILE points at nothing and SSO breaks."""

    def test_every_app_on_the_bundle_has_the_guard(self):
        users = sorted(p.parent.name for p in STACKS.glob('*/*/docker-compose.yml')
                       if 'SSL_CERT_FILE: /etc/purrbrews/bundle.crt' in p.read_text(encoding='utf-8'))
        self.assertEqual(users, ['paperless', 'vaultwarden', 'vikunja'])
        for name in users:
            prepare = app(name) / 'prepare.sh'
            self.assertIn('mail/mail-relay/require-bundle.sh', prepare.read_text(encoding='utf-8'), name)

    def test_prepare_refuses_until_the_bundle_exists(self):
        for name in ('vaultwarden', 'paperless', 'vikunja'):
            with self.subTest(app=name), tempfile.TemporaryDirectory() as tmp:
                root = Path(tmp)
                fake = root / 'bin'
                fake.mkdir()
                (fake / 'sudo').write_text('#!/bin/sh\nexec "$@"\n')
                (fake / 'sudo').chmod(0o755)
                env = dict(os.environ, PATH=f'{fake}{os.pathsep}{os.environ["PATH"]}')
                script = app(name) / 'prepare.sh'

                def prepare():
                    return subprocess.run(['bash', str(script), str(root / 'data')], env=env,
                                          capture_output=True, text=True)

                refused = prepare()
                self.assertNotEqual(refused.returncode, 0)
                self.assertIn(f'{name}/prepare.sh:', refused.stderr)
                self.assertIn('mail-relay up -d first', refused.stderr)
                bundle = root / 'data/mail-relay/tls-public/bundle.crt'
                bundle.parent.mkdir(parents=True)
                bundle.write_text('certificates\n')
                self.assertEqual(prepare().returncode, 0)


class UpgradeGates(unittest.TestCase):
    """Images that migrate their data one way wait for the owner's go-ahead."""

    CASES = [  # app, data that exists once it has run, key, what to acknowledge
        ('opencloud', 'opencloud/config/opencloud.yaml', 'OPENCLOUD_UPGRADE_READY', r'\d+'),
        ('karakeep', 'karakeep-meilisearch/data.ms', 'KARAKEEP_SEARCH_UPGRADE_READY', r'\d+\.\d+\.\d+'),
        ('traccar', 'traccar/data/database.mv.db', 'TRACCAR_UPGRADE_READY', r'\d+\.\d+'),
        ('openwebui', 'openwebui/webui.db', 'OPENWEBUI_UPGRADE_READY', r'\d+\.\d+\.\d+'),
    ]

    def test_existing_data_waits_for_the_pinned_version(self):
        for name, marker, key, shape in self.CASES:
            with self.subTest(app=name), tempfile.TemporaryDirectory() as tmp:
                root = Path(tmp)
                shutil.copytree(STACKS / '_lib', root / 'stacks/_lib')
                app_dir = root / 'stacks' / app(name).parent.name / name
                shutil.copytree(app(name), app_dir)
                node = root / 'nodes/test'
                node.mkdir(parents=True)
                (node / 'node.conf').write_text(f'APPS=({name})\n')
                fake = root / 'bin'
                fake.mkdir()
                (fake / 'sudo').write_text('#!/bin/sh\nexec "$@"\n')
                (fake / 'sudo').chmod(0o755)
                # compose.sh exports the node's folder for an app's own scripts.
                env = dict(os.environ, PATH=f'{fake}{os.pathsep}{os.environ["PATH"]}', PURRBREWS_NODE_DIR=str(node))
                data = root / 'data'

                def prepare():
                    return subprocess.run(['bash', str(app_dir / 'prepare.sh'), str(data)],
                                          env=env, capture_output=True, text=True)

                record = (data / marker).parent / f'.upgrade-gate-{key}'
                (data / marker).parent.mkdir(parents=True)   # data-dirs runs before prepare.sh
                self.assertEqual(prepare().returncode, 0, 'a fresh install has nothing to migrate')
                self.assertTrue(record.exists(), 'a fresh install records its version')
                (data / marker).touch()
                self.assertEqual(prepare().returncode, 0, 'a redeploy of the recorded version needs no key')

                record.unlink()   # data from before the record existed
                refused = prepare()
                self.assertNotEqual(refused.returncode, 0)
                version = re.search(rf'{key}=(\S+) in', refused.stderr).group(1)
                self.assertRegex(version, rf'^{shape}$')
                (node / '.env.local').write_text(f'{key}=0.0.1\n')
                self.assertNotEqual(prepare().returncode, 0, 'an older acknowledgement is not this one')
                (node / '.env.local').write_text(f'{key}={version}\n')
                self.assertEqual(prepare().returncode, 0, prepare().stderr)
                self.assertEqual(record.read_text().strip(), version, 'an acknowledged start is recorded')
                (node / '.env.local').write_text('')
                self.assertEqual(prepare().returncode, 0, 'the record carries it once the key is gone')

                record.write_text('0.0.1\n')   # data on an older version
                self.assertNotEqual(prepare().returncode, 0, 'an older record still waits for the key')
                (node / '.env.local').write_text(f'{key}={version}\n')

                if name == 'opencloud':
                    compose = app_dir / 'docker-compose.yml'
                    original = compose.read_text()
                    image = re.search(r'image: (opencloudeu/opencloud):(\d+)\.(\d+)\.(\d+)', original)
                    self.assertIsNotNone(image)
                    repository, major, minor, patch = image.groups()
                    same_major = f'image: {repository}:{major}.{minor}.{int(patch) + 1}'
                    compose.write_text(original.replace(image.group(0), same_major))
                    self.assertEqual(prepare().returncode, 0, 'patch retains major acknowledgement')
                    new_major = f'image: {repository}:{int(major) + 1}.0.0'
                    compose.write_text(original.replace(image.group(0), new_major))
                    self.assertNotEqual(prepare().returncode, 0, 'a later major closes the gate again')


if __name__ == '__main__':
    unittest.main()
