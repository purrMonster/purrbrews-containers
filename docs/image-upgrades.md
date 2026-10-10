# Image release review — 2026-10-10

[`image-lock.json`](../image-lock.json) records all 49 active registry inputs:
previous references, selected tags, registry digests, platforms and file coverage.
Compose, shared services, Dockerfile bases, the restore-test client and Windows
GPU probe all use exact digests. Local builds keep `:local`; their source and
runtime dependencies still need review when rebuilt.

Use `python scripts/check-images.py` for an offline consistency check.
`python scripts/images.py <image:tag> ...` queries public registries without
credentials, pulling layers or starting containers. Review its output and the
upstream release notes before updating manifests and the lock together. A valid
manifest proves availability, not application compatibility or vulnerability freedom.

## Selection policy and exceptions

Application images use the latest stable releases found in the publishers'
release metadata on the review date. Matching components move together: Immich
server/ML, Komodo Core/Periphery, and Scrutiny hub/collectors. nginx follows its
stable channel. Pi-hole is 2026.09.0 on both DNS hosts. Unbound, Samba and Karakeep's
browser publish the selected channel names; their digests prevent those names
from drifting after review.

Existing PostgreSQL majors remain 14 (Immich's upstream-supported extension
image), 16, 17 and 18. Generic clients/servers now use 16.15, 17.11 and 18.6;
pgvector is 0.8.7-pg16. Mongo remains 7.0 with the 7.0.43 maintenance release.
PostGIS keeps the 16-3.5 family with its refreshed digest. These are intentional
exceptions to a global newest-major policy: changing a database major against an
existing volume can prevent startup or require a data migration. Plan those
migrations separately with a restored copy, extension compatibility and a rollback.
Python remains 3.12 with its latest maintenance image to preserve model/runtime
compatibility. Neither model vectors nor embedding API behavior are changed here.

## Mandatory rollout checks

### Nextcloud 34 → 35

Upgrade the existing 34 installation to its latest 34 maintenance release first,
finish its background migrations, and verify installed app compatibility. Then
take a fresh matched database/config/files backup before deploying 35.0.1.
Upgrade one major at a time. The web and cron containers use the same image.
Check `occ status`, maintenance mode, background jobs, login, upload and download.
Downgrade requires restoring pre-upgrade data, not merely selecting the old image.
The Compose wrapper refuses existing Nextcloud data until the operator records
`NEXTCLOUD_UPGRADE_READY=35.0.1` in percolator's ignored `.env.local` after completing
these prerequisites. This acknowledgement is not a migration or backup check.
See [Nextcloud's upgrade procedure](https://docs.nextcloud.com/server/35/admin_manual/maintenance/upgrade.html).

### Karakeep browser and Meilisearch

The maintained upstream Karakeep Chrome image replaces Chrome 124. Its entrypoint
owns the debugging ports; our previous explicit port flags are removed and the
health check verifies an HTTP response. Validate screenshots, new bookmarks,
archiving, login and search in staging before deploying.

Meilisearch moves from 1.10 to 1.54.3. **Do not start this against an unmigrated
production index.** Export a completed dump using the old server, preserve a cold
copy of the old index, and import into a separate empty data directory with the
new version. Validate search and indexing with Karakeep before switching the
production bind mount. Keep the old directory and image for rollback. Karakeep
0.33.2's published example uses 1.41.0, so compatibility with the requested newest
Meilisearch must be demonstrated locally before rollout; registry verification
alone is insufficient. If that check fails, retain the supported version and
record the exception instead of deploying a broken search service.
The wrapper refuses an existing search index until
`KARAKEEP_SEARCH_UPGRADE_READY=1.54.3` is recorded in grinder's ignored `.env.local`
after the migration/compatibility rehearsal. Direct Docker commands bypass these
wrapper checks; use the documented entrypoints.
See [Karakeep's versioned Compose example](https://github.com/karakeep-app/karakeep/blob/v0.33.2/docker/docker-compose.yml)
and [Meilisearch's migration guide](https://www.meilisearch.com/docs/resources/migration/updating).

### Immich, Paperless and other stateful apps

Immich server/ML move together to 3.3.1; retain the database image recommended by
that release. Back up before application migrations, confirm uploads and GPU/CPU
ML processing, and retain the previous versions with a matched restore point.
Paperless 3.3.0, n8n 2.42.6, Traccar 6.16 and the other updated applications also
need their release notes and data migrations reviewed on a restored copy. Do not
use container readiness as evidence that historical data or integrations work.
See the [Immich release Compose](https://github.com/immich-app/immich/blob/v3.3.1/docker/docker-compose.yml).

### GPU and essential network services

The Windows CUDA diagnostic image is 13.4.2 on Ubuntu 24.04. Update/check the NVIDIA
driver's CUDA compatibility before invoking the probe; it is not a driver updater.
The existing llama-swap CUDA release remains 262, now with a verified digest.

Upgrade secondary DNS first, test resolution, then primary DNS in a separate
window. Check Pi-hole DHCP, Unbound, tunnel routing, certificates and both alert
paths after the relevant changes. Traefik 3.7.14 includes security-related changes;
review [its migration notes](https://doc.traefik.io/traefik/v3.7/migrate/v3/#v3714).
No live images, data, host settings or alerts were changed by this repository pass.
