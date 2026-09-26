#!/usr/bin/env bash
#
# lldap-bootstrap.sh: make sure LLDAP has the fleet's groups and that the
# given users are in them. Safe to re-run; every step checks first.
#
#   ./lldap-bootstrap.sh [--dry-run] [user ...]      (default user: barista)
#
# Ensures:
#   - groups LLDAP_ADMIN_GROUP and LLDAP_HOUSEHOLD_GROUP exist (.env.local);
#   - each named user exists and is in both groups. A missing user is created
#     with a random password that is printed once: have them change it at
#     https://lldap.${DOMAIN} (or reset it through Authelia).
#
# Add household members as `./lldap-bootstrap.sh <user>` and then remove them
# from the admin group in the LLDAP UI, or create them in the UI directly and
# add them to LLDAP_HOUSEHOLD_GROUP.
#
# Talks to LLDAP's GraphQL API on 127.0.0.1:17170 (published to loopback
# only), so it works even when Traefik or Authelia is down.
#
# shellcheck disable=SC2016  # GraphQL $variables are literal
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LLDAP_URL="http://127.0.0.1:17170"

DRY_RUN=0
USERS=()
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    -h|--help) sed -n '3,19p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) [[ "$arg" =~ ^[a-z0-9._-]+$ ]] || { echo "bad user name: $arg" >&2; exit 1; }; USERS+=("$arg") ;;
  esac
done
[[ ${#USERS[@]} -gt 0 ]] || USERS=(barista)

# shellcheck source=../_lib/common.sh
source "${DIR}/../_lib/common.sh"
command -v jq >/dev/null || die "jq not found (sudo apt-get install jq)"

ADMIN_GROUP="$(env_get "${DIR}/.env.local" LLDAP_ADMIN_GROUP)"
HOUSEHOLD_GROUP="$(env_get "${DIR}/.env.local" LLDAP_HOUSEHOLD_GROUP)"
DOMAIN="$(env_get "${DIR}/.env.local" DOMAIN)"
ADMIN_PASSWORD="$(env_get "${DIR}/lldap/secrets.env.local" LLDAP_ADMIN_PASSWORD)"
[[ -n "$ADMIN_GROUP" && -n "$HOUSEHOLD_GROUP" ]] || die "LLDAP_ADMIN_GROUP / LLDAP_HOUSEHOLD_GROUP missing from .env.local"
[[ -n "$ADMIN_PASSWORD" ]] || die "LLDAP_ADMIN_PASSWORD missing — run ./setup-secrets.sh"

[[ "$DRY_RUN" -eq 1 ]] && log "DRY RUN — reads are real, nothing is changed"

# graphql <query> [variables-json]
graphql() {
  local body response vars="${2:-}"
  [[ -n "$vars" ]] || vars='{}'
  body="$(jq -n --arg q "$1" --argjson v "$vars" '{query: $q, variables: $v}')"
  response="$(curl -fsS -X POST "${LLDAP_URL}/api/graphql" \
    -H "Authorization: Bearer ${TOKEN}" -H "Content-Type: application/json" -d "$body")" \
    || die "GraphQL request failed"
  if jq -e '.errors' >/dev/null <<<"$response"; then
    jq '.errors' <<<"$response" >&2
    return 1
  fi
  printf '%s' "$response"
}

log "Logging in to LLDAP as admin"
TOKEN="$(curl -fsS -X POST "${LLDAP_URL}/auth/simple/login" -H "Content-Type: application/json" \
  -d "$(jq -n --arg p "$ADMIN_PASSWORD" '{username: "admin", password: $p}')" | jq -r '.token // empty')" \
  || die "cannot reach LLDAP at ${LLDAP_URL} — is it up? (./compose.sh lldap up -d)"
[[ -n "$TOKEN" ]] || die "LLDAP login failed — does LLDAP_ADMIN_PASSWORD match the one LLDAP was first started with?"

ensure_group() {
  local name="$1" id
  id="$(graphql 'query { groups { id displayName } }' | jq -r --arg n "$name" '.data.groups[] | select(.displayName == $n) | .id')"
  if [[ -n "$id" ]]; then
    echo "  group ${name}: exists (id ${id})" >&2
  elif [[ "$DRY_RUN" -eq 1 ]]; then
    echo "  group ${name}: would create" >&2
  else
    id="$(graphql 'mutation($n: String!) { createGroup(name: $n) { id } }' "$(jq -n --arg n "$name" '{n: $n}')" | jq -r '.data.createGroup.id')"
    echo "  group ${name}: created (id ${id})" >&2
  fi
  printf '%s' "$id"
}

log "Groups"
ADMIN_GID="$(ensure_group "$ADMIN_GROUP")"
HOUSEHOLD_GID="$(ensure_group "$HOUSEHOLD_GROUP")"

for user in "${USERS[@]}"; do
  log "User ${user}"
  if ! info="$(graphql 'query($u: String!) { user(userId: $u) { id groups { id } } }' "$(jq -n --arg u "$user" '{u: $u}')" 2>/dev/null)"; then
    if [[ "$DRY_RUN" -eq 1 ]]; then
      echo "  would create ${user} with a random password"
      continue
    fi
    password="$(openssl rand -hex 12)"
    graphql 'mutation($u: CreateUserInput!) { createUser(user: $u) { id } }' \
      "$(jq -n --arg id "$user" --arg mail "${user}@${DOMAIN}" '{u: {id: $id, email: $mail, displayName: $id}}')" >/dev/null \
      || die "createUser failed"
    # LLDAP sets passwords over its OPAQUE protocol, which the bundled tool speaks.
    sudo docker exec lldap /app/lldap_set_password --base-url http://localhost:17170 \
      --admin-username admin --admin-password "$ADMIN_PASSWORD" --username "$user" --password "$password" >/dev/null \
      || die "setting the password failed — set one in the LLDAP UI instead"
    echo "  created ${user}, email ${user}@${DOMAIN} — one-time password: ${password}"
    echo "  (change the email in the LLDAP UI if that address isn't real; password resets are sent there)"
    info='{"data":{"user":{"groups":[]}}}'
  fi
  for gid in "$ADMIN_GID" "$HOUSEHOLD_GID"; do
    if [[ -z "$gid" ]]; then
      echo "  would add to the group created above"
    elif jq -e --arg g "$gid" '.data.user.groups[] | select((.id|tostring) == $g)' >/dev/null <<<"$info"; then
      echo "  already in group ${gid}"
    elif [[ "$DRY_RUN" -eq 1 ]]; then
      echo "  would add to group ${gid}"
    else
      graphql 'mutation($u: String!, $g: Int!) { addUserToGroup(userId: $u, groupId: $g) { ok } }' \
        "$(jq -n --arg u "$user" --argjson g "$gid" '{u: $u, g: $g}')" >/dev/null || die "addUserToGroup failed"
      echo "  added to group ${gid}"
    fi
  done
done

log "Done"
