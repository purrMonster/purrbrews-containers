import importlib.util
from pathlib import Path
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('migration', Path(__file__).resolve().parents[1] / 'init/use-lan-dns.py')
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)


class Migration(unittest.TestCase):
    def answer(self, *args):
        if args[0] == 'dig':
            ip = '192.168.0.11' if args[2].startswith('authelia.') else '192.0.2.1'
            return 'status: NOERROR\nname. 0 IN A ' + ip
        if args[0] == 'ip':
            return '[{"dev":"eth0"}]'
        if args[:3] == ('nmcli', '-g', 'GENERAL.CON-UUID'):
            return '293ce32d-dba4-454e-a22e-8e8daf848ade'
        return ''

    def test_failed_resolver_prevents_mutations(self):
        with patch.object(m, 'run', return_value='status: NXDOMAIN') as run:
            with self.assertRaises(ValueError):
                m.migrate('example.test', ['192.168.0.10', '192.168.0.13'], '192.168.0.11')
            self.assertTrue(all(c.args[0] == 'dig' for c in run.call_args_list))

    def test_only_dns_properties_applied_no_reconnect(self):
        with patch.object(m, 'run', side_effect=self.answer) as run:
            m.migrate('example.test', ['192.168.0.10', '192.168.0.13'], '192.168.0.11')
            calls = [c.args for c in run.call_args_list]
            self.assertEqual(sum(c[0] == 'dig' for c in calls), 8)
            changes = [c for c in calls if 'modify' in c]
            self.assertEqual(len(changes), 2)
            self.assertEqual(changes[0][1:4], ('connection', 'modify', 'uuid'))
            self.assertEqual(changes[1][1:3], ('device', 'modify'))
            for c in changes:
                self.assertIn('ipv6.ignore-auto-dns', c)
                self.assertNotIn('ipv6.method', c)
                self.assertNotIn('ipv4.addresses', c)
            self.assertFalse(any('down' in c or 'up' in c or 'reapply' in c for c in calls))

    def test_dry_run_does_not_modify(self):
        with patch.object(m, 'run', side_effect=self.answer) as run:
            m.migrate('example.test', ['192.168.0.10', '192.168.0.13'], '192.168.0.11', True)
            self.assertFalse(any('modify' in c.args for c in run.call_args_list))

    def test_own_resolver_uses_default_nic(self):
        def answer(*args):
            if args[:5] == ('ip', '-j', '-4', 'route', 'get'):
                return '[{"dev":"lo"}]'
            return self.answer(*args)
        with patch.object(m, 'run', side_effect=answer) as run:
            m.migrate('example.test', ['192.168.0.10', '192.168.0.13'], '192.168.0.11', True)
            self.assertTrue(any(c.args == ('ip', '-j', '-4', 'route', 'show', 'default') for c in run.call_args_list))
