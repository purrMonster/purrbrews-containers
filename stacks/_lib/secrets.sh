# shellcheck shell=bash
# shellcheck disable=SC2034,SC2016  # SECRETS_FAILED is read by setup.sh; the $ in the grep patterns is literal
#
# secrets.sh: sourced by setup.sh. Reads each app's <app>/secrets.conf and
# fills in <app>/secrets.env.local (mode 600, gitignored) on the node.
#
# secrets.conf is one line per key:
#
#   KEY  hex <chars> [prefix]      random hex. The default for anything that
#                                  might end up in a URL or an auth header:
#                                  base64's + / = broke Mealie's OIDC login once
#   KEY  base64 <bytes> [prefix]   only where the app insists (Laravel's APP_KEY)
#   KEY  value [literal]           a fixed default (a username, a db name)
#   KEY  prompt [optional] <text>  asked for, input hidden. Blank keeps
#                                  REPLACE_ME (or empty, if optional) and it's
#                                  asked again next run
#   KEY  copy <app> <KEY>          taken from another app on this node, once
#   KEY  mirror <app> <KEY>        same, but re-copied on every run
#   KEY  hash <pbkdf2|argon2|bcrypt> [<app>:]<KEY>
#                                  hash of another value, made with the app's
#                                  own image so the format is what it expects
#   KEY  rsa <bits>                PEM private key on one line, \n escaped
#   NOTE <text>                    printed in the summary at the end
#
# Nothing that already has a real value is ever regenerated (mirror aside).
# To rotate one, delete its line and re-run; for a hash, delete the hash too.
#
# An app with something too odd for this format can add <app>/secrets.hook,
# which is sourced afterwards with FILE pointing at its secrets file and the
# helpers below in scope (sieve's ntfy builds its user lists that way).

declare -A SECRETS_DONE=()
SECRETS_NOTES=()
SECRETS_FAILED=0

secret_file() { printf '%s/%s/secrets.env.local' "$NODE_DIR" "$1"; }
secret_get()  { env_get "$(secret_file "$1")" "$2"; }
secret_set()  { local v; v="$(secret_get "$1" "$2")"; ! is_placeholder "$v"; }

image_of() {  # image_of <image prefix>: the tag this node's compose files pin
  grep -rhoE "image: *${1}:[^ \"#]+" "$NODE_DIR"/*/docker-compose.yml 2>/dev/null \
    | head -n1 | sed -E 's/image: *//'
}

make_hash() {  # make_hash <pbkdf2|argon2|bcrypt> <plaintext>: prints the digest, or nothing
  local scheme="$1" plain="$2" image
  case "$scheme" in
    pbkdf2|argon2)
      image="$(image_of authelia/authelia)"
      [[ -n "$image" ]] || { warn "no authelia image on this node to hash with"; return 0; }
      "${DOCKER[@]}" run --rm "$image" authelia crypto hash generate "$scheme" --password "$plain" 2>/dev/null \
        | grep -oE '\$(pbkdf2-sha512|argon2id)\$[^[:space:]]+' | head -n1 || true
      ;;
    bcrypt)
      image="$(image_of binwiederhier/ntfy)"
      [[ -n "$image" ]] || { warn "no ntfy image on this node to hash with"; return 0; }
      printf '%s\n%s\n' "$plain" "$plain" \
        | "${DOCKER[@]}" run --rm -i "$image" user hash 2>/dev/null \
        | grep -oE '\$2[aby]\$[0-9]{2}\$[./A-Za-z0-9]{53}' | head -n1 || true
      ;;
    *) die "unknown hash scheme: $scheme" ;;
  esac
}

ask() {  # ask <text>: hidden input, empty without a terminal
  local value=''
  if [[ -t 0 ]]; then
    read -r -s -p "  $1: " value
    printf '\n'
  fi
  printf '%s' "$value"
}

apply_secret() {  # apply_secret <app> <KEY> <kind> [args...]
  local app="$1" key="$2" kind="$3"; shift 3
  local file current src_app src_key value
  file="$(secret_file "$app")"
  current="$(env_get "$file" "$key")"

  case "$kind" in
    hex)
      is_placeholder "$current" || return 0
      value="$(openssl rand -hex "$(( ($1 + 1) / 2 ))" | cut -c1-"$1")"
      env_put "$file" "$key" "${2:-}${value}"
      ;;
    base64)
      is_placeholder "$current" || return 0
      env_put "$file" "$key" "${2:-}$(openssl rand -base64 "$1")"
      ;;
    value)
      env_has "$file" "$key" || env_put "$file" "$key" "$*"
      ;;
    prompt)
      local optional=0 placeholder=REPLACE_ME
      if [[ "${1:-}" == optional ]]; then optional=1; placeholder=''; shift; fi
      # An optional key that's been answered (even with nothing) stays answered.
      if [[ $optional -eq 1 ]] && env_has "$file" "$key" && [[ "$current" != *REPLACE_ME* ]]; then return 0; fi
      [[ $optional -eq 0 ]] && ! is_placeholder "$current" && return 0
      value="$(ask "$*")"
      if [[ -z "$value" ]]; then
        [[ -t 0 && $optional -eq 0 ]] && note "(skipped; run ./setup-secrets.sh again once you have it)"
        value="$placeholder"
      fi
      env_put "$file" "$key" "$value"
      ;;
    copy|mirror)
      src_app="$1"; src_key="$2"
      [[ "$kind" == copy ]] && ! is_placeholder "$current" && return 0
      ensure_app_secrets "$src_app"
      value="$(secret_get "$src_app" "$src_key")"
      is_placeholder "$value" && return 0
      [[ "$value" == "$current" ]] || env_put "$file" "$key" "$value"
      ;;
    hash)
      is_placeholder "$current" || return 0
      src_app="$app"; src_key="$2"
      if [[ "$src_key" == *:* ]]; then src_app="${src_key%%:*}"; src_key="${src_key#*:}"; fi
      [[ "$src_app" == "$app" ]] || ensure_app_secrets "$src_app"
      local plain; plain="$(secret_get "$src_app" "$src_key")"
      is_placeholder "$plain" && return 0
      note "hashing $key ($1, with docker)…"
      value="$(make_hash "$1" "$plain")"
      if [[ -z "$value" ]]; then
        warn "couldn't hash $key; is Docker running and can it pull the image? Run setup again later."
        SECRETS_FAILED=1
        return 0
      fi
      env_put "$file" "$key" "$value"
      ;;
    rsa)
      is_placeholder "$current" || return 0
      # One line with literal \n: the renderer knows nothing about YAML
      # indentation, so the key lands in a double-quoted YAML string that
      # turns the \n back into newlines.
      value="$(openssl genpkey -algorithm RSA -pkeyopt "rsa_keygen_bits:${1:-2048}" 2>/dev/null | sed ':a;N;$!ba;s/\n/\\n/g')"
      [[ "$value" == -----BEGIN* ]] || die "openssl genpkey failed for $key."
      env_put "$file" "$key" "$value"
      ;;
    *) die "$app/secrets.conf: unknown kind '$kind' for $key" ;;
  esac
}

ensure_app_secrets() {  # ensure_app_secrets <app>: once per run, dependencies first
  local app="$1" spec key kind rest
  [[ -n "${SECRETS_DONE[$app]:-}" ]] && return 0
  SECRETS_DONE[$app]=1
  spec="$NODE_DIR/$app/secrets.conf"
  [[ -f "$spec" || -f "$NODE_DIR/$app/secrets.hook" ]] || return 0

  local file; file="$(secret_file "$app")"
  (umask 077 && touch "$file")
  chmod 600 "$file"

  if [[ -f "$spec" ]]; then
    # Read the whole spec first: prompts need stdin to still be the terminal.
    local -a lines args
    local line
    mapfile -t lines < "$spec"
    for line in "${lines[@]}"; do
      read -r key kind rest <<< "$line"
      [[ -z "$key" || "$key" == \#* ]] && continue
      if [[ "$key" == NOTE ]]; then
        SECRETS_NOTES+=("$app: $kind${rest:+ $rest}")
        continue
      fi
      # read -a splits on spaces without glob-expanding a stray * in prompt text.
      read -r -a args <<< "$rest"
      apply_secret "$app" "$key" "$kind" "${args[@]}"
    done
  fi

  if [[ -f "$NODE_DIR/$app/secrets.hook" ]]; then
    # shellcheck disable=SC2034  # FILE is for the hook
    FILE="$file"
    # shellcheck source=/dev/null
    source "$NODE_DIR/$app/secrets.hook"
  fi
}

generate_secrets() {
  local app
  local dir
  for app in "${APPS[@]}"; do ensure_app_secrets "$app"; done
  # Then any other folder with a secrets.conf: host-side tools like cellar's
  # restic, and an app that hasn't made it into node.conf yet.
  for dir in "$NODE_DIR"/*/; do
    [[ -f "${dir}secrets.conf" || -f "${dir}secrets.hook" ]] && ensure_app_secrets "$(basename "$dir")"
  done
  return 0
}
