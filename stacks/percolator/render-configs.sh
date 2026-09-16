#!/usr/bin/env bash
#
# render-configs.sh — render every <app>/config/*.template into the file next
# to it (config/traefik.yml.template → config/traefik.yml).
#
# Variables come from /opt/purrbrews/.env, this node's .env.local and the
# app's own secrets.env.local, in that order. Rendered files hold the real
# domain and secrets, are gitignored, and are written 0600 unless the
# template's first line says `# render-mode: 0644` (for images that read
# their config as a non-root user; such templates must not contain secrets).
#
# Safety:
#   - A template that references a variable which is unset or empty is NOT
#     rendered: envsubst would silently substitute "" and exit 0.
#   - One failing template does not stop the others; every failure is listed
#     at the end and the script exits non-zero. Always read to the end.
#   - Each template renders in its own subshell, so one app's secrets never
#     leak into another app's config.
#
# Re-run after any change to .env.local, a secrets.env.local or a template.
# Never edit a rendered file; edit the .template.
#
set -uo pipefail   # no -e: failures are collected, not fatal

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_ENV="$(cd "${DIR}/../.." && pwd)/.env"

command -v envsubst >/dev/null 2>&1 || { echo "envsubst not found — sudo apt-get install gettext-base" >&2; exit 1; }
[[ $EUID -ne 0 ]] || { echo "Don't run this under sudo: rendered files would become root-owned." >&2; exit 1; }

FAILED=()
COUNT=0

render_one() {
  local tpl="$1" out="${1%.template}" app_dir rel missing=() var mode tmp
  app_dir="$(dirname "$(dirname "$tpl")")"
  rel="${out#"$DIR"/}"

  set -a
  # shellcheck disable=SC1090
  [[ -f "$ROOT_ENV" ]] && { source "$ROOT_ENV" || { echo "FAILED: ${rel} — cannot source ${ROOT_ENV}" >&2; return 1; }; }
  # shellcheck disable=SC1091
  [[ -f "${DIR}/.env.local" ]] && { source "${DIR}/.env.local" || { echo "FAILED: ${rel} — cannot source .env.local" >&2; return 1; }; }
  if [[ -f "${app_dir}/secrets.env.local" ]]; then
    # shellcheck disable=SC1091
    source "${app_dir}/secrets.env.local" \
      || { echo "FAILED: ${rel} — cannot source ${app_dir#"$DIR"/}/secrets.env.local (check owner/permissions and 'bash -n')" >&2; return 1; }
  fi
  set +a

  while IFS= read -r var; do
    [[ -n "${!var:-}" ]] || missing+=("$var")
  done < <(envsubst --variables "$(cat "$tpl")" | sort -u)
  if [[ ${#missing[@]} -gt 0 ]]; then
    echo "FAILED: ${rel} — unset or empty: ${missing[*]}" >&2
    return 1
  fi

  mode=600
  head -n1 "$tpl" | grep -qE '^#[[:space:]]*render-mode:[[:space:]]*0?644' && mode=644

  tmp="$(mktemp "${out}.XXXXXX")" || { echo "FAILED: ${rel} — cannot write next to it" >&2; return 1; }
  chmod "$mode" "$tmp"
  if envsubst < "$tpl" > "$tmp"; then
    mv -f "$tmp" "$out"
    echo "Rendered: ${rel} (${mode})"
  else
    rm -f "$tmp"
    echo "FAILED: ${rel} — envsubst error" >&2
    return 1
  fi
}

while IFS= read -r tpl; do
  COUNT=$((COUNT + 1))
  ( render_one "$tpl" ) || FAILED+=("${tpl#"$DIR"/}")
done < <(find "$DIR" -path '*/config/*.template' | sort)

echo
if [[ ${#FAILED[@]} -gt 0 ]]; then
  echo "render-configs.sh: ${#FAILED[@]} of ${COUNT} template(s) FAILED:" >&2
  printf '  - %s\n' "${FAILED[@]}" >&2
  exit 1
fi
echo "render-configs.sh: all ${COUNT} template(s) rendered."
