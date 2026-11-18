"""The recovery kit (recovery/, docs/recovery-kit.md): its lists agree with the
fleet, fill-vault.sh never shows a value, and make-flask.sh's stick check
catches a changed file."""
import os
import re
import stat
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
KIT = ROOT / 'recovery'
DOC = ROOT / 'docs' / 'recovery-kit.md'


def tiers():
    rows = []
    for line in (KIT / 'vault.tiers').read_text().splitlines():
        if line.strip() and not line.startswith('#'):
            tier, name, *flag = line.split()
            rows.append((tier, name, flag[0] if flag else ''))
    return rows


def secret_names():
    names = set()
    for conf in (ROOT / 'stacks').rglob('secrets*.conf'):
        for line in conf.read_text().splitlines():
            m = re.match(r'([A-Z][A-Z0-9_]+)\s', line)
            if m:
                names.add(m.group(1))
    return names


class Lists(unittest.TestCase):
    def test_every_vault_secret_still_exists_in_some_app(self):
        known = secret_names()
        for _, name, _ in tiers():
            self.assertIn(name, known, f'{name}: in vault.tiers but in no secrets*.conf')

    def test_the_doc_and_the_list_agree(self):
        text = DOC.read_text()
        section = text[text.index('**Tier 1'):text.index('**Outside the repo**')]
        in_doc = {n for n in re.findall(r'`([A-Z][A-Z0-9_]{3,})`', section)
                  if n != 'OPENCLOUD_THUMBNAILS_TRANSFER_TOKEN'}   # named only as dropped
        self.assertEqual(in_doc, {name for _, name, _ in tiers()})
        for tier, name, _ in tiers():
            block = section[section.index(f'**Tier {tier}'):]
            nxt = re.search(r'\n\*\*Tier \d', block[1:])
            block = block[:nxt.start() + 1] if nxt else block
            self.assertIn(f'`{name}`', block, f'{name} is in the doc, but not under Tier {tier}')

    def test_tiers_are_one_to_four_and_flags_known(self):
        for tier, name, flag in tiers():
            self.assertIn(tier, '1234')
            self.assertIn(flag, ('', 'per-node'), name)

    def test_scripts_stay_within_bash_3_2(self):
        # americano runs them with macOS's own /bin/bash, which is 3.2.
        banned = [r'declare -A', r'\bmapfile\b', r'\breadarray\b', r'\$\{[^}]*,,\}', r'\$\{[^}]*\^\^\}',
                  r'\|&', r'&>>', r'\bcoproc\b', r'local -n', r'\[\[ -v ']
        for script in ['make-flask.sh', 'fill-vault.sh']:
            text = (KIT / script).read_text()
            self.assertTrue(text.startswith('#!/bin/bash\n'), script)
            for pattern in banned:
                self.assertIsNone(re.search(pattern, text), f'{script}: {pattern} needs bash 4')

    def test_live_files_keep_their_modes(self):
        for rel in ['usr/local/sbin/mount-flask', 'usr/local/bin/flask-keepassxc',
                    'usr/local/bin/restic', 'usr/local/bin/rclone']:
            mode = (KIT / 'live' / rel).stat().st_mode
            self.assertTrue(mode & stat.S_IXUSR, rel)
        for path in (KIT / 'live').rglob('*'):
            if path.is_file():
                self.assertNotIn(b'\r\n', path.read_bytes(), path)
                self.assertNotIn('ps1', path.read_text(), path)

    def test_nothing_live_points_at_the_old_kit(self):
        for path in [*KIT.rglob('*'), DOC]:
            if path.is_file():
                text = path.read_text(errors='replace')
                for old in ['make-flask.ps1', 'fill-vault.ps1', 'stacks/roastery/flask', 'docs/flask.md']:
                    if old in text:
                        # Only as history: "replaces ..." or "was built ... (deprecated/...)".
                        for line in text.splitlines():
                            if old in line:
                                self.assertRegex(line, r'replaces|deprecated|old', f'{path}: {line}')


FAKE_CLI = r'''#!/bin/bash
# A stand-in for keepassxc-cli: entries are files under $KPX_STORE, the
# master password is "pw". Records each argv, never stdin, in $KPX_STORE/argv.
set -u
store="$KPX_STORE"; mkdir -p "$store/e"
printf '%s\n' "$*" >> "$store/argv"
IFS= read -r master || true
[[ "$master" == pw ]] || exit 1
cmd="$1"; shift
args=(); for a in "$@"; do case "$a" in -q|-p|-s) ;; *) args+=("$a") ;; esac; done
key() { printf '%s' "$1" | od -An -tx1 | tr -d ' \n'; }
case "$cmd" in
  ls|mkdir) exit 0 ;;
  show) f="$store/e/$(key "${args[3]}")"; [[ -f "$f" ]] || exit 1; cat "$f"; echo ;;
  add) if [[ "${args[0]}" == --notes ]]; then path="${args[3]}"; else path="${args[1]}"; fi
       IFS= read -r v; printf '%s' "$v" > "$store/e/$(key "$path")"; printf '%s\n' "$path" >> "$store/added" ;;
  edit) path="${args[1]}"; IFS= read -r v; printf '%s' "$v" > "$store/e/$(key "$path")" ;;
  *) exit 2 ;;
esac
'''


class FillVault(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.addCleanup(subprocess.run, ['rm', '-rf', str(self.tmp)])
        s = self.tmp / 'secrets'
        s.mkdir()
        p = '/opt/purrbrews/stacks'
        (s / 'cellar.txt').write_text(
            f'{p}/backup/restic/secrets.env.local:RESTIC_PASSWORD=v4lue-restic\n'
            f'{p}/backup/restic/secrets.env.local:RCLONE_CRYPT_PASSWORD="v4lue-crypt"\n'
            f'{p}/network/traefik/secrets.env.local:CF_DNS_API_TOKEN=v4lue-cf-cellar\n'
            f'{p}/fleet-management/komodo/secrets.env.local:KOMODO_JWT_SECRET=REPLACE_ME\n')
        (s / 'sieve.txt').write_text(
            f'{p}/backup/restic/secrets.env.local:RESTIC_PASSWORD=v4lue-restic\n'
            f'{p}/network/traefik-edge/secrets.env.local:CF_DNS_API_TOKEN=v4lue-cf-sieve\n')
        (s / 'grinder.txt').write_text(
            f'{p}/backup/restic/secrets.env.local:RESTIC_PASSWORD=v4lue-different\n')
        self.env = dict(os.environ, FLASK_TEST_SECRETS_DIR=str(s))

    def run_fill(self, *args, env=None):
        return subprocess.run(['bash', str(KIT / 'fill-vault.sh'), *args], capture_output=True, text=True,
                              env=env or self.env)

    def test_dry_run_shows_entries_and_never_a_value(self):
        r = self.run_fill('--dry-run')
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        out = r.stdout + r.stderr
        self.assertNotIn('v4lue', out)
        self.assertIn('would write  Tier 1/RESTIC_PASSWORD (cellar)  (cellar/restic)', out)
        self.assertIn('RESTIC_PASSWORD differs between nodes', out)
        self.assertIn('would write  Tier 1/RCLONE_CRYPT_PASSWORD  (cellar/restic)', out)
        self.assertIn('would write  Tier 4/CF_DNS_API_TOKEN (sieve)  (sieve/traefik-edge)', out)
        self.assertNotIn('CF_DNS_API_TOKEN differs', out, 'per-node keys differ on purpose')
        self.assertNotIn('KOMODO_JWT_SECRET', out.split('Not set on any node')[0], 'placeholders are skipped')
        self.assertIn('KOMODO_JWT_SECRET', out.split('Not set on any node')[1])

    def test_it_writes_through_stdin_and_updates_only_what_changed(self):
        store = self.tmp / 'store'
        cli = self.tmp / 'keepassxc-cli'
        cli.write_text(FAKE_CLI)
        cli.chmod(0o755)
        vault = self.tmp / 'flask.kdbx'
        vault.write_text('fake')
        env = dict(self.env, FLASK_KPX_CLI=str(cli), KPX_STORE=str(store), FLASK_TEST_MASTER='pw')
        r = self.run_fill('--vault', str(vault), env=env)
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertNotIn('v4lue', r.stdout + r.stderr)
        self.assertIn('6 added, 0 changed, 0 already up to date', r.stdout)
        self.assertNotIn('v4lue', (store / 'argv').read_text(), 'values go on stdin, never in argv')
        again = self.run_fill('--vault', str(vault), env=env)
        self.assertIn('0 added, 0 changed, 6 already up to date', again.stdout, again.stdout + again.stderr)
        (self.tmp / 'secrets' / 'sieve.txt').write_text(
            '/opt/purrbrews/stacks/backup/restic/secrets.env.local:RESTIC_PASSWORD=v4lue-restic\n'
            '/opt/purrbrews/stacks/network/traefik-edge/secrets.env.local:CF_DNS_API_TOKEN=v4lue-cf-new\n')
        third = self.run_fill('--vault', str(vault), env=env)
        self.assertIn('0 added, 1 changed, 5 already up to date', third.stdout, third.stdout + third.stderr)
        self.assertIn('changed  Tier 4/CF_DNS_API_TOKEN (sieve)', third.stdout)

    def test_a_wrong_master_password_stops_it(self):
        cli = self.tmp / 'keepassxc-cli'
        cli.write_text(FAKE_CLI)
        cli.chmod(0o755)
        vault = self.tmp / 'flask.kdbx'
        vault.write_text('fake')
        env = dict(self.env, FLASK_KPX_CLI=str(cli), KPX_STORE=str(self.tmp / 'store'), FLASK_TEST_MASTER='nope')
        r = self.run_fill('--vault', str(vault), env=env)
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("doesn't open", r.stderr)


class StickCheck(unittest.TestCase):
    def make_stick(self, name):
        stick = Path(tempfile.mkdtemp()) / name
        self.addCleanup(subprocess.run, ['rm', '-rf', str(stick.parent)])
        (stick / 'tools' / 'linux-amd64').mkdir(parents=True)
        (stick / 'tools' / 'linux-amd64' / 'restic').write_text('restic')
        (stick / 'RECOVERY.md').write_text('# RECOVERY\n')
        (stick / 'debian-live-13.7.0-amd64-xfce.iso').write_text('iso')
        sums = subprocess.run(['bash', '-c', 'cd "$1" && find . -type f | sed "s|^./||" | sort | xargs sha256sum',
                               '_', str(stick)], capture_output=True, text=True, check=True).stdout
        (stick / 'SHA256SUMS').write_text(sums)
        (stick / 'flask.kdbx').write_text('vault')
        (stick / '._RECOVERY.md').write_text('apple double')   # macOS litter: ignored
        return stick

    def check(self, *sticks):
        pairs = ' '.join(f'{s.name}={s}' for s in sticks)
        return subprocess.run(['bash', str(KIT / 'make-flask.sh'), '--check'], capture_output=True, text=True,
                              env=dict(os.environ, FLASK_TEST_STICKS=pairs))

    def test_a_good_pair_passes(self):
        a, b = self.make_stick('FLASK-A'), self.make_stick('FLASK-B')
        r = self.check(a, b)
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertIn('FLASK-A: all 3 files match SHA256SUMS', r.stdout)
        self.assertIn('flask.kdbx: the same on both sticks', r.stdout)
        self.assertNotIn('._RECOVERY.md', r.stdout + r.stderr)

    def test_a_changed_file_fails_and_an_extra_one_is_only_noted(self):
        a, b = self.make_stick('FLASK-A'), self.make_stick('FLASK-B')
        (b / 'tools' / 'linux-amd64' / 'restic').write_text('tampered')
        (a / 'notes.txt').write_text('mine')
        (a / 'flask.kdbx').write_text('newer vault')
        r = self.check(a, b)
        self.assertNotEqual(r.returncode, 0)
        self.assertIn('FLASK-B: changed or missing: tools/linux-amd64/restic', r.stderr)
        self.assertIn('FLASK-A: not part of the kit (left alone): notes.txt', r.stdout)
        self.assertIn('flask.kdbx differs between the sticks', r.stderr)

    def test_no_stick_is_an_error(self):
        r = subprocess.run(['bash', str(KIT / 'make-flask.sh'), '--check'], capture_output=True, text=True,
                           env={k: v for k, v in os.environ.items() if k != 'FLASK_TEST_STICKS'})
        self.assertNotEqual(r.returncode, 0)
        self.assertIn('no flask stick plugged in', r.stderr)


if __name__ == '__main__':
    unittest.main()
