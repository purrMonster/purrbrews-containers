#!/usr/bin/env bash
#
# firewall.sh — cellar's UFW rules, as code. Idempotent; run after init and
# after any change here:   sudo ./firewall.sh        (--dry-run to print only)
#
# init/purrbrews-init.sh already set: deny incoming, SSH from the LAN,
# ufw-docker. UFW skips rules that already exist, so re-running only adds
# what's new. Rules are tagged "purrbrews cellar:"; see them with
# sudo ufw status numbered.
#
# Added 2026-09-16 alongside cellar's own Traefik -- this stack previously
# shipped with no firewall.sh at all (see README "Known gaps" before this
# date), leaving komodo's 9120 and scrutiny's 8080 reachable from the LAN
# with a plain (and, per infrastructure.md §5/§9, non-functional) ufw
# rule at best. All three of cellar's published ports go through the
# FORWARD chain (Docker's iptables DNAT bypasses plain ufw for any
# published bridge-network port), so they need `ufw route allow`
# (ufw-docker), not plain `ufw allow`. cellar has no host-networked app,
# so there is no `ufw allow` rule in this file at all.
#
set -Eeuo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DRY=0; [[ "${1:-}" == "--dry-run" ]] && DRY=1
[[ $DRY -eq 1 || $EUID -eq 0 ]] || { echo "Run with sudo (or --dry-run)." >&2; exit 1; }

get() { local l; l="$(grep -E "^$1=" "${DIR}/.env.local" | tail -n1 || true)"; l="${l#*=}"; l="${l#\'}"; printf '%s' "${l%\'}"; }
[[ -f "${DIR}/.env.local" ]] || { echo ".env.local missing — run ./setup-secrets.sh first." >&2; exit 1; }

LAN_CIDR="$(get LAN_CIDR)"
[[ -n "$LAN_CIDR" && "$LAN_CIDR" != *REPLACE_ME* ]] || { echo "LAN_CIDR is not set in .env.local." >&2; exit 1; }

rule() {  # rule <comment> <ufw args...>
  local comment="purrbrews cellar: $1"; shift
  if [[ $DRY -eq 1 ]]; then
    printf 'ufw %s comment %q\n' "$*" "$comment"
  else
    printf '%-44s ' "$comment"; ufw "$@" comment "$comment"
  fi
}

# ── Traefik (published 80, 443) ──────────────────────────────────────────────
rule "traefik http from LAN"  route allow proto tcp from "$LAN_CIDR" to any port 80
rule "traefik https from LAN" route allow proto tcp from "$LAN_CIDR" to any port 443

# ── Komodo Core (published 9120) ─────────────────────────────────────────────
# Must stay reachable from the whole LAN, not just Traefik's path -- every
# other node's Periphery agent dials in on this port directly (Docker
# networks don't span physical hosts). See komodo/docker-compose.yml's own
# comment: this port's real security boundary is KOMODO_JWT_SECRET/
# KOMODO_WEBHOOK_SECRET/the admin account, not this rule.
rule "komodo core from LAN"   route allow proto tcp from "$LAN_CIDR" to any port 9120

# ── Scrutiny hub (published 8080) ────────────────────────────────────────────
# Same reasoning as komodo above -- every other node's scrutiny-collector
# pushes here directly over the LAN, not through Traefik.
rule "scrutiny hub from LAN"  route allow proto tcp from "$LAN_CIDR" to any port 8080

[[ $DRY -eq 1 ]] || { ufw reload >/dev/null; echo; ufw status numbered | grep -E 'purrbrews cellar|Status'; }
