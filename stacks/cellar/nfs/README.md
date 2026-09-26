# nfs

`MEDIA_DIR/archive` (normally `/srv/media/archive`) exported to the LAN, for
app archives that other nodes may one day mount. Host-native, no compose file:
the NFS server images are abandoned and want `--privileged`
(see `setup-nfs.sh`).

```sh
sudo ./nfs/setup-nfs.sh        # installs nfs-kernel-server if missing; safe to re-run
showmount -e localhost
```

It manages one marked block in `/etc/exports` and leaves the rest of the file
alone. Everything is squashed to UID/GID 1000 (the ops user, and the SMB share's
`UID_barista`), so SMB and NFS clients agree on who owns what.

Nothing mounts it yet. When something does, check the consuming container's UID
against 1000 before trusting it.
