#!/usr/bin/env bash
#
# render-configs.sh: turn every *.template under a node into the file next to
# it (config.yml.template -> config.yml). Every node's ./render-configs.sh
# calls this with its own directory.
#
# Each app renders in its own subshell with the same env files compose.sh
# uses (fleet.env, /opt/purrbrews/.env, .env.local, the app's secrets), so one
# app's secrets never leak into another app's config. A template with an
# unset or REPLACE_ME variable fails and the old rendered file stays as it
# was; the others still render. Output is written atomically, mode 600 unless
# the template's first line is `# render-mode: 0644`.
#
# On a node with RESOLVER set in node.conf (the two Pi-holes), the local DNS
# records are regenerated first, since a new route anywhere in the fleet
# needs a record on both.
#
set -uo pipefail
# shellcheck source=common.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

load_node "${1:?usage: render-configs.sh <node dir>}"
not_root
command -v python3 >/dev/null || die "python3 is required."

if [[ -n "$RESOLVER" ]]; then
  bash "$LIB/refresh-dns.sh" "$NODE_DIR" || exit 1
fi

failed=0; count=0
while IFS= read -r tpl; do
  count=$((count + 1))
  relative="${tpl#"$NODE_DIR"/}"
  app_dir="$NODE_DIR/${relative%%/*}"
  if (
    set -e
    set -a
    for env_file in "${ENV_FILES[@]}" "$app_dir/secrets.env.local"; do
      if [[ -f "$env_file" ]]; then
        # shellcheck source=/dev/null
        source "$env_file" || { echo "Cannot load $env_file" >&2; exit 1; }
      fi
    done
    set +a
    python3 "$LIB/render-template.py" "$tpl"
  ); then
    echo "Rendered: $relative"
  else
    echo "FAILED: $relative" >&2
    failed=$((failed + 1))
  fi
done < <(find "$NODE_DIR" -name '*.template' -type f | sort)

echo "render-configs.sh: $count template(s), $failed failure(s)."
[[ $failed -eq 0 ]]
