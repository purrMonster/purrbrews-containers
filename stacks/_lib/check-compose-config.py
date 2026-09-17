#!/usr/bin/env python3
"""Reject placeholders in resolved Compose configuration without printing secrets."""
import json
import sys


def placeholders(value, path='config'):
    if isinstance(value, dict):
        return [p for k, v in value.items() for p in placeholders(v, f'{path}.{k}')]
    if isinstance(value, list):
        return [p for i, v in enumerate(value) for p in placeholders(v, f'{path}[{i}]')]
    return [path] if isinstance(value, str) and 'replace_me' in value.lower() else []


if __name__ == '__main__':
    try:
        invalid = placeholders(json.load(sys.stdin))
    except (ValueError, OSError):
        sys.exit('Cannot validate resolved Compose configuration; refusing startup.')
    if invalid:
        sys.exit('Unfilled placeholders in: ' + ', '.join(invalid) + '. Fix local settings before startup. Values withheld.')
