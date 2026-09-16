# nfs

No `docker-compose.yml` here, deliberately — see `setup-nfs.sh`'s own
header comment for why (containerized NFS servers still aren't
recommended for this fleet as of 2026-09-16, same finding the
pre-restructure cellar build made on 2026-09-03; nothing changed since).

Run `sudo ./setup-nfs.sh` once, after `../setup-secrets.sh` has created
`.env.local`. It installs `nfs-kernel-server` if missing, creates and
chowns `/srv/media/archive`, and writes a managed block into
`/etc/exports` (safe to re-run — replaces its own block, never touches
anything else in that file).

Not consumed by anything yet as of this stack's creation — percolator and
mochaPot don't have anything trying to mount from cellar until they're
migrated into this repo and their own archive-mount config is written. See
`../smb/docker-compose.yml`'s own comment on the UID/GID reconciliation
this still needs before that happens.
