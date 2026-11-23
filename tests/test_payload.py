"""payload/: what purrbrews-bootstrap runs on a new machine to make it a node,
and scripts/fleet-macs.sh, which shares its fleet list with the Pi-holes."""
import hashlib
import importlib.util
import io
import json
import os
from pathlib import Path
import pwd
import re
import shutil
import socket
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
PAYLOAD = ROOT / 'payload'
NODES = ['sieve', 'percolator', 'cellar', 'mochaPot', 'grinder']


def derived(name):
    h = hashlib.sha256(f'purrbrews:{name.lower()}'.encode()).hexdigest()[:10]
    return '02:' + ':'.join(h[i:i + 2] for i in range(0, 10, 2))


def fleet_env():
    return dict(line.split('=', 1) for line in (ROOT / 'stacks/fleet.env').read_text().splitlines()
                if re.match(r'^[A-Z_]+=', line))


def copy_repo(tmp):
    """The parts the fleet list reads: nodes/, stacks/fleet.env, payload/, scripts/."""
    root = Path(tmp) / 'repo'
    for part in ['nodes', 'payload', 'scripts']:
        shutil.copytree(ROOT / part, root / part, ignore=shutil.ignore_patterns('*.env.local', '__pycache__'))
    (root / 'stacks').mkdir()
    shutil.copy(ROOT / 'stacks/fleet.env', root / 'stacks/fleet.env')
    return root


def macs(root=ROOT):
    return subprocess.run(['bash', str(root / 'scripts/fleet-macs.sh'), '--format', 'csv'],
                          capture_output=True, text=True)


class FleetList(unittest.TestCase):
    def test_every_node_with_its_address_and_name_derived_mac(self):
        result = macs()
        self.assertEqual(result.returncode, 0, result.stderr)
        rows = [line.split(',') for line in result.stdout.splitlines()[1:]]
        fleet = fleet_env()
        self.assertEqual([r[0] for r in rows], NODES)  # in address order
        for name, ip, mac in rows:
            self.assertEqual(ip, fleet[f'{name.upper()}_LAN_IP'], name)
            self.assertEqual(mac, derived(name), name)
            self.assertEqual(int(mac[:2], 16) & 3, 2, 'locally administered, unicast')
        # The same MACs the fleet had before the rebuild (deprecated/README.md),
        # so the router and Pi-hole see the same devices.
        self.assertIn(['sieve', '192.168.1.10', '02:33:68:72:0b:17'], rows)
        self.assertIn(['grinder', '192.168.1.14', '02:93:3c:b4:86:e8'], rows)

    def test_overrides_and_broken_lists(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = copy_repo(tmp)
            settings = root / 'payload/payload.env'
            original = settings.read_text()
            settings.write_text(original.replace('NODE_MACS=\n', 'NODE_MACS=cellar=AA-BB-CC-DD-EE-02\n'))
            out = macs(root)
            self.assertEqual(out.returncode, 0, out.stderr)
            self.assertIn('cellar,192.168.1.12,aa:bb:cc:dd:ee:02', out.stdout)
            for bad in ['cellar=01:00:00:00:00:00', 'cellar=nonsense', f'cellar={derived("sieve")}']:
                with self.subTest(override=bad):
                    settings.write_text(original.replace('NODE_MACS=\n', f'NODE_MACS={bad}\n'))
                    self.assertNotEqual(macs(root).returncode, 0)
            settings.write_text(original)
            fleet = root / 'stacks/fleet.env'
            text = fleet.read_text()
            for broken in [text.replace('GRINDER_LAN_IP=192.168.1.14', 'GRINDER_LAN_IP=192.168.1.13'),
                           text.replace('GRINDER_LAN_IP=192.168.1.14\n', ''),
                           text.replace('GRINDER_LAN_IP=192.168.1.14', 'GRINDER_LAN_IP=192.168.1.300')]:
                with self.subTest(fleet=broken[-60:]):
                    fleet.write_text(broken)
                    self.assertNotEqual(macs(root).returncode, 0, 'a broken list never becomes empty records')

    def test_pi_hole_records_come_from_this_list(self):
        refresh = (ROOT / 'stacks/_lib/refresh-dns.sh').read_text()
        self.assertIn('scripts/fleet-macs.sh', refresh)
        self.assertNotIn('init/', refresh)
        spec = importlib.util.spec_from_file_location('dns', ROOT / 'stacks/_lib/dns-records.py')
        dns = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(dns)
        lines, hosts = dns.records(ROOT, 'example.test', io.StringIO(macs().stdout))
        self.assertIn('address=/authelia.example.test/192.168.1.11', lines)
        self.assertEqual(len(hosts), 5)
        leases = dns.dhcp_hosts(macs().stdout)
        self.assertIn('02:33:68:72:0b:17,192.168.1.10,sieve', leases)

    def test_no_live_code_calls_the_archive(self):
        for top in ['stacks', 'nodes', 'scripts', 'payload']:
            for file in (ROOT / top).rglob('*'):
                if file.suffix in ('.sh', '.py', '.service', '.timer', '.hook') and file.is_file():
                    text = file.read_text()
                    self.assertNotRegex(text, r'\$ROOT/init/|deprecated/init/.*\.sh"', str(file.relative_to(ROOT)))


class Payload(unittest.TestCase):
    SCRIPT = PAYLOAD / 'purrbrews-node.sh'

    def test_settings_are_public_and_clone_anonymously(self):
        text = (PAYLOAD / 'payload.env').read_text()
        url = re.search(r'(?m)^REPO_URL=(.*)$', text).group(1)
        self.assertTrue(url.startswith('https://'))
        self.assertNotIn('@', url)
        values = '\n'.join(l for l in text.splitlines() if not l.lstrip().startswith('#'))
        self.assertNotRegex(values, r'(?i)hc-ping|healthchecks\.io/|token|password|tskey-')

    def test_root_runs_only_payload_files(self):
        # The checkout is the ops user's to write; root must not execute from it.
        source = self.SCRIPT.read_text()
        self.assertNotRegex(source, r'(source|\.|bash|sh)\s+"?\$PROJECT_DIR')
        self.assertIn('install -m 755 "$HERE/lib/purrbrews-pull.sh"', source)
        self.assertIn('install -m 755 "$HERE/lib/net-apply.sh"', source)

    def test_network_is_last_and_asks(self):
        source = self.SCRIPT.read_text()
        steps = re.search(r'^ALL_STEPS=\((.*)\)', source, re.M).group(1).split()
        self.assertEqual(steps[-1], 'network')
        self.assertEqual(steps[:3], ['packages', 'repo', 'node'])
        body = re.search(r'^step_network\(\) \{.*?^\}', source, re.M | re.S).group(0)
        self.assertIn('confirm ', body)
        self.assertIn('systemd-run', body)          # detached, so a dropped SSH can't stop it
        self.assertIn('--on-active=5', body)
        self.assertIn('net-apply.sh', body)
        self.assertLess(body.index('confirm '), body.index('nmcli connection add'))

    def test_list_steps_and_unknown_options(self):
        out = subprocess.run(['bash', str(self.SCRIPT), '--list-steps'], capture_output=True, text=True)
        self.assertEqual(out.stdout.split(), ['packages', 'repo', 'node', 'folders', 'hosts', 'timers', 'tailnet', 'network'])
        bad = subprocess.run(['bash', str(self.SCRIPT), '--only', 'nope'], capture_output=True, text=True)
        self.assertNotEqual(bad.returncode, 0)

    @unittest.skipUnless(os.geteuid() == 0 and shutil.which('runuser') and shutil.which('git'),
                         'needs root, runuser and git')
    def test_repo_node_folders_hosts_as_root(self):
        user = next((p for p in pwd.getpwall() if p.pw_uid >= 1000 and p.pw_name != 'nobody'), None)
        if user is None:
            self.skipTest('needs an unprivileged user to act as the ops user')
        with tempfile.TemporaryDirectory(dir='/tmp') as tmp:
            tmp = Path(tmp)
            os.chmod(tmp, 0o755)
            project, data, media = tmp / 'opt', tmp / 'srv/data', tmp / 'srv/media'
            # An existing checkout: the repo step only fetches (and warns when it can't).
            shutil.copytree(ROOT / 'nodes', project / 'nodes', ignore=shutil.ignore_patterns('*.env.local'))
            (project / 'stacks').mkdir()
            shutil.copy(ROOT / 'stacks/fleet.env', project / 'stacks/fleet.env')
            git = ['git', '-c', 'user.name=t', '-c', 'user.email=t@example.test', '-C', str(project)]
            subprocess.run(['git', 'init', '-q', str(project)], check=True)
            subprocess.run(git + ['add', '-A'], check=True)
            subprocess.run(git + ['commit', '-qm', 'fixture'], check=True)
            subprocess.run(git + ['remote', 'add', 'origin', 'https://github.com/purrMonster/purrbrews-containers.git'], check=True)
            subprocess.run(['chown', '-R', f'{user.pw_name}:', str(project)], check=True)
            payload = tmp / 'payload'
            shutil.copytree(PAYLOAD, payload)
            settings = (PAYLOAD / 'payload.env').read_text()
            settings = (settings.replace('PROJECT_DIR=/opt/purrbrews', f'PROJECT_DIR={project}')
                        .replace('DATA_DIR=/srv/data', f'DATA_DIR={data}')
                        .replace('MEDIA_DIR=/srv/media', f'MEDIA_DIR={media}'))
            (payload / 'payload.env').write_text(settings)
            hosts = tmp / 'hosts'
            hosts.write_text('127.0.0.1\tlocalhost\n127.0.1.1\tdebian\n')  # as the installer leaves it
            env = dict(os.environ, PB_ETC_DIR=str(tmp / 'etc'), PB_HOSTS_FILE=str(hosts),
                       PB_LOG_DIR=str(tmp / 'log'), PB_LIB_DST=str(tmp / 'lib'), PB_UNIT_DIR=str(tmp / 'units'),
                       GIT_CONFIG_SYSTEM=str(tmp / 'gitconfig'), GIT_TERMINAL_PROMPT='0')
            command = ['bash', str(payload / 'purrbrews-node.sh'), 'GRINDER', '--user', user.pw_name,
                       '--only', 'repo node folders hosts']
            for _ in range(2):  # and once more: every step is safe to repeat
                result = subprocess.run(command, env=env, capture_output=True, text=True, stdin=subprocess.DEVNULL)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            node_env = (project / '.env').read_text()
            self.assertIn('NODE=grinder\n', node_env)          # the nodes/ spelling, whatever was typed
            self.assertIn('NODE_IP=192.168.1.14\n', node_env)
            self.assertIn(f'PUID={user.pw_uid}\n', node_env)
            self.assertIn(f'DATA_DIR={data}\n', node_env)
            self.assertIn('TZ=Asia/Kolkata\n', node_env)
            self.assertEqual(os.stat(data).st_uid, user.pw_uid)
            text = hosts.read_text()
            self.assertTrue(text.startswith('127.0.0.1\tlocalhost\n'))
            self.assertEqual(text.count('>>> purrbrews fleet'), 1)
            self.assertIn('192.168.1.10\tsieve\n', text)
            self.assertIn('192.168.1.13\tmochaPot\n', text)
            self.assertNotIn('\tgrinder\n', text)             # its own name isn't in the block
            self.assertNotIn('debian', text)                  # the install-time name is gone
            self.assertEqual(text.count('127.0.1.1\t'), 1)    # and 127.0.1.1 names this machine, once
            self.assertIn(f'127.0.1.1\t{socket.gethostname()}\n', text)
            unknown = subprocess.run(['bash', str(payload / 'purrbrews-node.sh'), 'roastery', '--user', user.pw_name,
                                      '--only', 'node'], env=env, capture_output=True, text=True,
                                     stdin=subprocess.DEVNULL)
            self.assertNotEqual(unknown.returncode, 0)
            self.assertIn("No node 'roastery'", unknown.stderr)


    def test_tailnet_only_runs_when_named(self):
        source = self.SCRIPT.read_text()
        self.assertRegex(source, r'(?m)^OPT_IN_STEPS=\(tailnet\)$')
        body = re.search(r'^step_tailnet\(\) \{.*?^\}', source, re.M | re.S).group(0)
        for flag in ['--netfilter-mode=off', '--accept-dns=false', '--ssh=false', '--reset']:
            self.assertIn(flag, body)
        settings = (PAYLOAD / 'payload.env').read_text()
        self.assertIn('TAILSCALE_ROUTES=192.168.0.0/23\n', settings)   # a /23 on its boundary

    def test_the_tailnet_route_holds_the_lan_and_the_policy_approves_it(self):
        import ipaddress
        settings = (PAYLOAD / 'payload.env').read_text()
        routes = re.search(r'(?m)^TAILSCALE_ROUTES=(\S+)$', settings).group(1).split(',')
        lan = ipaddress.ip_network(fleet_env()['LAN_CIDR'])
        nets = [ipaddress.ip_network(r) for r in routes]    # strict: a /23 on its boundary
        self.assertTrue(any(lan.subnet_of(n) and n.prefixlen < lan.prefixlen for n in nets),
                        'a route wider than the LAN, so the LAN wins at home')
        policy = (ROOT / 'tailscale/policy.hujson').read_text()
        policy = re.sub(r'(?m)^\s*//.*$', '', policy)
        policy = re.sub(r',(\s*[}\]])', r'\1', policy)
        data = json.loads(policy)
        self.assertEqual(sorted(data['autoApprovers']['routes']), sorted(routes))
        self.assertNotIn('3389', json.dumps(data), 'Remote Desktop was for roastery')
        routers = re.search(r'(?m)^TAILSCALE_SUBNET_ROUTERS=(.*)$', settings).group(1).split()
        self.assertTrue(set(routers) <= {n.name for n in (ROOT / 'nodes').iterdir()})

    @unittest.skipUnless(os.geteuid() == 0, 'needs root')
    def test_tailnet_step_with_stand_in_commands(self):
        user = next((p for p in pwd.getpwall() if p.pw_uid >= 1000 and p.pw_name != 'nobody'), None)
        if user is None:
            self.skipTest('needs an unprivileged user to act as the ops user')
        stub = """#!/bin/bash
printf '%s %s\\n' "$(basename "$0")" "$*" >> "$STUB_LOG"
case "$(basename "$0") $1" in
  'tailscale status') printf '{\\n  "BackendState": "NeedsLogin",\\n}\\n' ;;
  'tailscale ip') echo 100.64.0.7 ;;
  'ip -4') echo 'default via 192.168.1.1 dev enp1s0 proto static' ;;
esac
exit 0
"""
        def run(node, keyfile):
            tmp = Path(tempfile.mkdtemp(dir='/tmp'))
            self.addCleanup(shutil.rmtree, tmp)
            project = tmp / 'opt'
            shutil.copytree(ROOT / 'nodes', project / 'nodes', ignore=shutil.ignore_patterns('*.env.local'))
            (project / 'stacks').mkdir()
            shutil.copy(ROOT / 'stacks/fleet.env', project / 'stacks/fleet.env')
            payload = tmp / 'payload'
            shutil.copytree(PAYLOAD, payload)
            settings = (PAYLOAD / 'payload.env').read_text().replace('PROJECT_DIR=/opt/purrbrews', f'PROJECT_DIR={project}')
            (payload / 'payload.env').write_text(settings)
            bin_ = tmp / 'bin'
            bin_.mkdir()
            for name in ['tailscale', 'ufw', 'systemctl', 'sysctl', 'iptables', 'ip', 'apt-get', 'curl']:
                (bin_ / name).write_text(stub)
                (bin_ / name).chmod(0o755)
            etc, units, sysctl = tmp / 'etc', tmp / 'units', tmp / 'sysctl'
            for d in (etc, units, sysctl):
                d.mkdir()
            if keyfile:
                (etc / 'tailscale-authkey').write_text('stand-in-auth-key\n')
                (etc / 'tailscale-authkey').chmod(0o600)
            log = tmp / 'log'
            env = dict(os.environ, PATH=f'{bin_}:{os.environ["PATH"]}', STUB_LOG=str(log),
                       PB_ETC_DIR=str(etc), PB_UNIT_DIR=str(units), PB_SYSCTL_DIR=str(sysctl),
                       PB_LOG_DIR=str(tmp / 'logs'))
            result = subprocess.run(['bash', str(payload / 'purrbrews-node.sh'), node, '--user', user.pw_name,
                                     '--only', 'tailnet'], env=env, capture_output=True, text=True,
                                    stdin=subprocess.DEVNULL, start_new_session=True)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            return log.read_text() if log.exists() else '', etc, units, sysctl, result

        calls, etc, units, sysctl, _ = run('grinder', keyfile=True)
        self.assertIn('ufw allow in on tailscale0 to any port 22 proto tcp', calls)
        self.assertIn('ufw allow 41641/udp', calls)
        self.assertIn('ufw route allow in on tailscale0 proto tcp to any port 443', calls)
        self.assertIn('out on enp1s0 proto udp to 192.168.1.0/24 port 53', calls)
        up = next(l for l in calls.splitlines() if l.startswith('tailscale up'))
        for arg in ['--hostname=grinder', '--netfilter-mode=off', '--accept-dns=false', '--ssh=false',
                    '--advertise-tags=tag:purrbrews-node', '--advertise-routes=192.168.0.0/23',
                    f'--auth-key=file:{etc}/tailscale-authkey']:
            self.assertIn(arg, up.split())
        self.assertNotIn('stand-in-auth-key', calls, 'the key goes by file, never on the command line')
        self.assertFalse((etc / 'tailscale-authkey').exists(), 'the auth key is deleted once used')
        self.assertIn('MASQUERADE', (units / 'purrbrews-tailscale-nat.service').read_text())
        self.assertIn('net.ipv4.ip_forward = 1', (sysctl / '99-purrbrews-tailscale.conf').read_text())
        self.assertNotIn('apt-get', calls, 'already installed: nothing to install')

        calls, _, units, _, _ = run('sieve', keyfile=True)
        up = next(l for l in calls.splitlines() if l.startswith('tailscale up'))
        self.assertIn('--advertise-routes=', up.split())
        self.assertNotIn('route allow', calls)
        self.assertFalse((units / 'purrbrews-tailscale-nat.service').exists())

        calls, _, _, _, result = run('sieve', keyfile=False)   # no key and no terminal
        self.assertNotIn('tailscale up', calls)
        self.assertIn('Not signed in', result.stderr)

if __name__ == '__main__':
    unittest.main()
