#!/usr/bin/env bash
#
# upgrade-gate.sh: called from an app's prepare.sh, for images whose upgrade
# changes the data one way (a database schema, a search index format).
#
#   upgrade-gate.sh <app dir> <DATA_DIR> <existing data> <KEY> <image> [major]
#
# <existing data> is a path under DATA_DIR that only exists once the app has
# run. Without it (a fresh install) the gate is open. With it, the gate opens
# only when .env.local has KEY=<the version this app's compose file pins>: the
# owner's note that the backup and the steps in docs/image-upgrades.md were
# done for that version. A later bump, a Dependabot PR included, changes the
# pinned version, so the gate closes again until that one is acknowledged.
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
# The data is often owned by the container's user, so the check goes through sudo.
if ! "${SUDO[@]}" test -e "$data_dir/$existing"; then
  exit 0
fi

acknowledged="$(env_value "$key")"
[[ "$acknowledged" == "$version" ]] || die \
  "$(basename "$app_dir"): existing data and a new $image version ($version; acknowledged: ${acknowledged:-none}). Follow docs/image-upgrades.md, then put $key=$version in $NODE_NAME's .env.local."
