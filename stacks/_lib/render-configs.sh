#!/usr/bin/env bash
# Shared renderer. Each app gets a fresh shell, root/node/app env precedence,
# validation, private permissions and atomic replacement of its output.
set -uo pipefail
DIR="$(cd "${1:?node directory required}" && pwd)"
ROOT="$(cd "$DIR/../.." && pwd)"
[[ $EUID -ne 0 ]] || { echo 'Run as the ops user, not sudo.' >&2; exit 1; }
command -v python3 >/dev/null || { echo 'python3 is required.' >&2; exit 1; }
case "$(basename "$DIR")" in
  sieve|mochaPot)
    bash "$ROOT/stacks/_lib/refresh-dns.sh" "$(basename "$DIR")" || exit 1
    ;;
esac
failed=0; count=0
while IFS= read -r tpl; do
  count=$((count + 1))
  relative="${tpl#"$DIR"/}"
  app_dir="$DIR/${relative%%/*}"
  if (
    set -e
    set -a
    for env_file in "$ROOT/.env" "$DIR/.env.local" "$app_dir/secrets.env.local"; do
      if [[ -f "$env_file" ]]; then
        source "$env_file" || { echo "Cannot load $env_file" >&2; exit 1; }
      fi
    done
    set +a
    python3 "$ROOT/stacks/_lib/render-template.py" "$tpl"
  ); then
    echo "Rendered: ${tpl#"$DIR"/}"
  else
    echo "FAILED: ${tpl#"$DIR"/}" >&2
    failed=$((failed + 1))
  fi
done < <(find "$DIR" -name '*.template' -type f | sort)
echo "render-configs.sh: $count template(s), $failed failure(s)."
[[ $failed -eq 0 ]]
