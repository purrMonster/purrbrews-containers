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

Merging a PR changes nothing on a node: nodes pull `main` daily, but nothing
restarts until `./compose.sh <app> up -d` on that node.

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
| Nextcloud (percolator) | `NEXTCLOUD_UPGRADE_READY` | the major, e.g. `35` |
| Meilisearch for Karakeep (grinder) | `KARAKEEP_SEARCH_UPGRADE_READY` | the version, e.g. `1.41.0` |
| Traccar (grinder) | `TRACCAR_UPGRADE_READY` | the version, e.g. `6.16` |
| Open WebUI (grinder) | `OPENWEBUI_UPGRADE_READY` | the version, e.g. `0.11.4` |

The refusal names the exact value. Every later bump changes the pinned version,
so the gate closes again by itself. It is a reminder, not a backup: set the key
only after the steps below. Plain `docker compose` bypasses it.

Each one, in general: read the release notes from the running version up;
take a backup you've checked (last night's snapshot, or a copy of the data
directory with the app stopped); set the key; `./compose.sh <app> up -d`;
check the app, not just that the container is healthy. To go back: stop the
app, restore the data directory, set the image back in Git. Reverting the image
alone doesn't work once the data has been migrated.

### Nextcloud 34 → 35

Nextcloud goes up one major at a time, from the newest release of the one
before. Bring 34 to its last maintenance release first and let its background
jobs finish; check installed apps support 35. Take a backup of the database
(`pg` line in percolator's backup), config and data, then set
`NEXTCLOUD_UPGRADE_READY=35`. After `up`: `occ status`, no maintenance mode,
background jobs running, a login, an upload and a download.
[Nextcloud's upgrade procedure](https://docs.nextcloud.com/server/35/admin_manual/maintenance/upgrade.html).

### Meilisearch 1.10 → 1.41.0 (Karakeep)

v1.41.0 is the version Karakeep's own compose pins for the release we run
(0.33.2), not the newest Meilisearch: Karakeep is only tested against that one.
Move it when Karakeep's compose moves.

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

### Open WebUI `main` build → v0.11.4

The running build came from `main` (reported 0.11.3, wasn't that release).
Back up `openwebui/webui.db` (grinder's `sqlite` backup line does this nightly),
set `OPENWEBUI_UPGRADE_READY=0.11.4`, start it, check a login and a chat.

## Others worth a look before deploying

- Immich 3.2.1 → 3.3.1: server on percolator and ML on roastery together;
  check an upload gets its thumbnails and faces.
- Traefik 3.7.14 has security changes:
  [its migration notes](https://doc.traefik.io/traefik/v3.7/migrate/v3/#v3714).
- After any change to sieve (Pi-hole, Unbound, Gatus, ntfy, cloudflared): check
  resolution, DHCP, and both alert paths.
