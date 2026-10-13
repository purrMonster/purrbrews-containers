# Image upgrades

Every registry image in this repo (Compose files, Dockerfile bases, the
restore test's Postgres client) is pinned by tag and digest:
`image: name:tag@sha256:…`. The tag says what it is; the digest means a pull can
never change what runs, even for upstream channels that only publish `main` or
`latest` (Unbound, Samba, Karakeep's browser). Images built here (`:local`) are
the only exception. `tests/` enforces this, and that one tag has one digest
everywhere, and that paired images share a version.

Dependabot proposes new versions as PRs and moves the tag and digest together.
To pin something by hand, `python3 scripts/images.py <image:tag> …` asks the
public registry for the digest without credentials, pulls or containers. A
resolvable digest proves the image exists, not that it works with our data.

Merging a PR changes nothing on a node: nodes only fetch `main` daily, and a
node moves when a reviewed commit is checked out and deployed there
([operations](operations.md)).

## Images that move together

- Immich server (percolator) and machine learning (roastery): same version.
- Komodo Core (cellar) and every Periphery: same version.
- The Scrutiny hub (cellar) and its collectors: same version.
- Pi-hole on sieve and mochaPot: same version, but deploy the secondary
  (mochaPot) first, check resolution, then sieve in a separate window.

## Database majors stay put

Postgres stays at the major each volume was created with (14 for Immich's own
image, 16, 17, 18), Mongo at 7.0, Valkey at 9, Redis at 8. A major change against an
existing volume is a dump and restore, done by hand; Dependabot ignores those
(see `.github/dependabot.yml`).

## Upgrades that change data one way

Four apps migrate their data on start, and the old version can't read it
afterwards. For these, each app's `prepare.sh` (run by `compose.sh` before
`up`) calls `stacks/_lib/upgrade-gate.sh`: with existing data, it refuses to
start a version that hasn't been acknowledged in the node's `.env.local`.

| App (node) | Key in `.env.local` | Acknowledge |
|---|---|---|
| OpenCloud (percolator) | `OPENCLOUD_UPGRADE_READY` | the pinned major, e.g. `7` |
| Meilisearch for Karakeep (grinder) | `KARAKEEP_SEARCH_UPGRADE_READY` | the version, e.g. `1.41.0` |
| Traccar (grinder) | `TRACCAR_UPGRADE_READY` | the version, e.g. `6.16` |
| Open WebUI (grinder) | `OPENWEBUI_UPGRADE_READY` | the version, e.g. `0.11.4` |

The gate records the version the data is on in `.upgrade-gate-<KEY>`, beside
the data (so it's backed up and restored with it): on a fresh install, and
after an acknowledged upgrade. Redeploying that same version, a fresh node's
second deploy included, needs no key. Data without a record (from before
2026-10-13) needs the key once, then it's recorded.

The refusal names the exact value. Every later bump (major for OpenCloud) changes the acknowledged version,
so the gate closes again by itself. It is a reminder, not a backup: set the key
only after the steps below. Plain `docker compose` bypasses it.

Each one, in general: read the release notes from the running version up;
take a backup you've checked (last night's snapshot, or a copy of the data
directory with the app stopped); set the key; `./compose.sh <app> up -d`;
check the app, not just that the container is healthy. To go back: stop the
app, restore the data directory, set the image back in Git. Reverting the image
alone doesn't work once the data has been migrated.

### OpenCloud majors

Read the [upstream upgrade guide](https://docs.opencloud.eu/docs/admin/maintenance/upgrade/upgrade-guide/)
and the migration notes for each intervening major, including the
[7.x configuration migration](https://docs.opencloud.eu/docs/admin/maintenance/upgrade/upgrade-7.x.x/)
when crossing that boundary. Follow the supported sequence; do not assume a
major can be skipped or that replacing the image performs every migration.

1. Stop client writes and stop OpenCloud for a consistent backup of its entire
   config and data directories plus matching secrets. Rehearse the upgrade on
   an isolated restore before changing the live copy.
2. Pin the target tag and digest with `scripts/images.py`. Compare the generated
   config with the target's defaults and apply the version-specific migration
   instructions; never run forced initialization over existing identity state.
3. Set `OPENCLOUD_UPGRADE_READY` in percolator's `.env.local` to the pinned major
   printed by the gate, then `./compose.sh opencloud up -d`.
4. Verify admin/household OIDC, bot app-token DAV, file checksums, shares, iOS
   Files integration and desktop sync, then repeat the restore check.

Rollback requires stopping the new service and restoring its matching old
config, data, secrets and image digest. An image-only downgrade is not a rollback.
The major gate is a reminder; patch/minor releases still need release-note review.
Radicale has no gate: no mandatory collection-format migration was found for
our standalone 3.8.3 storage configuration in the
[tagged changelog](https://github.com/Kozea/Radicale/blob/v3.8.3/CHANGELOG.md)
and [v3 documentation](https://radicale.org/v3.html). Review future release
notes; optional sharing formats are not enabled here.

### Meilisearch 1.10 → 1.41.0 (Karakeep)

v1.41.0 is the version Karakeep's own compose pins for the release we run
(0.33.2), not the newest Meilisearch: Karakeep is only tested against that one.
Move it when Karakeep's compose moves, and raise the `getmeili/meilisearch`
ignore rule in `.github/dependabot.yml` with it.

A newer Meilisearch won't open an older index. The index holds nothing of its
own (bookmarks are in Karakeep's SQLite), so the simple way is to rebuild it:

1. `./compose.sh karakeep down`
2. Move `${DATA_DIR}/karakeep-meilisearch` aside (keep it for going back).
3. Set `KARAKEEP_SEARCH_UPGRADE_READY=1.41.0`, then `./compose.sh karakeep up -d`.
4. In Karakeep's admin settings, reindex all bookmarks; check a search.

The alternative, keeping the index, is a dump from 1.10 and an import into
1.41.0 ([Meilisearch's guide](https://www.meilisearch.com/docs/resources/migration/updating)).
Going back: restore the moved directory and the old image.

Karakeep's browser moved to upstream's own `karakeep-chrome` image, configured
as in [Karakeep's compose](https://github.com/karakeep-app/karakeep/blob/v0.33.2/docker/docker-compose.yml).
Check a new bookmark gets its screenshot.

### Traccar 6.2 → 6.16

Traccar migrates its H2 database on start. With Traccar stopped, copy
`${DATA_DIR}/traccar/data`, set `TRACCAR_UPGRADE_READY=6.16`, start it, and
check the bike's latest position arrives and Home Assistant still sees it.

### Open WebUI `main` build → a release

The running build came from `main` (reported 0.11.3, wasn't that release); the
repo now pins a release (0.12.0 since 2026-10-13). Read the release notes from
0.11.3 up, back up `openwebui/webui.db` (grinder's `sqlite` backup line does this
nightly), set `OPENWEBUI_UPGRADE_READY` to the version `compose.sh` names, start
it, check a login and a chat.

## Others worth a look before deploying

- Immich 3.2.1 → 3.3.1: server on percolator and ML on roastery together;
  check an upload gets its thumbnails and faces.
- Traefik 3.7.14 has security changes:
  [its migration notes](https://doc.traefik.io/traefik/v3.7/migrate/v3/#v3714).
- After any change to sieve (Pi-hole, Unbound, Gatus, ntfy, cloudflared): check
  resolution, DHCP, and both alert paths.
