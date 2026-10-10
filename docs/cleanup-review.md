# Workspace cleanup review

Reviewed 2026-10-09 on `codex/code-sanitization`, using the existing graph as a
navigation aid and checking the current source for references and discovery
rules. Graph warnings and missing references alone are not proof of dead code.
The initial pass was a local source review. The owner later authorized tests and
Debian test dependencies; verification results are recorded below. No live fleet
services were changed.

## Changes

- Corrected outdated backup, Windows init and power-policy descriptions in the
  overview docs using the dated runbook and current implementation. Recorded
  history is not a claim that the rebuilt workstation is running today.
- Added a shared-helper guide to [stacks/README.md](../stacks/README.md#where-shared-behavior-lives).
- Ignored `graphify-out/` in Git. It holds generated reports, caches and a local
  Python dependency installation; it remains available on disk. Archive contents
  are excluded from active graph discovery by `.graphifyignore`.
- Moved eight original Compose files into the [Deprecated archive](../Deprecated/README.md).
  Their active replacements extend two [shared definitions](../stacks/_shared/README.md).
  Node-local keys, disk devices and mochaPot's collector workaround remain local.
  No files were deleted.
- Added PowerShell `--help` and `--list` support without Docker or secrets. Linux
  inspection and teardown no longer migrate environment keys or create networks;
  startup, `run`, `watch` and `scale` retain that preparation. Invalid app targets fail before it.
  Both wrappers skip global option values when identifying the command, and use
  that command to select preflight and reverse teardown order.
- Updated existing source checks to include inherited environment variables and
  shared image pins, and to skip archives and generated packages during active
  source scans. The credential scan still includes archived files. Follow-up test
  results are recorded below.
- Documented dynamic discovery contracts and complete-repository deployment for
  shared Compose files. This makes implicit usage easier to follow.

## Components retained

| Candidate | Evidence and reason to keep it |
|---|---|
| Identical node wrapper scripts | Each passes its own directory to `stacks/_lib`; they provide the documented per-node commands. The implementation is already shared. |
| Remaining per-app specs (`secrets.conf`, `firewall`, `data-dirs`) | Location is part of the input contract. Shared service definitions now remove the larger Compose duplication without adding a new custom loader for tiny specs. |
| Cellar backup service and timer files | `node_units()` in `_lib/backup.sh` discovers `restic/*.service` and `restic/*.timer`; literal filename references are not required. |
| `step_*` and `Step-*` init functions | Both init scripts dispatch the step name dynamically. A function with only one literal occurrence is still called. |
| `groom-record.py` | Its header describes externally installed systemd drop-ins. None are present here, so its actual deployment cannot be established from this workspace. |
| `_lib/renamed-keys` | Setup uses it to migrate existing installations. Removing historical mappings could break an older node's next setup. |
| `restic-init.sh`, `lldap-bootstrap.sh`, `allow-wvd.py` | Current READMEs document these manual operations; lack of an automatic caller is expected. |
| roastery's shell and PowerShell scripts | The README supports both invocation paths. Consolidating them would change platform requirements. |
| `ollama` hostname and Open WebUI settings | The hostname is deliberately retained for compatibility. The runbook records unresolved machine authentication for Open WebUI; changing it is functional work. |
| `.claude/` and `CLAUDE.md` | Existing user-approved Graphify integration. The skill files referenced by `.claude/CLAUDE.md` are present. |

The local Markdown target scan found no missing file targets among tracked docs.
The Python import scan found no clearly unused ordinary imports; the apparent
`annotations` candidate is a `__future__` directive and was retained.

## Second review

Revisited the shared-file references, local bind mounts, percolator's second disk,
mochaPot's workaround, Compose command preparation and the checks that consume
raw Compose text. Included `run` in network preparation to preserve one-off
container behavior (also retained for `watch` and `scale`), corrected global-option
parsing in both wrappers, and kept credential scanning of the archive. The environment
coverage check now follows each node file's shared definition.

This initial review used source and diffs; follow-up execution is recorded below.
The active service definitions are shorter, while retained originals increase
the repository's total size as requested.

## Verification and second refactor

The follow-up fixed preview commands triggering startup preparation and added
Windows stale-render checks. Regression checks cover argument parsing, preview,
startup preflight, invalid targets and teardown order. Test collection now tolerates
Windows and resolves Bash explicitly; source scans follow shared Compose files.

Evidence on 2026-10-09:

- Debian full suite: 75 passed, 4 skipped. Three skipped backup integration tests
  passed separately as root. Linux `pwsh` rendering parity remains skipped.
- Native Windows Compose regression checks passed, including stale-render rejection.
- All eight resolved Compose configurations matched their archived originals
  using Docker Compose with fixture values; no containers were started.
- All active PowerShell scripts parsed. ShellCheck reported no errors and one
  known cross-file-use warning for `CURRENT_STEP` (used by imported `warn`/`die`).
- The original Windows pytest attempt was blocked by missing pytest; Debian now
  has pytest and the required backup tools. See [tests/README.md](../tests/README.md).

## Follow-ups requiring a decision

- Confirm whether `groom-record.py` is deployed through external drop-ins before
  considering retirement. No external project or node was inspected.
- Deployment remains a separate owner-authorized task. Offline comparisons passed;
  no live service rollout or alert-path check was performed.
- Choose how Graphify should be available to the Claude hooks. The settings call
  `graphify` by name, while this session used the existing local Python package
  installation. That does not establish availability in Claude's environment.
- Reconcile the historical Backlog with the owner's current fleet state in a
  separate task. Existing checkboxes and deployment settings were left intact.

The later verification installed dependencies in the owner's new Debian WSL
environment. No fleet node changes or pushes were performed. The pre-existing
runbook review and Claude changes remain separate from the cleanup commits.
