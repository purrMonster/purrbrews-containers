#!/usr/bin/env bash
#
# purrbrews-node.sh — the fleet's bootstrap payload: turns a machine that
# purrbrews-bootstrap has just set up into a fleet node.
#
# purrbrews-bootstrap does the general part (packages, the ops user, SSH keys
# and their sync, key-only SSH, no sleep, journald, Docker, UFW). It then
# downloads payload/ from the server, checks it, and runs this script as root
# with what came after `--` on its command line:
#
#   curl … /bootstrap.sh | sudo bash -s -- --user barista --hostname sieve -- sieve
#
# Steps, in order. Every one is safe to run again:
#
#   packages   NetworkManager, for the static address with rollback
#   repo       clone this repo to PROJECT_DIR as the ops user (a re-run only
#              fetches: a node's checkout moves by hand, docs/operations.md)
#   node       check the node exists in the checkout (nodes/<node>/node.conf)
#   folders    DATA_DIR, MEDIA_DIR, /etc/purrbrews, and PROJECT_DIR/.env (NODE,
#              NODE_IP, TZ, PUID/PGID, the folders), which stacks/_lib reads
#   hosts      every other node's name in /etc/hosts
#   timers     the daily fetch (purrbrews-pull.timer); it never moves the checkout
#   tailnet    only when named (--only tailnet): Tailscale, joined with the
#              fleet's tag; SSH over it through UFW, and on the subnet routers
#              (TAILSCALE_SUBNET_ROUTERS) web and DNS onto the LAN. Phase 10 of
#              docs/migration-plan.md; tailscale/README.md
#   network    static address from stacks/fleet.env and the node's fixed MAC,
#              switched over detached with a rollback after ~60 s. Last, because
#              an SSH session drops when the address changes. Asks first (on
#              the terminal), or needs --yes
#
# Usage: purrbrews-node.sh [<node>] [--user NAME] [--yes] [--only "a b"] [--skip "a b"] [--list-steps]
#   <node>     a folder under nodes/ (case doesn't matter); default: the hostname
#   --user     the ops user; default: the one purrbrews-bootstrap manages
#
# Settings are in payload.env next to this file. Node addresses, gateway, LAN
# and timezone come from stacks/fleet.env in the checkout: one source for them.
#
# Root runs only files from the verified payload, never from the checkout,
# which the ops user can write to. From the checkout it only reads data.
#
set -Eeuo pipefail
export LC_ALL=C

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/node-mac.sh
source "$HERE/lib/node-mac.sh"
# shellcheck source=lib/fleet.sh
source "$HERE/lib/fleet.sh"

ALL_STEPS=(packages repo node folders hosts timers tailnet network)
# Steps that run only when --only names them: joining the tailnet needs the
# policy in the admin console first, and a sign-in or an auth key.
OPT_IN_STEPS=(tailnet)
SETTINGS="$HERE/payload.env"
# Where things go. Overridable for the tests only.
ETC_DIR="${PB_ETC_DIR:-/etc/purrbrews}"
LIB_DST="${PB_LIB_DST:-/usr/local/lib/purrbrews}"
LOG_DIR="${PB_LOG_DIR:-/var/log/purrbrews}"
HOSTS_FILE="${PB_HOSTS_FILE:-/etc/hosts}"
UNIT_DIR="${PB_UNIT_DIR:-/etc/systemd/system}"
SYSCTL_DIR="${PB_SYSCTL_DIR:-/etc/sysctl.d}"
BOOTSTRAP_CONF="${PB_BOOTSTRAP_CONF:-/etc/purrbrews-bootstrap/client.conf}"

CURRENT_STEP=start
WARNINGS=()
say()  { printf '\033[1;36m[purrbrews]\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m[purrbrews]\033[0m   %s\n' "$*"; }
warn() { printf '\033[1;33m[purrbrews] WARNING:\033[0m %s\n' "$*" >&2; WARNINGS+=("[$CURRENT_STEP] $*"); }
die()  { printf '\033[1;31m[purrbrews] ERROR:\033[0m [%s] %s\n' "$CURRENT_STEP" "$*" >&2; exit 1; }

have_tty() { { : < /dev/tty; } 2>/dev/null; }
confirm() {
  $AUTO_YES && return 0
  have_tty || { warn "No terminal to ask '$1': run it again with --yes to allow it."; return 1; }
  local reply
  read -r -p "$1 [y/N] " reply < /dev/tty
  [[ "$reply" =~ ^[Yy]$ ]]
}
as_ops() { runuser -u "$OPS_USER" -- env HOME="$(getent passwd "$OPS_USER" | cut -d: -f6)" "$@"; }

setting() {  # setting KEY [default]: payload.env, else the default
  local v; v="$(kv_get "$SETTINGS" "$1")"
  printf '%s' "${v:-${2:-}}"
}

load_settings() {
  REPO_URL="$(setting REPO_URL)"
  REPO_BRANCH="$(setting REPO_BRANCH main)"
  PROJECT_DIR="$(setting PROJECT_DIR /opt/purrbrews)"
  DATA_DIR="$(setting DATA_DIR /srv/data)"
  MEDIA_DIR="$(setting MEDIA_DIR /srv/media)"
  CLONE_MAC="$(setting CLONE_MAC true)"
  BOOTSTRAP_DNS="$(setting BOOTSTRAP_DNS "1.1.1.1 9.9.9.9")"
  PULL_SCHEDULE="$(setting PULL_SCHEDULE "*-*-* 06:15:00")"
  [[ "$REPO_URL" == https://* ]] || die "REPO_URL in payload.env must be an https URL, not '$REPO_URL'."
  [[ "$REPO_URL" != *@* ]] || die "REPO_URL has a credential in it; the repo is public, remove it."
  [[ "$CLONE_MAC" == true || "$CLONE_MAC" == false ]] || die "CLONE_MAC must be true or false."
  local d
  for d in "$PROJECT_DIR" "$DATA_DIR" "$MEDIA_DIR"; do
    [[ "$d" == /* && "$d" != */ && "$d" != *..* ]] || die "'$d' in payload.env must be an absolute folder path."
  done
}

# Read once the checkout exists (step node).
load_fleet() {
  local fleet="$PROJECT_DIR/stacks/fleet.env" name ip mac
  [[ -f "$fleet" ]] || die "$fleet is missing: is $PROJECT_DIR a checkout of this repo?"
  local given="$NODE"
  NODE="$(fleet_node "$PROJECT_DIR" "$given")" \
    || die "No node '$given' in $PROJECT_DIR/nodes (there: $(ls "$PROJECT_DIR/nodes" | tr '\n' ' '))."
  declare -gA FLEET_IP=() FLEET_MAC=()
  local list
  list="$(fleet_list "$PROJECT_DIR" "$SETTINGS")" || die "The fleet list in the checkout is broken (above)."
  while read -r name ip mac; do
    [[ -n "$name" ]] || continue
    FLEET_IP[$name]="$ip"; FLEET_MAC[$name]="$mac"
  done <<< "$list"
  NODE_IP="${FLEET_IP[$NODE]}"
  NODE_MAC="${FLEET_MAC[$NODE]}"
  GATEWAY="$(kv_get "$fleet" GATEWAY)"
  LAN_CIDR="$(kv_get "$fleet" LAN_CIDR)"
  TIMEZONE="$(kv_get "$fleet" TZ)"
  valid_ipv4 "$GATEWAY" || die "GATEWAY in stacks/fleet.env is '$GATEWAY', not an IPv4 address."
  [[ "$LAN_CIDR" =~ ^[0-9.]+/([0-9]{1,2})$ ]] || die "LAN_CIDR in stacks/fleet.env is '$LAN_CIDR', not a CIDR."
  PREFIX="${BASH_REMATCH[1]}"
  (( PREFIX >= 8 && PREFIX <= 30 )) || die "LAN_CIDR's prefix must be 8 to 30."
}

# ── Steps ────────────────────────────────────────────────────────────────────

step_packages() {
  if command -v nmcli >/dev/null; then ok "NetworkManager is installed"; return; fi
  DEBIAN_FRONTEND=noninteractive apt-get install -y -q network-manager >/dev/null
  ok "installed NetworkManager (it takes the interface over only in the network step)"
}

step_repo() {
  export GIT_TERMINAL_PROMPT=0
  git config --system --replace-all safe.directory "$PROJECT_DIR" "^${PROJECT_DIR}$"
  if [[ -d "$PROJECT_DIR/.git" ]]; then
    local origin; origin="$(as_ops git -C "$PROJECT_DIR" remote get-url origin 2>/dev/null || true)"
    [[ "$origin" == "$REPO_URL" ]] || warn "$PROJECT_DIR's origin is '$origin', payload.env says '$REPO_URL': left alone."
    if as_ops git -C "$PROJECT_DIR" fetch --quiet origin; then
      ok "$PROJECT_DIR fetched; the checkout stays at $(as_ops git -C "$PROJECT_DIR" rev-parse --short HEAD) (moving it is a reviewed step, docs/operations.md)"
    else
      warn "git fetch failed in $PROJECT_DIR; the checkout is unchanged."
    fi
    return
  fi
  if [[ -e "$PROJECT_DIR" && -n "$(ls -A "$PROJECT_DIR" 2>/dev/null)" ]]; then
    die "$PROJECT_DIR exists, isn't empty and isn't a git checkout. Move it aside and run this again."
  fi
  install -d -m 2775 -o "$OPS_USER" -g "$OPS_USER" "$PROJECT_DIR"
  as_ops git clone --quiet --branch "$REPO_BRANCH" "$REPO_URL" "$PROJECT_DIR" \
    || die "Couldn't clone $REPO_URL ($REPO_BRANCH)."
  ok "cloned $REPO_URL ($REPO_BRANCH) to $PROJECT_DIR"
}

step_node() {
  load_fleet
  local current; current="$(hostname -s)"
  [[ "${current,,}" == "${NODE,,}" ]] \
    || warn "This machine is called '$current', not '$NODE'. Pass --hostname $NODE to the bootstrap one-liner to rename it."
  ok "$NODE: $NODE_IP/$PREFIX via $GATEWAY, MAC $NODE_MAC$( [[ "$CLONE_MAC" == true ]] || echo ' (not cloned: CLONE_MAC=false)')"
}

# write_node_env <file> <uid> <gid>: the node-wide facts stacks/_lib reads.
write_node_env() {
  cat > "$1" <<EOF
# Written by payload/purrbrews-node.sh on every run. Do not edit, do not commit.
# Non-secret, node-wide values for the stacks (stacks/_lib/common.sh reads NODE).
NODE=${NODE}
NODE_IP=${NODE_IP}
TZ=${TIMEZONE}
PUID=${2}
PGID=${3}
PROJECT_DIR=${PROJECT_DIR}
DATA_DIR=${DATA_DIR}
MEDIA_DIR=${MEDIA_DIR}
EOF
  chmod 644 "$1"
}

step_folders() {
  [[ -n "${NODE_IP:-}" ]] || load_fleet
  install -d -m 2775 -o "$OPS_USER" -g "$OPS_USER" "$DATA_DIR" "$MEDIA_DIR"
  install -d -m 755 "$ETC_DIR"
  write_node_env "$PROJECT_DIR/.env" "$(id -u "$OPS_USER")" "$(id -g "$OPS_USER")"
  chown "$OPS_USER:$OPS_USER" "$PROJECT_DIR/.env"
  ok "$DATA_DIR, $MEDIA_DIR and $ETC_DIR exist; $PROJECT_DIR/.env says NODE=$NODE"
}

# write_hosts <file>: a marked block with every other node, replacing the last one.
write_hosts() {
  local begin="# >>> purrbrews fleet (managed by the bootstrap payload) >>>"
  local end="# <<< purrbrews fleet <<<" tmp n
  tmp="$(mktemp)"
  awk -v b="$begin" -v e="$end" '$0==b{s=1;next} $0==e{s=0;next} !s' "$1" > "$tmp"
  {
    printf '%s\n' "$begin"
    for n in "${!FLEET_IP[@]}"; do
      [[ "$n" == "$NODE" ]] && continue
      printf '%s\t%s\n' "${FLEET_IP[$n]}" "$n"
    done | sort -V
    printf '%s\n' "$end"
  } >> "$tmp"
  cat "$tmp" > "$1"
  rm -f "$tmp"
}

step_hosts() {
  [[ -n "${NODE_IP:-}" ]] || load_fleet
  write_hosts "$HOSTS_FILE"
  ok "$HOSTS_FILE lists the other $(( ${#FLEET_IP[@]} - 1 )) nodes"
}

step_timers() {
  systemd-analyze calendar "$PULL_SCHEDULE" >/dev/null 2>&1 || die "PULL_SCHEDULE '$PULL_SCHEDULE' isn't a valid OnCalendar value."
  install -d -m 755 "$LIB_DST" "$ETC_DIR"
  install -m 755 "$HERE/lib/purrbrews-pull.sh" "$LIB_DST/purrbrews-pull.sh"
  # A healthchecks.io URL is a secret-ish ping address: it's never in the
  # payload. Set it on the node in pull.env, and a re-run keeps it.
  local hc; hc="$(kv_get "$ETC_DIR/pull.env" PULL_HEALTHCHECK_URL)"
  ( umask 027; printf 'PROJECT_DIR=%s\nPULL_HEALTHCHECK_URL=%s\n' "$PROJECT_DIR" "$hc" > "$ETC_DIR/pull.env" )
  chown "root:$OPS_USER" "$ETC_DIR/pull.env"
  cat > "$UNIT_DIR/purrbrews-pull.service" <<EOF
[Unit]
Description=purrbrews: fetch new commits for ${PROJECT_DIR} (never moves the checkout)
Wants=network-online.target
After=network-online.target

[Service]
Type=oneshot
User=${OPS_USER}
EnvironmentFile=${ETC_DIR}/pull.env
ExecStart=${LIB_DST}/purrbrews-pull.sh
EOF
  cat > "$UNIT_DIR/purrbrews-pull.timer" <<EOF
[Unit]
Description=purrbrews: daily fetch of the repo

[Timer]
OnCalendar=${PULL_SCHEDULE}
RandomizedDelaySec=10min
Persistent=true

[Install]
WantedBy=timers.target
EOF
  systemctl daemon-reload
  systemctl enable --now purrbrews-pull.timer >/dev/null
  ok "purrbrews-pull.timer: a fetch at ${PULL_SCHEDULE}"
}

step_network() {
  [[ -n "${NODE_IP:-}" ]] || load_fleet
  local addr="${NODE_IP}/${PREFIX}" iface
  iface="$(ip -4 route show default | awk '{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}')"
  [[ -n "$iface" ]] || die "No default route: can't tell which interface to configure."
  [[ ! -d "/sys/class/net/${iface}/wireless" ]] \
    || die "$iface is Wi-Fi. The fleet is wired only: plug in Ethernet (a USB adapter on the x360s) and run this again."
  if systemctl is-active --quiet purrbrews-net-apply.service purrbrews-net-apply.timer; then
    die "A network switch is already running: wait a minute, read $LOG_DIR/net-apply.log, then run this again."
  fi

  local want_mac="" mac_arg=preserve cur_mac
  [[ "$CLONE_MAC" == true ]] && { want_mac="$NODE_MAC"; mac_arg="$want_mac"; }
  cur_mac="$(cat "/sys/class/net/${iface}/address")"

  local active_con current_method="" current_clone=""
  active_con="$(nmcli -t -f NAME,DEVICE connection show --active 2>/dev/null | awk -F: -v d="$iface" '$2==d{print $1; exit}')"
  if [[ -n "$active_con" ]]; then
    current_method="$(nmcli -g ipv4.method connection show "$active_con" 2>/dev/null || true)"
    current_clone="$(nmcli -g 802-3-ethernet.cloned-mac-address connection show "$active_con" 2>/dev/null || true)"
    current_clone="${current_clone,,}"; current_clone="${current_clone//\\/}"
  fi
  if ip -4 addr show dev "$iface" | grep -q "inet ${addr} " && [[ "$current_method" == manual ]] \
     && { [[ -z "$want_mac" ]] || [[ "$cur_mac" == "$want_mac" && "$current_clone" == "$want_mac" ]]; }; then
    ok "$iface is already $addr${want_mac:+ with MAC $want_mac}"
    return
  fi
  if [[ -n "$want_mac" && "$cur_mac" != "$want_mac" ]] && ip neigh show | grep -qi " lladdr ${want_mac} "; then
    die "MAC $want_mac is already on the network: two machines set up as $NODE?"
  fi

  systemctl enable --now NetworkManager >/dev/null
  if ! ip -4 addr show dev "$iface" | grep -q "inet ${NODE_IP}/" && ping -c2 -W1 "$NODE_IP" &>/dev/null; then
    die "$NODE_IP already answers on the network: another device has it. Check the router's DHCP range against stacks/fleet.env."
  fi

  local mode=nm nm_state
  nm_state="$(nmcli -t -f DEVICE,STATE device status | awk -F: -v d="$iface" '$1==d{print $2}')"
  if grep -Eq "^[[:space:]]*(auto|allow-hotplug|iface)[[:space:]]+${iface}([[:space:]]|$)" /etc/network/interfaces 2>/dev/null; then
    mode=migrate
  elif [[ "$nm_state" == unmanaged ]]; then
    die "$iface isn't managed by NetworkManager or /etc/network/interfaces (look in /etc/network/interfaces.d/). Hand it to NetworkManager, then run this again."
  fi

  local final_con="purrbrews-${iface}" new_con="purrbrews-${iface}"
  [[ "$active_con" == "$final_con" ]] && new_con="${final_con}-next"

  warn "About to switch $iface to $addr${want_mac:+, MAC $cur_mac -> $want_mac}, gateway $GATEWAY. Over SSH, reconnect to ${OPS_USER}@${NODE_IP}."
  confirm "Switch to the static address now? (it rolls back by itself in about 60 s if the gateway doesn't answer)" \
    || { warn "Static address not applied: run the one-liner again with '-- $NODE --only network --yes' when ready."; return; }

  install -d -m 755 "$LIB_DST" "$LOG_DIR"
  install -m 755 "$HERE/lib/net-apply.sh" "$LIB_DST/net-apply.sh"
  nmcli connection delete "${final_con}-next" &>/dev/null || true
  [[ "$new_con" == "$final_con" ]] && { nmcli connection delete "$final_con" &>/dev/null || true; }
  nmcli connection add type ethernet ifname "$iface" con-name "$new_con" \
    ipv4.method manual ipv4.addresses "$addr" ipv4.gateway "$GATEWAY" ipv4.dns "${BOOTSTRAP_DNS// /,}" \
    ipv4.ignore-auto-dns yes ipv6.method disabled \
    802-3-ethernet.cloned-mac-address "$mac_arg" \
    connection.autoconnect yes connection.autoconnect-priority 100 >/dev/null

  if [[ "$mode" == migrate ]]; then
    [[ -f /etc/network/interfaces.pre-purrbrews.bak ]] || cp /etc/network/interfaces /etc/network/interfaces.pre-purrbrews.bak
    # net-apply.sh swaps this in only after ifdown has released the DHCP lease:
    # ifdown needs the original stanza to know what to take down.
    awk -v ifc="$iface" '
      $1=="auto" || $1=="allow-hotplug" { if ($2==ifc) { print "# purrbrews: " $0; next } }
      $1=="iface" { inblk = ($2==ifc) }
      $1!="iface" && $0 !~ /^[[:space:]]/ && $0 !~ /^$/ { inblk=0 }
      inblk { print "# purrbrews: " $0; next }
      { print }' /etc/network/interfaces > /etc/network/interfaces.purrbrews-new
  fi

  systemctl reset-failed purrbrews-net-apply.service &>/dev/null || true
  systemd-run --unit=purrbrews-net-apply --description="purrbrews static address switch" \
    --on-active=5 "$LIB_DST/net-apply.sh" "$iface" "$new_con" "$addr" "$GATEWAY" "$mode" "$active_con" "$cur_mac" "$want_mac" >/dev/null
  NETWORK_SCHEDULED=true
  ok "static address${want_mac:+ and MAC} switch starts in 5 s (log: $LOG_DIR/net-apply.log)"
}

# ── tailnet ──────────────────────────────────────────────────────────────────
# Ported from the old init's tailscale step (deprecated/init/purrbrews-init.sh).
# Every run states the whole configuration (tailscale up --reset), so a
# hand-made change can't linger.

install_tailscale() {
  if command -v tailscale >/dev/null; then ok "tailscale is installed"; return; fi
  # From Tailscale's own apt repo, the way purrbrews-bootstrap adds Docker's.
  # Debian's unattended upgrades don't cover it; its own auto-update (below)
  # keeps it current.
  local suite
  suite="$(. /etc/os-release && printf '%s' "${VERSION_CODENAME:-}")"
  [[ -n "$suite" ]] || die "can't tell the Debian release (VERSION_CODENAME in /etc/os-release)."
  if ! curl -fsS -m 10 -o /dev/null "https://pkgs.tailscale.com/stable/debian/dists/$suite/Release"; then
    die "Tailscale's repo has no '$suite' suite yet; install it by hand (tailscale.com/download) and run again."
  fi
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL "https://pkgs.tailscale.com/stable/debian/$suite.noarmor.gpg" -o /etc/apt/keyrings/tailscale.gpg
  chmod a+r /etc/apt/keyrings/tailscale.gpg
  printf '%s\n' 'Types: deb' 'URIs: https://pkgs.tailscale.com/stable/debian' "Suites: $suite" \
    'Components: main' 'Signed-By: /etc/apt/keyrings/tailscale.gpg' > /etc/apt/sources.list.d/tailscale.sources
  apt-get update -q >/dev/null
  DEBIAN_FRONTEND=noninteractive apt-get install -y -q tailscale >/dev/null
  ok "tailscale installed from pkgs.tailscale.com ($suite)"
}

# The apps over the tailnet (tailscale/README.md, "Apps over the tailnet"). A
# tailnet device reaches https://<app>.${DOMAIN} at the app's LAN address
# through this node, and the Pi-holes through split DNS. Three pieces, since
# with --netfilter-mode=off Tailscale sets up none of them itself:
#   - forwarding on;
#   - UFW forwards 443 and 53 from tailscale0 and nothing else (which LAN
#     hosts may be reached is the tailnet policy's job: its grants name them);
#   - NAT onto the LAN, so every node sees the request coming from this node's
#     LAN address and its "from the LAN" rules apply unchanged. A oneshot unit
#     adds the rule, since UFW's before.rules would add a nat rule again on
#     every reload.
tailnet_router() {
  local lan_if rule
  lan_if="$(ip -4 route show default | awk '{for (i = 1; i <= NF; i++) if ($i == "dev") { print $(i + 1); exit }}')"
  [[ -n "$lan_if" ]] || die "no default route: can't tell which interface is the LAN."
  printf '# Written by the purrbrews payload (tailnet step): this node is a Tailscale subnet router.\nnet.ipv4.ip_forward = 1\n' \
    > "$SYSCTL_DIR/99-purrbrews-tailscale.conf"
  sysctl -q -p "$SYSCTL_DIR/99-purrbrews-tailscale.conf"
  # "to any" for 443: this node's own Traefik is a container, so after
  # Docker's DNAT the destination is a container address, not the LAN.
  ufw route allow in on tailscale0 proto tcp to any port 443 comment 'purrbrews: tailnet → web (subnet router)' >/dev/null
  ufw route allow in on tailscale0 out on "$lan_if" proto tcp to "$LAN_CIDR" port 53 comment 'purrbrews: tailnet → Pi-hole (subnet router)' >/dev/null
  ufw route allow in on tailscale0 out on "$lan_if" proto udp to "$LAN_CIDR" port 53 comment 'purrbrews: tailnet → Pi-hole (subnet router)' >/dev/null
  rule="POSTROUTING -s 100.64.0.0/10 -o $lan_if -j MASQUERADE"
  cat > "$UNIT_DIR/purrbrews-tailscale-nat.service" <<EOF
[Unit]
Description=PurrBrews: NAT the tailnet traffic this subnet router forwards onto the LAN
Wants=network-online.target
After=network-online.target ufw.service docker.service tailscaled.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/sh -c 'iptables -t nat -C $rule 2>/dev/null || iptables -t nat -A $rule'
ExecStop=/bin/sh -c 'iptables -t nat -D $rule 2>/dev/null || true'

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
  systemctl enable purrbrews-tailscale-nat.service >/dev/null
  systemctl restart purrbrews-tailscale-nat.service
  # shellcheck disable=SC2086  # the rule is words on purpose
  iptables -t nat -C $rule 2>/dev/null || die "the NAT rule isn't in place: systemctl status purrbrews-tailscale-nat"
  ok "subnet router: forwarding on, web (443) and DNS (53) from the tailnet, NAT via $lan_if"
}

step_tailnet() {
  [[ -n "${NODE_IP:-}" ]] || load_fleet
  local tags routers routes router=false r keyfile="$ETC_DIR/tailscale-authkey" state
  tags="$(setting TAILSCALE_TAGS tag:purrbrews-node)"
  routers="$(setting TAILSCALE_SUBNET_ROUTERS "cellar grinder")"
  routes="$(setting TAILSCALE_ROUTES 192.168.0.0/23)"
  [[ "$tags" =~ ^tag:[a-z0-9-]+(,tag:[a-z0-9-]+)*$ ]] || die "TAILSCALE_TAGS in payload.env must look like tag:purrbrews-node[,tag:other], not '$tags'."
  [[ "$routes" =~ ^[0-9]+(\.[0-9]+){3}/[0-9]{1,2}(,[0-9]+(\.[0-9]+){3}/[0-9]{1,2})*$ ]] \
    || die "TAILSCALE_ROUTES in payload.env must be comma-separated CIDRs, not '$routes'."
  for r in $routers; do
    [[ -n "${FLEET_IP[$r]:-}" ]] || die "TAILSCALE_SUBNET_ROUTERS names '$r', which isn't a node."
    [[ "$r" == "$NODE" ]] && router=true
  done
  command -v ufw >/dev/null || die "ufw isn't installed (purrbrews-bootstrap's firewall step): with --netfilter-mode=off it is the only filter on tailscale0."

  install_tailscale
  systemctl enable --now tailscaled >/dev/null
  # --netfilter-mode=off: by default Tailscale puts its own chains ahead of
  # UFW's and accepts everything arriving on tailscale0, so every port on the
  # node would answer the tailnet whatever UFW says. Off, UFW decides alone,
  # and the tailnet gets SSH and nothing else. Published container ports stay
  # shut too: ufw-docker only lets Docker's own subnets past.
  ufw allow in on tailscale0 to any port 22 proto tcp comment 'purrbrews: ssh over tailscale' >/dev/null
  ufw allow 41641/udp comment 'purrbrews: tailscale (wireguard)' >/dev/null
  ok "UFW: SSH on tailscale0, WireGuard on 41641/udp"

  if $router; then
    tailnet_router
  elif [[ -f "$UNIT_DIR/purrbrews-tailscale-nat.service" ]]; then
    systemctl disable --now purrbrews-tailscale-nat.service >/dev/null 2>&1 || true
    rm -f "$UNIT_DIR/purrbrews-tailscale-nat.service" "$SYSCTL_DIR/99-purrbrews-tailscale.conf"
    systemctl daemon-reload
    warn "No longer a subnet router: NAT and forwarding removed. Delete its 'tailnet →' rules by hand (sudo ufw status numbered)."
  fi

  # --accept-dns=false: the node keeps the Pi-holes, not MagicDNS.
  # --ssh=false: the nodes run OpenSSH with their own keys, not Tailscale SSH.
  local args=(up --reset "--hostname=${NODE,,}" --accept-dns=false --netfilter-mode=off --ssh=false
              "--advertise-tags=$tags")
  if $router; then args+=("--advertise-routes=$routes"); else args+=(--advertise-routes=); fi
  state="$(tailscale status --json 2>/dev/null | sed -n 's/^ *"BackendState": *"\([^"]*\)".*/\1/p' | head -n 1)" || true
  if [[ "$state" != Running ]]; then
    if [[ -f "$keyfile" ]]; then
      [[ "$(stat -c '%U %a' "$keyfile")" =~ ^root\ [46]00$ ]] || die "$keyfile must be owned by root, mode 600."
      args+=("--auth-key=file:$keyfile")
      say "  joining with the auth key in $keyfile"
    elif have_tty; then
      say "  joining: open the link below and sign in as the tailnet's admin (the tag needs it)."
    else
      warn "Not signed in, and no terminal to sign in from. Put an auth key in $keyfile (root, 600), or run this from a terminal."
      return 0
    fi
  fi
  tailscale "${args[@]}" \
    || die "tailscale up failed. If it says the tag isn't permitted, paste tailscale/policy.hujson into the admin console first (tailscale/README.md)."
  if [[ -f "$keyfile" ]]; then
    shred -u "$keyfile" 2>/dev/null || rm -f "$keyfile"
    ok "auth key used and deleted"
  fi
  tailscale set --auto-update=true || warn "couldn't turn on Tailscale's auto-update; update it with apt instead."
  local tsip
  tsip="$(tailscale ip -4 2>/dev/null | head -n 1)"
  [[ -n "$tsip" ]] || die "tailscale is up but has no address: tailscale status"
  ok "on the tailnet as ${NODE,,} at $tsip ($tags); SSH only, through UFW; DNS stays on the Pi-holes"
  if $router; then ok "advertising $routes: web and DNS only, NATed onto the LAN"; fi
}

# ── Main ─────────────────────────────────────────────────────────────────────

step_enabled() {
  local s="$1" x
  if [[ -n "$ONLY" ]]; then
    for x in $ONLY; do [[ "$x" == "$s" ]] && return 0; done
    return 1
  fi
  for x in "${OPT_IN_STEPS[@]}"; do [[ "$x" == "$s" ]] && return 1; done
  for x in $SKIP; do [[ "$x" == "$s" ]] && return 1; done
  return 0
}

main() {
  NODE=""; OPS_USER=""; ONLY=""; SKIP=""; AUTO_YES=false; NETWORK_SCHEDULED=false
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --user)       OPS_USER="${2:?--user needs a name}"; shift 2 ;;
      --only)       ONLY="${ONLY} ${2:?--only needs step names}"; shift 2 ;;
      --skip)       SKIP="${SKIP} ${2:?--skip needs step names}"; shift 2 ;;
      --yes|-y)     AUTO_YES=true; shift ;;
      --list-steps) printf '%s\n' "${ALL_STEPS[@]}"; exit 0 ;;
      -h|--help)    sed -n '2,/^set -Eeuo/p' "${BASH_SOURCE[0]}" | grep '^#' | sed 's/^# \{0,1\}//'; exit 0 ;;
      -*)           die "Unknown option: $1" ;;
      *)            [[ -z "$NODE" ]] || die "Only one node name."; NODE="$1"; shift ;;
    esac
  done
  ONLY="${ONLY//,/ }"; SKIP="${SKIP//,/ }"
  local s
  for s in $ONLY $SKIP; do
    [[ " ${ALL_STEPS[*]} " == *" $s "* ]] || die "Unknown step '$s'. Steps: ${ALL_STEPS[*]}"
  done
  if [[ " $ONLY " == *" tailnet "* && " $ONLY " == *" network "* ]]; then
    die "tailnet and network in one run: the address change would cut the sign-in off. One, then the other."
  fi

  [[ "$(id -u)" -eq 0 ]] || die "Run as root (purrbrews-bootstrap does)."
  [[ -n "$NODE" ]] || NODE="$(hostname -s)"
  [[ -n "$OPS_USER" ]] || OPS_USER="$(kv_get "$BOOTSTRAP_CONF" KEY_USER)"
  [[ -n "$OPS_USER" ]] || die "No ops user: run this through purrbrews-bootstrap, or pass --user."
  id "$OPS_USER" &>/dev/null || die "User '$OPS_USER' doesn't exist (purrbrews-bootstrap's user step makes it)."
  cd /   # the ops user must be able to read the working directory for git
  umask 022
  load_settings

  say "Making this machine fleet node '$NODE' (ops user $OPS_USER)"
  for s in "${ALL_STEPS[@]}"; do
    step_enabled "$s" || continue
    CURRENT_STEP="$s"
    say "→ $s"
    "step_$s"
  done
  CURRENT_STEP="done"

  printf '\n'
  say "$NODE is set up. Next, as $OPS_USER (not with sudo): cd $PROJECT_DIR/nodes/$NODE && ./setup-secrets.sh, then the node README."
  if [[ ${#WARNINGS[@]} -gt 0 ]]; then
    printf '\033[1;33m[purrbrews] %s warning(s):\033[0m\n' "${#WARNINGS[@]}" >&2
    printf '  - %s\n' "${WARNINGS[@]}" >&2
  fi
  if $NETWORK_SCHEDULED; then
    say "The address is switching now. Reconnect with: ssh $OPS_USER@$NODE_IP"
  fi
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  trap 'printf "\033[1;31m[purrbrews] ERROR:\033[0m step \"%s\" failed (line %s). Fix the cause and run the same command again.\n" "$CURRENT_STEP" "$LINENO" >&2' ERR
  main "$@"
fi
