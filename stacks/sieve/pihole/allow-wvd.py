#!/usr/bin/env python3
"""Reconcile the approved WVD exception via sieve's local Pi-hole v6 API.

Run on sieve after pulling Git. The rule persists in the mounted gravity database.
No credentials, direct database writes, or DNS service restart are needed.
"""
import json
from urllib.parse import quote
from urllib.request import Request, urlopen

BASE = 'http://127.0.0.1:8080/api'
PATTERN = r'(\.|^)wvd\.microsoft\.com$'


def api(path, method='GET', payload=None):
    data = None if payload is None else json.dumps(payload).encode()
    request = Request(BASE + path, data=data, method=method,
                      headers={'Content-Type': 'application/json'})
    with urlopen(request, timeout=10) as response:
        result = json.load(response)
    if result.get('processed', {}).get('errors'):
        raise RuntimeError(result['processed']['errors'])
    return result


def main():
    allows = api('/domains/allow/regex')['domains']
    denies = api('/domains/deny/regex')['domains']
    allowed = next((r for r in allows if r['domain'] == PATTERN), None)
    denied = next((r for r in denies if r['domain'] == PATTERN), None)
    groups = sorted(set([0] + (allowed or {}).get('groups', [])
                        + (denied or {}).get('groups', [])))
    payload = {'enabled': True, 'groups': groups,
               'comment': 'Managed in Git: Windows App / Azure Virtual Desktop service endpoints'}
    encoded = quote(PATTERN, safe='')
    if allowed:
        api('/domains/allow/regex/' + encoded, 'PUT', payload)
        if denied:
            # Keep a disabled record for audit; the allow rule is authoritative.
            api('/domains/deny/regex/' + encoded, 'PUT',
                {**payload, 'enabled': False})
    elif denied:
        api('/domains/deny/regex/' + encoded, 'PUT',
            {**payload, 'type': 'allow', 'kind': 'regex'})
    else:
        api('/domains/allow/regex', 'POST', {**payload, 'domain': PATTERN})
    # Some FTL versions retain the source entry when changing list type.
    for rule in api('/domains/deny/regex')['domains']:
        if rule['domain'] == PATTERN and rule['enabled']:
            api('/domains/deny/regex/' + encoded, 'PUT',
                {**payload, 'enabled': False})
    rules = api('/domains/allow/regex')['domains']
    if not any(r['domain'] == PATTERN and r['enabled'] and
               set(groups).issubset(r['groups']) for r in rules):
        raise RuntimeError('WVD allow rule verification failed')
    if any(r['domain'] == PATTERN and r['enabled']
           for r in api('/domains/deny/regex')['domains']):
        raise RuntimeError('WVD deny rule remains enabled')
    print('Verified: wvd.microsoft.com and all subdomains allowed.')


if __name__ == '__main__':
    main()
