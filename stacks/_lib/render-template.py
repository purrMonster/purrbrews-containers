#!/usr/bin/env python3
"""Render envsubst-style variables, refusing missing settings before atomic write."""
import os
from pathlib import Path
import re
import sys
import tempfile

VARIABLE = re.compile(r'\$(?:\{([A-Za-z_][A-Za-z0-9_]*)\}|([A-Za-z_][A-Za-z0-9_]*))')


def render(path, env):
    text = path.read_text()
    # Comments document shell runtime variables, not deployment requirements.
    active = '\n'.join(line for line in text.splitlines() if not line.lstrip().startswith('#'))
    required = {a or b for a, b in VARIABLE.findall(active)}
    invalid = sorted(key for key in required if not env.get(key) or 'REPLACE_ME' in env[key])
    if invalid:
        raise ValueError('unset, empty or placeholder: ' + ', '.join(invalid))
    result = VARIABLE.sub(lambda m: env.get(m[1] or m[2], m[0]), text)
    out = path.with_suffix('')
    mode = 0o644 if re.match(r'^#\s*render-mode:\s*0?644\s*$', next(iter(text.splitlines()), '')) else 0o600
    fd, tmp = tempfile.mkstemp(prefix=out.name + '.', dir=out.parent)
    try:
        with os.fdopen(fd, 'w') as stream:
            os.fchmod(stream.fileno(), mode)
            stream.write(result)
        os.replace(tmp, out)
    finally:
        if os.path.exists(tmp):
            os.unlink(tmp)


if __name__ == '__main__':
    try:
        render(Path(sys.argv[1]), os.environ)
    except (ValueError, OSError) as exc:
        sys.exit(f'FAILED: {sys.argv[1]}: {exc}')
