#!/usr/bin/env bash
#
# firewall.sh: a node's UFW rules, built from each app's <app>/firewall file.
# Every node's ./firewall.sh calls this with its own directory.
#
#   sudo ./firewall.sh             apply
#   ./firewall.sh --dry-run        print the ufw commands instead
#
# init/purrbrews-init.sh already set deny-incoming, SSH from the LAN and
# ufw-docker. UFW skips a rule it already has, so re-running only adds what's
# new. Nothing here deletes a rule; if an app goes away, remove its rules with
# `sudo ufw status numbered` and `sudo ufw delete <n>`.
#
# <app>/firewall, one rule per line:
#
#   <allow|route> <tcp|udp> <port> <from> [<to>]   # <label>
#
#   allow   host-networked apps; the traffic hits the INPUT chain
#   route   published container ports; Docker DNATs them through FORWARD,
#           which plain `ufw allow` never sees (ufw-docker's `route` rules)
#   from/to LAN      this node's LAN_CIDR
#           NETWORK  the subnet of node.conf's NETWORK (host-networked apps
#                    see Traefik's proxied requests coming from there)
#           $KEY     any setting; a space-separated list gives one rule each
#           any, or a literal address/CIDR
#   to defaults to any. Rules are tagged "purrbrews <node>: <label>".
#
set -Eeuo pipefail
# shellcheck source=common.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

load_node "${1:?usage: firewall.sh <node dir> [--dry-run]}"
shift
DRY=0
[[ "${1:-}" == --dry-run ]] && DRY=1
[[ $DRY -eq 1 || $EUID -eq 0 ]] || die "run with sudo (or --dry-run)."
[[ -f "$ENV_LOCAL" ]] || die ".env.local is missing; run ./setup-secrets.sh first."
[[ $DRY -eq 1 ]] || command -v ufw >/dev/null || die "ufw isn't installed; init's firewall step does that."

network_subnet() {
  # NETWORK_SUBNET in the environment wins, so --dry-run works on a machine
  # without Docker (the tests use that).
  local subnet="${NETWORK_SUBNET:-}"
  [[ -n "$subnet" || -z "$NETWORK_SUBNET_KEY" ]] || subnet="$(env_value "$NETWORK_SUBNET_KEY")"
  if [[ -z "$subnet" && -n "$NETWORK" ]]; then
    subnet="$(docker network inspect "$NETWORK" --format '{{range .IPAM.Config}}{{println .Subnet}}{{end}}' 2>/dev/null | grep -v : | head -n1)" || true
  fi
  [[ -n "$subnet" ]] || die "can't work out $NETWORK's subnet; bring an app up first, or set NETWORK_SUBNET."
  printf '%s' "$subnet"
}

resolve() {  # resolve <token>: prints one address per line
  local token="$1" value
  case "$token" in
    any)     echo any; return ;;
    LAN)     value="$(env_value LAN_CIDR)" ;;
    NETWORK) value="$(network_subnet)" ;;
    \$*)     value="$(env_value "${token#\$}")" ;;
    *)       value="$token" ;;
  esac
  is_placeholder "$value" && die "'$token' has no value; check .env.local."
  for value in $value; do
    [[ "$value" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}(/[0-9]{1,2})?$ ]] || die "'$token' gave '$value', which isn't an address."
    echo "$value"
  done
}

rule() {  # rule <label> <ufw args...>
  local comment="purrbrews $NODE_NAME: $1"; shift
  if [[ $DRY -eq 1 ]]; then
    printf 'ufw %s comment %q\n' "$*" "$comment"
  else
    printf '%-52s ' "$comment"
    ufw "$@" comment "$comment"
  fi
}

total=0
for app in "${APPS[@]}"; do
  spec="$NODE_DIR/$app/firewall"
  [[ -f "$spec" ]] || continue
  while IFS= read -r line; do
    label="${line#*#}"; label="${label# }"
    [[ "$line" == *#* ]] || label=''
    line="${line%%#*}"
    read -r action proto port from to _ <<< "$line"
    [[ -n "${action:-}" ]] || continue
    [[ "$action" == allow || "$action" == route ]] || die "$app/firewall: '$action' should be allow or route."
    [[ "$proto" == tcp || "$proto" == udp ]] || die "$app/firewall: '$proto' should be tcp or udp."
    [[ -n "$label" ]] || die "$app/firewall: every rule needs a '# label'."
    # Resolved in a plain assignment so a bad token stops the whole run.
    resolved_from="$(resolve "$from")"
    resolved_to="$(resolve "${to:-any}")"
    mapfile -t sources <<< "$resolved_from"
    mapfile -t targets <<< "$resolved_to"
    for src in "${sources[@]}"; do
      for dst in "${targets[@]}"; do
        tag="$label"
        [[ ${#sources[@]} -gt 1 ]] && tag="$label from $src"
        if [[ "$action" == route ]]; then
          rule "$tag" route allow proto "$proto" from "$src" to "$dst" port "$port"
        else
          rule "$tag" allow proto "$proto" from "$src" to "$dst" port "$port"
        fi
        total=$((total + 1))
      done
    done
  done < "$spec"
done

[[ $total -gt 0 ]] || { note "no app on $NODE_NAME asks for a firewall rule."; exit 0; }
if [[ $DRY -eq 0 ]]; then
  ufw reload >/dev/null
  echo
  ufw status numbered | grep -E "purrbrews $NODE_NAME|Status"
fi
