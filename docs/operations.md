# Fleet operations

This is infrastructure for six hosts. Compose files define services;
`stacks/<node>/node.conf` defines their order; `fleet.json` adds platform,
service tier, optional apps and prerequisites. No second list of IPs or app order.

## Release workflow

1. Review a PR and its offline verification results. Run the checks in
   [tests/README.md](../tests/README.md) locally before committing.
2. Read [image-upgrades.md](image-upgrades.md). Record a verified, restorable
   backup and the previous commit/image digests before upgrading stateful apps.
3. Fetch on the target host, select the reviewed **full commit ID**, and check out
   that revision during an authorized maintenance window. Preserve local secrets;
   never reset or discard unexplained changes. Pause overlapping backup/maintenance
   jobs explicitly if the upgrade requires it, and record how to resume them.
4. Run the plan below, complete node README prerequisites, then deploy as `barista`.
5. Check application functions and alert delivery, record evidence in the runbook,
   and only then proceed to the next host. Never update both DNS servers together.

```sh
# From the repository root; these two commands are read-only.
python3 scripts/fleet.py validate
python3 scripts/fleet.py plan grinder

# Run on grinder, after selecting a reviewed, clean checkout.
python3 scripts/fleet.py deploy grinder --release <full-commit-id> --acknowledge-prerequisites
python3 scripts/fleet.py status grinder
```

Linux node-local `bash scripts/run.sh` shows the plan. Pass the same `--release`
and `--acknowledge-prerequisites` options to execute setup/render → firewall →
Compose in `node.conf` order. Existing individual node-root commands remain valid.
One-off DHCP and LLDAP scripts now live in their node's `scripts/`; their old paths
forward to them. Recovery and backups are never included in routine deployment.

The runner rejects the wrong host, wrong OS, root on Linux, a dirty checkout or
an unexpected commit. A lock shared across the operator's checkouts prevents two
runners on the same host. It cannot lock out manual Docker commands, another OS
user or scheduled jobs. Per-phase records in ignored `.fleet/` contain no command
output. `status` shows the last recorded run, **not live health**; `running` may mean
an interrupted process. Inspect the host before retrying.

Each Compose launch uses `--wait --wait-timeout 180` (adjust with `--wait-timeout`).
The runner sets `PURRBREWS_KEEP_IMAGES=1` so previous images remain available for
rollback. Standalone wrappers retain their existing post-upgrade cleanup policy.
This waits for configured health checks; services without one only need to be
running. It does not prove login, backups, DNS failover or external alert delivery.
If a phase fails, later phases do not run; completed changes remain applied.
Setup and firewall can also leave partial changes. Inspect and repair the failed
phase before retrying; there is no automatic data rollback.

Cellar excludes SMB and the separately maintained watcher by default. Select
`--include-optional smb` or `--include-optional persian-perch` only after their own
READMEs' prerequisites are complete. Windows uses `python scripts/fleet.py ...`
and its existing PowerShell helpers; native firewall, Traefik, game mode and GPU
drivers remain explicit steps in roastery's README.

## Provisioning versus deployment

Provisioning (`init/`) changes the OS, network and scheduled services. Use it for
rebuilds or an explicit host change, not every application release. The existing
`purrbrews-pull` timer name is retained, but its installed helper now fetches only:
the checkout used by scheduled jobs no longer moves unattended. Roll out the new
timer helper through the init `timers` step during an authorized host change;
editing this repo alone does not replace an already installed helper.

## Recovery and rollback

- Configuration-only: select the previous reviewed commit, render and redeploy
  the affected app; verify its routes, DNS and alert paths.
- Database/application migrations: restore a matched pre-upgrade data backup and
  image version. Reverting Git or an image tag alone is not a database rollback.
- Backups: follow [cellar/restic](../stacks/cellar/restic/README.md), including its
  restore test and repository identity checks. Run a restore to an isolated path;
  never use a healthy production directory as the test destination.
- Network/DNS: retain console or Tailscale access and the router fallback before
  changing DHCP/firewall. Follow the node's documented recovery checks.

## Readiness targets and remaining operational work

Proposed targets below require owner agreement and measured recovery drills;
they are not claims about current availability or capacity.

| Tier | Services | Proposed recovery target | Release evidence |
|---|---|---|---|
| Essential | DNS, DHCP, remote access, alerts | restore service within 1 hour | both DNS paths, remote login, primary and fallback alert received |
| Data | identity, files, photos, documents, vault | lose at most 24 hours; restore within 4 hours | isolated restore plus login/read/write checks |
| Recovery | backup hub, repositories, inventory | restore within 4 hours | repository identity, integrity check and independent restore |
| Household | home automation and music | restore within 4 hours | local controls work without ingress/identity |
| Optional/compute | automation, indexing, GPU | next maintenance window | app-specific smoke checks |

The backup target still depends on roastery. Moving it to independent storage,
adding an offline/immutable copy, completing the recovery kit and measuring
power-loss recovery require hardware/live work. Preserve these as open runbook
items until verified. Linux source tests cannot prove Windows GPU support,
household DNS failover, real data migration or external alert delivery.

## Secrets

Keep `.env.local`, `secrets.env.local`, private keys, topics and callback URLs out
of Git and PR text. Only placeholder examples belong here. Real values are
generated/pasted on the host and may be included in encrypted recovery backups.
Rotate at the source, update dependent local files, render, restart only affected
services, and test their authentication/alert path. Never paste resolved Compose
output into an issue; it includes secrets.

Gitleaks scans history in CI; scan the working changes and `git diff origin/main`
before a public push, including the private domain. No scanner proves absence of
every secret. Backup status records omit journal text by default. Only set
`GROOM_INCLUDE_LOGS=1` after reviewing the logged data: those records are readable
by the watcher user, so enabling it can expose credentials from upstream logs.
