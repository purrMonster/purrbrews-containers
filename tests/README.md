# Offline checks

Run from the repository root. These checks use temporary files, fake Docker
commands and local backup repositories; they do not deploy stacks or contact nodes.

CI runs these checks on pull requests: Linux suite and isolated root backup tests,
Windows Compose checks, shell analysis, inventory/image-lock checks, and a
checksum-verified Gitleaks scan of history. Deployment tests cover ordering,
optional apps, exact revisions, locking, partial failures and atomic state writes.
Upgrade-gate tests cover fresh data and refusals for existing data; they do not
rehearse real database migrations.

```sh
python3 scripts/fleet.py validate
python3 scripts/check-images.py
```

## Debian / WSL

Install dependencies in the test environment:

```sh
sudo apt-get update
sudo apt-get install --no-install-recommends python3 python3-pytest git restic sqlite3 rclone openssl shellcheck
```

Run the suite as a normal user so secret-generation and rendering tests execute:

```sh
PYTHONDONTWRITEBYTECODE=1 python3 -m pytest tests -q -p no:cacheprovider
```

Three backup tests require root. They create isolated local repositories under
`/tmp` and replace remote destinations with local aliases:

```sh
sudo env PYTHONDONTWRITEBYTECODE=1 python3 -m pytest tests -q -p no:cacheprovider -k 'dump_and_files_into_a_local_repository or drive_sync_never_mirrors_an_empty_or_different_repository or glob_dumps_are_named_by_path'
```

The rendering parity test also requires `pwsh` on Linux; it reports a skip when
PowerShell is absent. Do not interpret skips as passes. The Windows checks below
cover Windows Compose behavior separately.

## Windows PowerShell

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tests/test_compose_helpers.ps1
```

The execution-policy option applies only to that process. The test shadows Docker
with a function, checks preview and startup behavior, and leaves fixtures under
the ignored `graphify-out/verification/` directory for inspection.

The Python suite's source-only checks can run on Windows with UTF-8 enabled and
Git Bash on PATH. The full suite needs Linux filesystem permissions and tools.
The standard-library runner is also supported: `python3 -m unittest discover -s tests -v`.

## Source analysis

```sh
find bootstrap init stacks tailscale -type f -name '*.sh' -print0 | xargs -0 shellcheck --severity=warning
```

`CURRENT_STEP` in `init/purrbrews-mac.sh` is used by `warn()` and `die()` from the
sourced init script. ShellCheck without source following may report it as unused.
