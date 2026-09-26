#!/usr/bin/env python3
"""Generate identical split DNS on both Pi-holes from routers and fleet CSV."""
import argparse
import csv
import ipaddress
import os
from pathlib import Path
import re
import shlex
import sys
import tempfile

RULE = re.compile(r'''^\s*(?:rule:|-?\s*["']?\s*traefik\.http\.routers\.[\w-]+\.rule\s*[=:])''')
HOST = re.compile(r'Host\(`([a-z0-9.-]+)\.(?:\$\{DOMAIN\}|\{\{\s*env "DOMAIN"\s*\}\})`\)')


def records(root, domain, fleet, extra_hosts='', existing_hosts=''):
    if not re.fullmatch(r'[a-z0-9]+(?:[.-][a-z0-9]+)*', domain) or 'REPLACE_ME' in domain:
        raise ValueError('DOMAIN must be a real lowercase DNS domain')
    addresses = {}
    for row in csv.DictReader(fleet):
        addresses[row['name']] = str(ipaddress.IPv4Address(row['ip']))
    # Native hosts such as roastery need DNS without a cloned fleet DHCP MAC.
    for entry in extra_hosts.split(';'):
        if not entry.strip():
            continue
        address, *names = entry.split()
        address = str(ipaddress.IPv4Address(address))
        if not names:
            raise ValueError('PIHOLE_DNS_EXTRA_HOSTS entries need an IP and host name')
        for name in names:
            if name in addresses and addresses[name] != address:
                raise ValueError(f'Conflicting address for {name}')
            addresses[name] = address
    # Reuse existing native router host records without letting stale generated
    # fleet addresses override the current inventory or explicit extras.
    existing = {}
    for entry in existing_hosts.split(';'):
        fields = entry.split()
        if len(fields) < 2:
            continue
        for name in fields[1:]:
            existing[name] = fields[0]
    routes = {}
    paths = set(root.glob('stacks/*/traefik/dynamic/*.yml'))
    paths.update(root.glob('stacks/*/traefik/config/**/*.template'))
    paths.update(root.glob('stacks/*/*/docker-compose.yml'))
    for path in sorted(paths):
        node = path.relative_to(root).parts[1]
        for line in path.read_text().splitlines():
            if not RULE.match(line):
                continue
            matches = HOST.findall(line)
            if 'Host(' in line and not matches:
                raise ValueError(f'Unsupported Host rule in {path.relative_to(root)}')
            for label in matches:
                if node not in addresses and node in existing:
                    addresses[node] = str(ipaddress.IPv4Address(existing[node]))
                if node not in addresses:
                    raise ValueError(f'Router node {node} is missing from NODE_IPS, PIHOLE_DNS_EXTRA_HOSTS and PIHOLE_DNS_HOSTS')
                name = f'{label}.{domain}'
                if name in routes and routes[name] != addresses[node]:
                    raise ValueError(f'Conflicting route for {name}')
                routes[name] = addresses[node]
    if not routes:
        raise ValueError('No app routes found; refusing to replace DNS records')
    lines = ['filter-AAAA']
    for name, address in sorted(routes.items()):
        # dnsmasq >=2.86 otherwise forwards AAAA/HTTPS queries upstream.
        # Scope local= to app names: leave public TXT/ACME names alone.
        lines.extend((f'address=/{name}/{address}', f'local=/{name}/'))
    hosts = [f'{ip} {name}' for name, ip in sorted(addresses.items())]
    return lines, hosts


def read_env(path):
    values = {}
    for line in path.read_text().splitlines():
        if re.match(r'^[A-Za-z_][A-Za-z0-9_]*=', line):
            key, raw = line.split('=', 1)
            parts = shlex.split(raw, comments=True)
            if len(parts) > 1:
                raise ValueError(f'{key} must be quoted if it contains spaces')
            values[key] = parts[0] if parts else ''
    return values


def update_env(path, updates):
    content = path.read_text().splitlines()
    for key, value in updates.items():
        if "'" in value or '\n' in value:
            raise ValueError(f'Invalid character in {key}')
        content = [line for line in content if not line.startswith(key + '=')]
        content.append(f"{key}='{value}'")
    fd, name = tempfile.mkstemp(prefix=path.name + '.', dir=path.parent)
    try:
        with os.fdopen(fd, 'w') as stream:
            stream.write('\n'.join(content) + '\n')
        os.replace(name, path)
    finally:
        if os.path.exists(name):
            os.unlink(name)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--node-dir', type=Path, required=True)
    args = parser.parse_args()
    node = args.node_dir.resolve()
    path = node / '.env.local'
    values = read_env(path)
    lines, hosts = records(node.parent.parent, values.get('DOMAIN', ''), sys.stdin,
                           values.get('PIHOLE_DNS_EXTRA_HOSTS', ''),
                           values.get('PIHOLE_DNS_HOSTS', ''))
    if node.name == 'sieve':
        by_name = {entry.split()[1]: entry.split()[0] for entry in hosts}
        lines.append('dhcp-option=option:dns-server,' + by_name['sieve'] + ',' + by_name['mochaPot'])
    update_env(path, {'PIHOLE_DNSMASQ_LINES': ';'.join(lines),
                      'PIHOLE_DNS_HOSTS': ';'.join(hosts)})
    print(f'{node.name}: generated {(len(lines) - 1) // 2} local app names')


if __name__ == '__main__':
    try:
        main()
    except (ValueError, KeyError, OSError) as exc:
        sys.exit(f'DNS generation failed: {exc}')
