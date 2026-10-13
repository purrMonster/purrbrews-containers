#!/usr/bin/env bash
#
# upgrade-gate.sh: called from an app's prepare.sh, for images whose upgrade
# changes the data one way (a database schema, a search index format).
#
#   upgrade-gate.sh <app dir> <DATA_DIR> <existing data> <KEY> <image> [major]
#
# <existing data> is a path under DATA_DIR that only exists once the app has
# run. Without it (a fresh install) the gate is open, and the pinned version is
# recorded beside it in .upgrade-gate-KEY. With it, the gate opens when that
# record matches the version this app's compose file pins (a redeploy), or
# when .env.local has KEY=<that version>: the owner's note that the backup and
# the steps in docs/image-upgrades.md were done for it, after which the record
# is updated. A later bump, a Dependabot PR included, changes the pinned
# version, so the gate closes again until that one is acknowledged.
#
# The version is the tag without a leading v or a -variant suffix
# (v1.41.0 -> 1.41.0, 6.16-alpine -> 6.16). `major` compares only the first
# number, for apps where the reviewed gate is per major (OpenCloud).
#
# Direct `docker compose` bypasses this, as it bypasses every compose.sh check.
set -euo pipefail

app_dir="${1:?usage: upgrade-gate.sh <app dir> <DATA_DIR> <existing data> <KEY> <image> [major]}"
data_dir="${2:?DATA_DIR required}"
existing="${3:?existing data path required}"
key="${4:?KEY required}"
image="${5:?image repository required}"
part="${6:-full}"

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
load_node "$app_dir/.."

tag="$(sed -nE "s|^[[:space:]]*image:[[:space:]]*${image//./\\.}:([^@[:space:]]+).*|\1|p" \
  "$app_dir/docker-compose.yml" | head -n1)"
[[ -n "$tag" ]] || die "$(basename "$app_dir"): no $image image in docker-compose.yml."
version="${tag#v}"
version="${version%%-*}"
[[ "$part" != major ]] || version="${version%%.*}"

SUDO=()
[[ $EUID -eq 0 ]] || SUDO=(sudo)

# The version the data is on, kept next to it (so it's in the app's backup and
# comes back with a restore). Written on a fresh install and after an
# acknowledged upgrade; a redeploy of that same version then needs nothing.
marker="$(dirname "$data_dir/$existing")/.upgrade-gate-$key"
record() {
  "${SUDO[@]}" test -d "$(dirname "$marker")" || return 0
  printf '%s\n' "$version" | "${SUDO[@]}" tee "$marker" >/dev/null
}

# The data is often owned by the container's user, so the check goes through sudo.
if ! "${SUDO[@]}" test -e "$data_dir/$existing"; then
  record   # fresh install: the data this creates will be on $version
  exit 0
fi

installed="$("${SUDO[@]}" cat "$marker" 2>/dev/null || true)"
[[ "$installed" == "$version" ]] && exit 0

acknowledged="$(env_value "$key")"
[[ "$acknowledged" == "$version" ]] || die \
  "$(basename "$app_dir"): existing data (on ${installed:-an unrecorded version}) and a new $image version ($version; acknowledged: ${acknowledged:-none}). Follow docs/image-upgrades.md, then put $key=$version in $NODE_NAME's .env.local."
record
