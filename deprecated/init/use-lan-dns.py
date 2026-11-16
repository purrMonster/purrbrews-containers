#!/usr/bin/env python3
"""Switch a provisioned node to verified LAN DNS, without reconnecting its NIC."""
import argparse
import ipaddress
import json
import os
from pathlib import Path
import re
import shlex
import socket
import subprocess
import sys


def run(*args):
    return subprocess.check_output(args, text=True, stderr=subprocess.PIPE).strip()


def check_dns(server, name, expected=None, tcp=False):
    args = ['dig', '@' + server, name, 'A', '+time=2', '+tries=1', '+noall', '+comments', '+answer']
    if tcp:
        args.append('+tcp')
    response = run(*args)
    answers = re.findall(r'\sIN\s+A\s+([0-9.]+)', response)
    if 'status: NOERROR' not in response or not answers:
        raise ValueError(f'{server}: DNS check failed for {name}')
    if expected and set(answers) != {expected}:
        raise ValueError(f'{server}: {name} does not resolve exclusively to {expected}')


def migrate(domain, servers, auth_ip, dry_run=False):
    if not re.fullmatch(r'[a-z0-9]+(?:[.-][a-z0-9]+)*', domain):
        raise ValueError('Invalid DOMAIN')
    for address in [*servers, auth_ip]:
        ipaddress.IPv4Address(address)
    # Refuse migration unless BOTH resolvers answer local and public names,
    # over UDP and TCP, from the machine that will actually use them.
    for server in servers:
        for tcp in [False, True]:
            check_dns(server, 'authelia.' + domain, auth_ip, tcp)
            check_dns(server, 'example.com', tcp=tcp)
    routes = json.loads(run('ip', '-j', '-4', 'route', 'get', servers[0]))
    interface = routes[0]['dev']
    # A resolver host routes to its own address via lo; use the default NIC.
    if interface == 'lo':
        defaults = json.loads(run('ip', '-j', '-4', 'route', 'show', 'default'))
        if len(defaults) != 1:
            raise ValueError('Expected one IPv4 default route; inspect network configuration')
        interface = defaults[0]['dev']
    uuid = run('nmcli', '-g', 'GENERAL.CON-UUID', 'device', 'show', interface)
    if not re.fullmatch(r'[0-9a-fA-F-]{36}', uuid):
        raise ValueError('No active NetworkManager profile on ' + interface)
    settings = ['ipv4.dns', ','.join(servers), 'ipv4.ignore-auto-dns', 'yes',
                'ipv6.dns', '', 'ipv6.ignore-auto-dns', 'yes']
    print(f'{interface}: verified LAN DNS {", ".join(servers)}; profile {uuid}')
    if dry_run:
        print('Dry run: no settings changed.')
        return
    # Save only DNS properties, then apply only those properties to the active
    # device. Do not reapply unrelated saved settings or bring a connection down.
    run('nmcli', 'connection', 'modify', 'uuid', uuid, *settings)
    run('nmcli', 'device', 'modify', interface, *settings)
    print('Saved and applied DNS settings; network interface was not reconnected.')
    print(run('nmcli', '-g', 'IP4.DNS,IP6.DNS', 'device', 'show', interface))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--domain')
    parser.add_argument('--primary', default='192.168.0.10')
    parser.add_argument('--secondary', default='192.168.0.13')
    parser.add_argument('--auth-ip', default='192.168.0.11')
    parser.add_argument('--dry-run', action='store_true')
    args = parser.parse_args()
    if not args.dry_run and os.geteuid() != 0:
        raise ValueError('Run with sudo, or use --dry-run')
    domain = args.domain
    if not domain:
        stacks = Path(__file__).resolve().parents[1] / 'stacks'
        hostname = socket.gethostname().split('.')[0].lower()
        nodes = [p for p in stacks.iterdir() if p.name.lower() == hostname]
        if len(nodes) != 1:
            raise ValueError('Cannot find this node settings; provide --domain')
        for line in (nodes[0] / '.env.local').read_text().splitlines():
            if line.startswith('DOMAIN='):
                values = shlex.split(line.split('=', 1)[1], comments=True)
                domain = values[0] if len(values) == 1 else None
    if not domain:
        raise ValueError('DOMAIN is missing')
    migrate(domain, [args.primary, args.secondary], args.auth_ip, args.dry_run)


if __name__ == '__main__':
    try:
        main()
    except (ValueError, OSError, KeyError, IndexError, subprocess.CalledProcessError) as exc:
        sys.exit(f'DNS migration failed: {exc}. If saving succeeded but live application failed, the saved DNS settings will apply at the next connection activation.')
