#!/usr/bin/env bash
#
# purrbrews-init.sh — take a fresh Debian 13 (trixie) install to "ready for
# container configs" in one run.
#
# What it does (each is a named step; see --list-steps):
#   hostname     hostname + managed /etc/hosts block for every fleet node
#   timezone     timezone + NTP
#   apt          full upgrade, base packages, unattended security upgrades
#   ops_user     the ops account (sudo, password-gated, NOT in the docker group)
#   ssh_keys     authorized_keys synced from roastery (purrbrews-bootstrap) / URLs / a local file
#   ssh_harden   key-only SSH, no root login, AllowUsers
#   power        ignore lid close, never suspend/hibernate
#   journald     cap journal disk use
#   docker       Docker Engine + Compose plugin from Docker's apt repo, log rotation
#   repo         clone the public REPO_URL into PROJECT_DIR (or fast-forward it)
#   directories  DATA_DIR / MEDIA_DIR + PROJECT_DIR/.env
#   timers       daily repo pull + hourly SSH key sync (systemd timers)
#   firewall     UFW (deny in, SSH from LAN only) + pinned ufw-docker
#   network      static IP + cloned MAC via NetworkManager, applied detached with auto-rollback
#
# Usage:
#   sudo ./purrbrews-init.sh [node] [options]
#
#   node               name from NODE_IPS in the env file (case-insensitive).
#                      Optional if this machine's hostname is already one of them.
#   --env FILE         env file (default: ./purrbrews-init.env next to this
#                      script, then /etc/purrbrews/purrbrews-init.env)
#   --yes, -y          don't ask before disruptive steps (SSH lock-down, IP change)
#   --only a,b         run only these steps
#   --skip a,b         run everything except these steps
#   --list-steps       print step names and exit
#   -h, --help         this text
#
# Safe to re-run: every step checks current state first. After the first run
# the env file is kept at /etc/purrbrews/purrbrews-init.env (root, 0600), so
# later runs from /opt/purrbrews/init need no USB stick.
#
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_NAME="$(basename "$0")"
LIB_SRC="${SCRIPT_DIR}/lib"
LIB_DST="/usr/local/lib/purrbrews"
ETC_DIR="/etc/purrbrews"
LOG_DIR="/var/log/purrbrews"

ALL_STEPS=(hostname timezone apt ops_user ssh_keys ssh_harden power journald
           docker repo directories timers firewall network)

# ---------------------------------------------------------------------------
# Output helpers
# ---------------------------------------------------------------------------
if [[ -t 1 ]]; then C_B=$'\033[1;36m'; C_Y=$'\033[1;33m'; C_R=$'\033[1;31m'; C_G=$'\033[1;32m'; C_0=$'\033[0m'
else C_B=""; C_Y=""; C_R=""; C_G=""; C_0=""; fi

CURRENT_STEP="startup"
log()  { printf '%s==>%s %s\n' "$C_B" "$C_0" "$*"; }
ok()   { printf '%s ok%s %s\n' "$C_G" "$C_0" "$*"; }
warn() { printf '%s !!%s %s\n' "$C_Y" "$C_0" "$*" >&2; WARNINGS+=("[$CURRENT_STEP] $*"); }
die()  { printf '%sERROR%s [%s] %s\n' "$C_R" "$C_0" "$CURRENT_STEP" "$*" >&2; exit 1; }
WARNINGS=()

on_err() {
  local code=$? line=${BASH_LINENO[0]}
  printf '%sFAILED%s step "%s" (line %s, exit %s): %s\n' \
    "$C_R" "$C_0" "$CURRENT_STEP" "$line" "$code" "$BASH_COMMAND" >&2
  printf 'Fix the cause and re-run; completed steps are skipped or no-ops.\n' >&2
}
trap on_err ERR

# /dev/tty can exist yet fail to open (no controlling terminal), so try opening it.
have_tty() { { : < /dev/tty; } 2>/dev/null; }

AUTO_YES=false
confirm() {
  $AUTO_YES && return 0
  have_tty || { warn "No terminal to confirm '$1' — pass --yes to allow."; return 1; }
  local reply
  read -r -p "$1 [y/N] " reply < /dev/tty
  [[ "$reply" =~ ^[Yy]$ ]]
}

# ---------------------------------------------------------------------------
# Env file: KEY=value lines, parsed WITHOUT executing anything.
# ---------------------------------------------------------------------------
ENV_FILE=""
declare -A NODE_IP=()
declare -A NODE_MAC=()

# shellcheck source=lib/node-mac.sh
. "${LIB_SRC}/node-mac.sh"

load_env_file() {
  local file="$1" line key val n=0
  while IFS= read -r line || [[ -n "$line" ]]; do
    n=$((n + 1))
    line="${line%$'\r'}"                         # tolerate Windows line endings
    [[ $n -eq 1 ]] && line="${line#$'\xef\xbb\xbf'}"  # and a UTF-8 BOM (Notepad)
    [[ "$line" =~ ^[[:space:]]*(#|$) ]] && continue
    if [[ ! "$line" =~ ^[[:space:]]*([A-Z_][A-Z0-9_]*)[[:space:]]*=(.*)$ ]]; then
      die "$file line $n is not KEY=value: $line"
    fi
    key="${BASH_REMATCH[1]}"; val="${BASH_REMATCH[2]}"
    val="${val#"${val%%[![:space:]]*}"}"; val="${val%"${val##*[![:space:]]}"}"   # trim
    if [[ "$val" =~ ^\"(.*)\"$ || "$val" =~ ^\'(.*)\'$ ]]; then val="${BASH_REMATCH[1]}"; fi
    printf -v "CFG_${key}" '%s' "$val"
  done < "$file"
}

cfg() {  # cfg KEY [default] — value from env file, else default
  local var="CFG_$1"
  if [[ -n "${!var:-}" ]]; then printf '%s' "${!var}"; else printf '%s' "${2:-}"; fi
}

resolve_config() {
  local candidates=()
  [[ -n "$ENV_FILE" ]] && candidates=("$ENV_FILE") \
    || candidates=("${SCRIPT_DIR}/purrbrews-init.env" "${ETC_DIR}/purrbrews-init.env")
  for f in "${candidates[@]}"; do
    if [[ -f "$f" ]]; then ENV_FILE="$f"; break; fi
  done
  [[ -n "$ENV_FILE" && -f "$ENV_FILE" ]] \
    || die "No env file found (looked in: ${candidates[*]}). Copy purrbrews-init.env.example to purrbrews-init.env and fill it in."
  load_env_file "$ENV_FILE"

  REPO_URL="$(cfg REPO_URL)"
  REPO_BRANCH="$(cfg REPO_BRANCH main)"
  OPS_USER="$(cfg OPS_USER barista)"
  OPS_PASSWORD_HASH="$(cfg OPS_PASSWORD_HASH)"
  SSH_KEYS_GITHUB_USERS="$(cfg SSH_KEYS_GITHUB_USERS)"
  SSH_KEYS_URLS="$(cfg SSH_KEYS_URLS)"
  SSH_KEY_FINGERPRINTS="$(cfg SSH_KEY_FINGERPRINTS)"
  SSH_KEYS_PINNED_PUBKEY="$(cfg SSH_KEYS_PINNED_PUBKEY)"
  BOOTSTRAP_URL="$(cfg BOOTSTRAP_URL)"
  SSH_ALLOW_USERS="$(cfg SSH_ALLOW_USERS "$OPS_USER")"
  NODE_IPS="$(cfg NODE_IPS)"
  GATEWAY="$(cfg GATEWAY 192.168.0.1)"
  SUBNET_CIDR="$(cfg SUBNET_CIDR 24)"
  BOOTSTRAP_DNS="$(cfg BOOTSTRAP_DNS "1.1.1.1 9.9.9.9")"
  LAN_CIDR="$(cfg LAN_CIDR 192.168.0.0/24)"
  CONFIGURE_STATIC_IP="$(cfg CONFIGURE_STATIC_IP true)"
  CLONE_MAC="$(cfg CLONE_MAC true)"
  NODE_MACS="$(cfg NODE_MACS)"
  TIMEZONE="$(cfg TZ Asia/Kolkata)"
  PROJECT_DIR="$(cfg PROJECT_DIR /opt/purrbrews)"
  DATA_DIR="$(cfg DATA_DIR /srv/data)"
  MEDIA_DIR="$(cfg MEDIA_DIR /srv/media)"
  ENABLE_UFW="$(cfg ENABLE_UFW true)"
  UFW_DOCKER_VERSION="$(cfg UFW_DOCKER_VERSION 251123)"
  UFW_DOCKER_SHA256="$(cfg UFW_DOCKER_SHA256 c3e5f0bf6061a3a2e7d7ac06abc80665707d2f4c91e90d76f22e4168863fb472)"
  PULL_SCHEDULE="$(cfg PULL_SCHEDULE "*-*-* 06:15:00")"
  PULL_HEALTHCHECK_URL="$(cfg PULL_HEALTHCHECK_URL)"
  KEY_SYNC_SCHEDULE="$(cfg KEY_SYNC_SCHEDULE hourly)"
  JOURNAL_MAX_USE="$(cfg JOURNAL_MAX_USE 500M)"
  DISABLE_SLEEP="$(cfg DISABLE_SLEEP true)"

  placeholder "$NODE_IPS" && die "NODE_IPS is not set in $ENV_FILE (e.g. NODE_IPS=sieve=192.168.0.10 percolator=192.168.0.11)."
  local pair name ip mac other
  declare -A seen_ip=() seen_mac=()
  for pair in $NODE_IPS; do
    [[ "$pair" =~ ^([A-Za-z][A-Za-z0-9-]*)=([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)$ ]] \
      || die "NODE_IPS entry '$pair' must look like name=192.168.0.10"
    name="${BASH_REMATCH[1]}"; ip="${BASH_REMATCH[2]}"
    valid_ipv4 "$ip" || die "NODE_IPS: '$ip' is not a valid IPv4 address"
    for other in "${!NODE_IP[@]}"; do
      [[ "${other,,}" == "${name,,}" ]] && die "NODE_IPS lists '$name' twice (names are case-insensitive)."
    done
    [[ -z "${seen_ip[$ip]:-}" ]] || die "NODE_IPS gives $ip to both ${seen_ip[$ip]} and $name."
    seen_ip["$ip"]="$name"
    NODE_IP["$name"]="$ip"
    NODE_MAC["$name"]="$(derive_mac "$name")"
  done

  for pair in $NODE_MACS; do
    [[ "$pair" =~ ^([A-Za-z][A-Za-z0-9-]*)=(.+)$ ]] || die "NODE_MACS entry '$pair' must look like name=02:aa:bb:cc:dd:ee"
    name="$(canonical_node "${BASH_REMATCH[1]}")" || die "NODE_MACS names '${BASH_REMATCH[1]}', which is not in NODE_IPS."
    mac="$(normalize_mac "${BASH_REMATCH[2]}")" || die "NODE_MACS: '${BASH_REMATCH[2]}' is not a MAC address."
    mac_is_usable "$mac" || die "NODE_MACS: $mac is a multicast/broadcast or zero address — it can't go on a NIC."
    mac_is_local "$mac" || warn "NODE_MACS: $mac for $name is a vendor (globally administered) MAC — make sure no real device has it."
    NODE_MAC["$name"]="$mac"
  done

  for name in "${!NODE_MAC[@]}"; do
    mac="${NODE_MAC[$name]}"
    [[ -z "${seen_mac[$mac]:-}" ]] || die "Nodes ${seen_mac[$mac]} and $name would share MAC $mac — set one explicitly in NODE_MACS."
    seen_mac["$mac"]="$name"
  done
}

# canonical_node <name> → the NODE_IPS spelling of a name, matched case-insensitively
canonical_node() {
  local n
  for n in "${!NODE_IP[@]}"; do
    [[ "${n,,}" == "${1,,}" ]] && { printf '%s\n' "$n"; return 0; }
  done
  return 1
}

valid_ipv4() {
  local IFS=. o; local -a p
  read -r -a p <<<"$1"
  [[ ${#p[@]} -eq 4 ]] || return 1
  for o in "${p[@]}"; do [[ "$o" =~ ^[0-9]{1,3}$ && "$o" -le 255 ]] || return 1; done
}

placeholder() { [[ -z "$1" || "$1" == *REPLACE_ME* ]]; }

step_enabled() {
  local s="$1" x
  if [[ -n "$ONLY" ]]; then
    for x in ${ONLY//,/ }; do [[ "$x" == "$s" ]] && return 0; done
    return 1
  fi
  for x in ${SKIP//,/ }; do [[ "$x" == "$s" ]] && return 1; done
  return 0
}

as_ops() { runuser -u "$OPS_USER" -- env HOME="$(getent passwd "$OPS_USER" | cut -d: -f6)" "$@"; }

# ---------------------------------------------------------------------------
# Preflight
# ---------------------------------------------------------------------------
preflight() {
  CURRENT_STEP="preflight"
  [[ "$(id -u)" -eq 0 ]] || die "Run as root: sudo ./$SCRIPT_NAME ${NODE:-<node>}"
  (( BASH_VERSINFO[0] >= 4 )) || die "bash 4+ required."

  # shellcheck disable=SC1091
  . /etc/os-release
  if [[ "${ID:-}" != debian ]]; then
    warn "OS is ${PRETTY_NAME:-unknown}, not Debian — continuing, but untested."
  elif [[ "${VERSION_ID:-}" != 13 ]]; then
    warn "Debian ${VERSION_ID:-?} detected; this script targets Debian 13 (trixie)."
  fi
  OS_CODENAME="${VERSION_CODENAME:-trixie}"

  resolve_config

  [[ ${#NODE_IP[@]} -gt 0 ]] || die "NODE_IPS is empty in $ENV_FILE."
  if [[ -z "$NODE" ]]; then
    local current; current="$(hostname -s)"
    NODE="$(canonical_node "$current")" \
      || die "No node given and hostname '$current' is not in NODE_IPS (${!NODE_IP[*]}). Usage: sudo ./$SCRIPT_NAME <node>"
  else
    local given="$NODE"
    NODE="$(canonical_node "$given")" || die "Unknown node '$given'. NODE_IPS has: ${!NODE_IP[*]}"
  fi
  [[ "$CLONE_MAC" == true || "$CLONE_MAC" == false ]] || die "CLONE_MAC must be true or false."
  valid_ipv4 "$GATEWAY" || die "GATEWAY '$GATEWAY' is not a valid IPv4 address."
  [[ "$SUBNET_CIDR" =~ ^[0-9]+$ && "$SUBNET_CIDR" -ge 8 && "$SUBNET_CIDR" -le 30 ]] || die "SUBNET_CIDR must be 8-30."
  [[ "$OPS_USER" =~ ^[a-z_][a-z0-9_-]*$ ]] || die "OPS_USER '$OPS_USER' is not a valid username."

  placeholder "$REPO_URL" && die "REPO_URL is not set in $ENV_FILE."
  if [[ -z "$SSH_KEYS_GITHUB_USERS$SSH_KEYS_URLS" && ! -f "${SCRIPT_DIR}/authorized_keys" && ! -f "${ETC_DIR}/authorized_keys.local" ]]; then
    die "No SSH key source: run via bootstrap.sh from roastery, set SSH_KEYS_URLS, or put an authorized_keys file next to this script."
  fi

  # GitHub is the public mirror: nothing secret may be needed to reach it.
  [[ -z "$(cfg GITHUB_TOKEN)" || "$(cfg GITHUB_TOKEN)" == *REPLACE_ME* ]] \
    || die "GITHUB_TOKEN is set in $ENV_FILE, but the repo is public — remove the token (and revoke it on GitHub)."
  [[ "$REPO_URL" == https://* ]] || die "REPO_URL must be the public https:// clone URL (no SSH, no credentials)."
  [[ "$REPO_URL" != *@* ]] || die "REPO_URL must not contain credentials."

  local perms; perms="$(stat -c %a "$ENV_FILE")"
  if [[ -n "$OPS_PASSWORD_HASH" && "$perms" != 600 && "$perms" != 400 ]]; then
    warn "$ENV_FILE is mode $perms and holds OPS_PASSWORD_HASH — it is copied to ${ETC_DIR} with mode 600; delete this copy when done."
  fi

  # A minimal Debian install may lack curl/jq/git/ssh-keygen, which the steps need.
  local need=() cmd
  for cmd in curl:curl jq:jq git:git ssh-keygen:openssh-client flock:util-linux; do
    command -v "${cmd%%:*}" &>/dev/null || need+=("${cmd##*:}")
  done
  if [[ ${#need[@]} -gt 0 ]]; then
    log "Installing prerequisites: ${need[*]}"
    DEBIAN_FRONTEND=noninteractive apt-get update -qq \
      || die "apt-get update failed — is the node online?"
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq ca-certificates "${need[@]}" >/dev/null
  fi

  if ! curl -fsS -m 10 -o /dev/null "https://deb.debian.org/debian/dists/${OS_CODENAME}/Release"; then
    die "No internet (could not reach deb.debian.org). Connect the node and re-run."
  fi

  install -d -m 755 "$ETC_DIR" "$LIB_DST"
  install -d -m 750 "$LOG_DIR"
  if [[ "$(realpath "$ENV_FILE")" != "$(realpath -m "${ETC_DIR}/purrbrews-init.env")" ]]; then
    install -m 600 -o root -g root "$ENV_FILE" "${ETC_DIR}/purrbrews-init.env"
  fi

  local mac_note="burned-in MAC"
  [[ "$CLONE_MAC" == true ]] && mac_note="MAC ${NODE_MAC[$NODE]}"
  log "Node ${NODE} → ${NODE_IP[$NODE]}/${SUBNET_CIDR} via ${GATEWAY}, ${mac_note}   (env: ${ENV_FILE})"
}

# ---------------------------------------------------------------------------
# Steps
# ---------------------------------------------------------------------------
step_hostname() {
  hostnamectl set-hostname "$NODE"
  if grep -qE '^127\.0\.1\.1[[:space:]]' /etc/hosts; then
    sed -i -E "s/^127\.0\.1\.1[[:space:]].*/127.0.1.1\t${NODE}/" /etc/hosts
  else
    printf '127.0.1.1\t%s\n' "$NODE" >> /etc/hosts
  fi

  local begin="# >>> purrbrews fleet (managed by purrbrews-init.sh) >>>"
  local end="# <<< purrbrews fleet <<<"
  local tmp; tmp="$(mktemp)"
  awk -v b="$begin" -v e="$end" '$0==b{s=1;next} $0==e{s=0;next} !s' /etc/hosts > "$tmp"
  {
    printf '%s\n' "$begin"
    local n
    for n in $(printf '%s\n' "${!NODE_IP[@]}" | sort); do
      [[ "$n" == "$NODE" ]] && continue          # own name stays on 127.0.1.1
      printf '%s\t%s\n' "${NODE_IP[$n]}" "$n"
    done
    printf '%s\n' "$end"
  } >> "$tmp"
  cat "$tmp" > /etc/hosts && rm -f "$tmp"
  ok "hostname=$NODE, /etc/hosts lists ${#NODE_IP[@]} fleet nodes"
}

step_timezone() {
  timedatectl set-timezone "$TIMEZONE" || die "Unknown timezone '$TIMEZONE' (see: timedatectl list-timezones)"
  timedatectl set-ntp true 2>/dev/null || true   # timesyncd arrives in the apt step on minimal installs
  ok "timezone $(timedatectl show -p Timezone --value)"
}

step_apt() {
  export DEBIAN_FRONTEND=noninteractive
  local apt_opts=(-y -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold)
  apt-get update
  apt-get "${apt_opts[@]}" full-upgrade
  apt-get "${apt_opts[@]}" install --no-install-recommends \
    ca-certificates curl gnupg git sudo openssl openssh-server \
    vim htop tmux jq rsync bash-completion \
    python3 bind9-dnsutils iputils-ping iproute2 net-tools ethtool \
    network-manager systemd-timesyncd \
    unattended-upgrades apt-listchanges \
    ufw gettext-base
  timedatectl set-ntp true 2>/dev/null || true

  cat > /etc/apt/apt.conf.d/20auto-upgrades <<'EOF'
// Managed by purrbrews-init.sh
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
EOF
  systemctl enable --now unattended-upgrades >/dev/null 2>&1 || true
  ok "system upgraded, base packages + unattended security upgrades in place"
}

step_ops_user() {
  if ! id "$OPS_USER" &>/dev/null; then
    adduser --disabled-password --gecos "" "$OPS_USER"
    log "Created user $OPS_USER"
  fi
  usermod -aG sudo "$OPS_USER"
  if id -nG "$OPS_USER" | tr ' ' '\n' | grep -qx docker; then
    gpasswd -d "$OPS_USER" docker >/dev/null
    warn "Removed $OPS_USER from the docker group (root-equivalent without a password — use 'sudo docker')."
  fi

  local status; status="$(passwd -S "$OPS_USER" | awk '{print $2}')"
  if [[ -n "$OPS_PASSWORD_HASH" ]]; then
    [[ "$OPS_PASSWORD_HASH" =~ ^\$(6|y|5)\$ ]] || die "OPS_PASSWORD_HASH must be a crypt hash (e.g. from 'openssl passwd -6')."
    local current; current="$(getent shadow "$OPS_USER" | cut -d: -f2)"
    if [[ "$current" != "$OPS_PASSWORD_HASH" ]]; then
      usermod -p "$OPS_PASSWORD_HASH" "$OPS_USER"
      ok "sudo password for $OPS_USER set from OPS_PASSWORD_HASH"
    fi
  elif [[ "$status" != P ]]; then
    if have_tty && ! $AUTO_YES; then
      log "Set the sudo password for $OPS_USER (SSH stays key-only; this gates root):"
      local tries=0
      until passwd "$OPS_USER" < /dev/tty; do
        tries=$((tries + 1)); [[ $tries -lt 3 ]] || die "Password not set."
      done
    else
      local pw; pw="$(openssl rand -base64 18)"
      echo "${OPS_USER}:${pw}" | chpasswd
      ( umask 077; printf '%s\n' "$pw" > /root/purrbrews-ops-password )
      warn "Generated a sudo password for $OPS_USER → /root/purrbrews-ops-password (root-only). Store it, then delete the file."
    fi
  fi
  ok "$OPS_USER: sudo (password-gated), not in docker group"
}

step_ssh_keys() {
  install -m 755 "${LIB_SRC}/sync-ssh-keys.sh" "${LIB_DST}/sync-ssh-keys.sh"

  local local_file=""
  if [[ -f "${SCRIPT_DIR}/authorized_keys" ]]; then
    install -m 644 "${SCRIPT_DIR}/authorized_keys" "${ETC_DIR}/authorized_keys.local"
  fi
  [[ -f "${ETC_DIR}/authorized_keys.local" ]] && local_file="${ETC_DIR}/authorized_keys.local"

  cat > "${ETC_DIR}/ssh-keys.conf" <<EOF
# Managed by purrbrews-init.sh — edit purrbrews-init.env and re-run instead.
OPS_USER=${OPS_USER}
SSH_KEYS_GITHUB_USERS=${SSH_KEYS_GITHUB_USERS}
SSH_KEYS_URLS=${SSH_KEYS_URLS}
SSH_KEYS_LOCAL_FILE=${local_file}
SSH_KEY_FINGERPRINTS=${SSH_KEY_FINGERPRINTS}
SSH_KEYS_PINNED_PUBKEY=${SSH_KEYS_PINNED_PUBKEY}
EOF
  chmod 644 "${ETC_DIR}/ssh-keys.conf"

  local rc=0
  "${LIB_DST}/sync-ssh-keys.sh" --config "${ETC_DIR}/ssh-keys.conf" || rc=$?
  case "$rc" in
    0) ;;
    75) die "A key source is unreachable${BOOTSTRAP_URL:+ (is purrbrews-bootstrap on roastery running?)} — nothing was changed." ;;
    *)  die "SSH key sync failed — nothing was changed. Check the key sources above." ;;
  esac
  ok "authorized_keys for $OPS_USER synced"
}

step_ssh_harden() {
  local home ak
  home="$(getent passwd "$OPS_USER" | cut -d: -f6)"
  ak="${home}/.ssh/authorized_keys"
  if ! { [[ -s "$ak" ]] && grep -qE '^(ssh-|ecdsa-|sk-)' "$ak"; }; then die "$ak has no keys — refusing to disable password login (you'd be locked out). Run the ssh_keys step first."; fi

  local conf=/etc/ssh/sshd_config.d/00-purrbrews.conf
  local desired
  desired="$(cat <<EOF
# Managed by purrbrews-init.sh. Loaded before other drop-ins; first value wins.
PubkeyAuthentication yes
PasswordAuthentication no
KbdInteractiveAuthentication no
AuthenticationMethods publickey
PermitRootLogin no
PermitEmptyPasswords no
MaxAuthTries 3
LoginGraceTime 30
X11Forwarding no
AllowUsers ${SSH_ALLOW_USERS}
EOF
)"
  if [[ -f "$conf" && "$(cat "$conf")" == "$desired" ]]; then
    systemctl enable --now ssh >/dev/null 2>&1 || true
    ok "sshd already hardened"; return
  fi

  grep -qE '^[[:space:]]*Include[[:space:]]+/etc/ssh/sshd_config\.d/\*\.conf' /etc/ssh/sshd_config \
    || die "/etc/ssh/sshd_config does not Include sshd_config.d/*.conf — add it, then re-run."

  if [[ -n "${SSH_CONNECTION:-}" ]]; then
    local me="${SUDO_USER:-$(logname 2>/dev/null || echo root)}"
    if [[ " $SSH_ALLOW_USERS " != *" $me "* ]]; then
      warn "You are connected over SSH as '$me', which will no longer be allowed to log in (AllowUsers ${SSH_ALLOW_USERS})."
    fi
    confirm "Disable SSH password login now? Test 'ssh ${OPS_USER}@${NODE_IP[$NODE]}' with your key from another terminal first." \
      || { warn "Skipped SSH hardening — re-run with --only ssh_harden when ready."; return; }
  fi

  printf '%s\n' "$desired" > "$conf"
  chmod 644 "$conf"
  if ! sshd -t; then
    rm -f "$conf"
    die "sshd config test failed — change reverted."
  fi
  systemctl enable ssh >/dev/null 2>&1 || true
  systemctl reload-or-restart ssh
  ok "SSH: key-only, no root, AllowUsers ${SSH_ALLOW_USERS}"
}

step_power() {
  [[ "$DISABLE_SLEEP" == true ]] || { log "DISABLE_SLEEP=false — skipping."; return; }
  install -d /etc/systemd/logind.conf.d
  cat > /etc/systemd/logind.conf.d/50-purrbrews.conf <<'EOF'
# Managed by purrbrews-init.sh — a server must not sleep when a lid closes.
[Login]
HandleLidSwitch=ignore
HandleLidSwitchExternalPower=ignore
HandleLidSwitchDocked=ignore
HandleSuspendKey=ignore
HandleHibernateKey=ignore
IdleAction=ignore
EOF
  systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target >/dev/null 2>&1 || true
  # Reloading logind does not end sessions (a restart could on some versions).
  systemctl kill -s HUP systemd-logind 2>/dev/null || true
  ok "lid close ignored, suspend/hibernate masked"
}

step_journald() {
  install -d /etc/systemd/journald.conf.d
  cat > /etc/systemd/journald.conf.d/50-purrbrews.conf <<EOF
# Managed by purrbrews-init.sh
[Journal]
Storage=persistent
SystemMaxUse=${JOURNAL_MAX_USE}
EOF
  systemctl restart systemd-journald
  ok "journal capped at ${JOURNAL_MAX_USE}"
}

step_docker() {
  if ! command -v docker &>/dev/null || ! docker compose version &>/dev/null; then
    # Remove distro packages that conflict with Docker's own.
    local p
    for p in docker.io docker-doc docker-compose podman-docker containerd runc; do
      dpkg -s "$p" &>/dev/null && apt-get -y remove "$p"
    done
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
    chmod a+r /etc/apt/keyrings/docker.asc
    local suite="$OS_CODENAME"
    if ! curl -fsS -m 10 -o /dev/null "https://download.docker.com/linux/debian/dists/${suite}/Release"; then
      warn "Docker's repo has no '${suite}' suite — falling back to bookworm."
      suite=bookworm
    fi
    rm -f /etc/apt/sources.list.d/docker.list
    cat > /etc/apt/sources.list.d/docker.sources <<EOF
Types: deb
URIs: https://download.docker.com/linux/debian
Suites: ${suite}
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
EOF
    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get -y install \
      docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  fi

  # Log rotation: without it json-file logs grow until the disk is full.
  install -d /etc/docker
  local daemon=/etc/docker/daemon.json
  local want='{"log-driver":"json-file","log-opts":{"max-size":"10m","max-file":"3"},"live-restore":true}'
  if [[ -f "$daemon" ]]; then
    local merged; merged="$(jq -S --argjson w "$want" '. * $w' "$daemon")" \
      || die "$daemon is not valid JSON — fix or remove it."
    if [[ "$merged" != "$(jq -S . "$daemon")" ]]; then
      printf '%s\n' "$merged" > "$daemon"; DOCKER_RESTART=true
    fi
  else
    jq -S . <<<"$want" > "$daemon"; DOCKER_RESTART=true
  fi

  systemctl enable --now docker containerd >/dev/null
  if [[ "${DOCKER_RESTART:-false}" == true ]]; then systemctl restart docker; fi
  docker info >/dev/null 2>&1 || die "Docker daemon is not responding — check 'journalctl -u docker'."
  ok "$(docker --version | cut -d, -f1), $(docker compose version --short 2>/dev/null | sed 's/^/compose /')"
}

step_repo() {
  export GIT_TERMINAL_PROMPT=0
  as_ops git config --global pull.ff only
  as_ops git config --global init.defaultBranch main
  git config --system --replace-all safe.directory "$PROJECT_DIR" "^${PROJECT_DIR}$"
  chmod 644 /etc/gitconfig
  if ! as_ops git ls-remote --heads "$REPO_URL" "$REPO_BRANCH" | grep -q .; then
    die "Cannot read branch '$REPO_BRANCH' of $REPO_URL. Is the repo public and pushed, and is the branch name right?"
  fi
  if [[ -d "${PROJECT_DIR}/.git" ]]; then
    local origin; origin="$(as_ops git -C "$PROJECT_DIR" remote get-url origin 2>/dev/null || true)"
    [[ "$origin" == "$REPO_URL" ]] \
      || warn "$PROJECT_DIR origin is '$origin', env says '$REPO_URL' — leaving it alone."
    chown -R "$OPS_USER:$OPS_USER" "$PROJECT_DIR"
    if as_ops git -C "$PROJECT_DIR" pull --ff-only; then
      ok "$PROJECT_DIR fast-forwarded to $(as_ops git -C "$PROJECT_DIR" rev-parse --short HEAD)"
    else
      warn "git pull --ff-only failed in $PROJECT_DIR (local edits or diverged history) — left as is."
    fi
    return
  fi

  if [[ -e "$PROJECT_DIR" ]] && [[ -n "$(ls -A "$PROJECT_DIR" 2>/dev/null)" ]]; then
    die "$PROJECT_DIR exists, is not empty and is not a git repo. Move it aside and re-run."
  fi
  install -d -m 2775 -o "$OPS_USER" -g "$OPS_USER" "$PROJECT_DIR"
  as_ops git clone --branch "$REPO_BRANCH" "$REPO_URL" "$PROJECT_DIR" \
    || die "Clone of $REPO_URL failed."
  ok "cloned $REPO_URL ($REPO_BRANCH) → $PROJECT_DIR"
}

step_directories() {
  install -d -m 2775 -o "$OPS_USER" -g "$OPS_USER" "$DATA_DIR" "$MEDIA_DIR"
  [[ -d "$PROJECT_DIR" ]] || install -d -m 2775 -o "$OPS_USER" -g "$OPS_USER" "$PROJECT_DIR"

  local uid gid; uid="$(id -u "$OPS_USER")"; gid="$(id -g "$OPS_USER")"
  cat > "${PROJECT_DIR}/.env" <<EOF
# Generated by purrbrews-init.sh on every run — do not edit, do not commit.
# Non-secret, node-wide values for compose files.
NODE=${NODE}
NODE_IP=${NODE_IP[$NODE]}
TZ=${TIMEZONE}
PUID=${uid}
PGID=${gid}
PROJECT_DIR=${PROJECT_DIR}
DATA_DIR=${DATA_DIR}
MEDIA_DIR=${MEDIA_DIR}
EOF
  chown "$OPS_USER:$OPS_USER" "${PROJECT_DIR}/.env"
  chmod 644 "${PROJECT_DIR}/.env"
  ok "DATA_DIR=$DATA_DIR MEDIA_DIR=$MEDIA_DIR, ${PROJECT_DIR}/.env written"
}

step_timers() {
  install -m 755 "${LIB_SRC}/purrbrews-pull.sh" "${LIB_DST}/purrbrews-pull.sh"

  umask 077
  cat > "${ETC_DIR}/pull.env" <<EOF
PROJECT_DIR=${PROJECT_DIR}
PULL_HEALTHCHECK_URL=${PULL_HEALTHCHECK_URL}
EOF
  chown root:"$OPS_USER" "${ETC_DIR}/pull.env"; chmod 640 "${ETC_DIR}/pull.env"
  umask 022

  cat > /etc/systemd/system/purrbrews-pull.service <<EOF
[Unit]
Description=PurrBrews: fast-forward ${PROJECT_DIR}
Wants=network-online.target
After=network-online.target

[Service]
Type=oneshot
User=${OPS_USER}
EnvironmentFile=${ETC_DIR}/pull.env
ExecStart=${LIB_DST}/purrbrews-pull.sh
EOF
  cat > /etc/systemd/system/purrbrews-pull.timer <<EOF
[Unit]
Description=PurrBrews: daily repo pull

[Timer]
OnCalendar=${PULL_SCHEDULE}
RandomizedDelaySec=10min
Persistent=true

[Install]
WantedBy=timers.target
EOF
  cat > /etc/systemd/system/purrbrews-ssh-keys.service <<EOF
[Unit]
Description=PurrBrews: sync SSH authorized_keys for ${OPS_USER}
Wants=network-online.target
After=network-online.target

[Service]
Type=oneshot
# 75 = a source (roastery) was unreachable; keys were left unchanged. Not a failure.
SuccessExitStatus=75
ExecStart=${LIB_DST}/sync-ssh-keys.sh --config ${ETC_DIR}/ssh-keys.conf
EOF
  cat > /etc/systemd/system/purrbrews-ssh-keys.timer <<EOF
[Unit]
Description=PurrBrews: periodic SSH key sync

[Timer]
OnCalendar=${KEY_SYNC_SCHEDULE}
RandomizedDelaySec=5min
Persistent=true

[Install]
WantedBy=timers.target
EOF
  systemd-analyze calendar "$PULL_SCHEDULE" >/dev/null || die "PULL_SCHEDULE '$PULL_SCHEDULE' is not a valid OnCalendar value."
  systemd-analyze calendar "$KEY_SYNC_SCHEDULE" >/dev/null || die "KEY_SYNC_SCHEDULE '$KEY_SYNC_SCHEDULE' is not a valid OnCalendar value."
  systemctl daemon-reload
  systemctl enable --now purrbrews-pull.timer purrbrews-ssh-keys.timer >/dev/null
  ok "timers: repo pull (${PULL_SCHEDULE}), SSH key sync (${KEY_SYNC_SCHEDULE})"
}

step_firewall() {
  [[ "$ENABLE_UFW" == true ]] || { log "ENABLE_UFW=false — skipping."; return; }

  # Additive only — never 'ufw reset', which would wipe per-app rules on re-runs.
  ufw default deny incoming >/dev/null
  ufw default allow outgoing >/dev/null
  ufw allow from "$LAN_CIDR" to any port 22 proto tcp comment 'purrbrews: ssh from LAN' >/dev/null
  if [[ -n "${SSH_CONNECTION:-}" ]]; then
    local client="${SSH_CONNECTION%% *}"
    ufw allow from "$client" to any port 22 proto tcp comment 'purrbrews: current ssh session' >/dev/null
  fi
  ufw --force enable >/dev/null

  if command -v docker &>/dev/null; then
    local bin=/usr/local/bin/ufw-docker have=""
    [[ -f "$bin" ]] && have="$(sha256sum "$bin" | cut -d' ' -f1)"
    if [[ "$have" != "$UFW_DOCKER_SHA256" ]]; then
      local tmp; tmp="$(mktemp)"
      curl -fsSL -o "$tmp" "https://raw.githubusercontent.com/chaifeng/ufw-docker/${UFW_DOCKER_VERSION}/ufw-docker"
      [[ "$(sha256sum "$tmp" | cut -d' ' -f1)" == "$UFW_DOCKER_SHA256" ]] \
        || { rm -f "$tmp"; die "ufw-docker ${UFW_DOCKER_VERSION} checksum mismatch — not installing."; }
      install -m 755 "$tmp" "$bin"; rm -f "$tmp"
    fi
    if ! ufw-docker check >/dev/null 2>&1; then
      ufw-docker install
      ufw reload >/dev/null
    fi
    ok "UFW on (SSH from ${LAN_CIDR}); ufw-docker ${UFW_DOCKER_VERSION} blocks published ports until 'ufw-docker allow'"
  else
    warn "Docker not installed — ufw-docker skipped; re-run --only firewall after the docker step."
  fi
}

step_network() {
  [[ "$CONFIGURE_STATIC_IP" == true ]] || { log "CONFIGURE_STATIC_IP=false — skipping."; return; }

  local target="${NODE_IP[$NODE]}" addr="${NODE_IP[$NODE]}/${SUBNET_CIDR}"
  local iface; iface="$(ip -4 route show default | awk '{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}')"
  [[ -n "$iface" ]] || die "No default route — can't tell which interface to configure."

  if systemctl is-active --quiet purrbrews-net-apply.service purrbrews-net-apply.timer; then
    die "A network switch is already in progress — wait ~1 minute, check ${LOG_DIR}/net-apply.log, then re-run."
  fi
  [[ -d "/sys/class/net/${iface}/wireless" ]] \
    && die "$iface is Wi-Fi. The fleet is wired-only by design; plug in Ethernet (or a USB dongle) and re-run."

  local want_mac="" mac_arg=preserve
  if [[ "$CLONE_MAC" == true ]]; then want_mac="${NODE_MAC[$NODE]}"; mac_arg="$want_mac"; fi
  local cur_mac; cur_mac="$(cat "/sys/class/net/${iface}/address")"

  local current_method="" current_clone=""
  local active_con; active_con="$(nmcli -t -f NAME,DEVICE connection show --active 2>/dev/null | awk -F: -v d="$iface" '$2==d{print $1; exit}')"
  if [[ -n "$active_con" ]]; then
    current_method="$(nmcli -g ipv4.method connection show "$active_con" 2>/dev/null || true)"
    current_clone="$(nmcli -g 802-3-ethernet.cloned-mac-address connection show "$active_con" 2>/dev/null || true)"
    current_clone="${current_clone,,}"; current_clone="${current_clone//\\/}"
  fi
  if ip -4 addr show dev "$iface" | grep -q "inet ${addr} " && [[ "$current_method" == manual ]] \
     && { [[ -z "$want_mac" ]] || [[ "$cur_mac" == "$want_mac" && "$current_clone" == "$want_mac" ]]; }; then
    ok "$iface already static at $addr${want_mac:+ with MAC $want_mac}"; return
  fi

  # Is the target MAC already on the LAN? (another node cloned the same name)
  if [[ -n "$want_mac" && "$cur_mac" != "$want_mac" ]]; then
    ip neigh show | grep -qi " lladdr ${want_mac} " \
      && die "MAC $want_mac is already in this node's ARP table for another host — two nodes with the same name?"
  fi

  systemctl enable --now NetworkManager >/dev/null
  if ! ip -4 addr show dev "$iface" | grep -q "inet ${target}/"; then
    if ping -c2 -W1 "$target" &>/dev/null; then
      die "$target already answers on the network — another device has it. Fix NODE_IPS or the DHCP range."
    fi
  fi

  local mode=nm
  local nm_state; nm_state="$(nmcli -t -f DEVICE,STATE device status | awk -F: -v d="$iface" '$1==d{print $2}')"
  if grep -Eq "^[[:space:]]*(auto|allow-hotplug|iface)[[:space:]]+${iface}([[:space:]]|$)" /etc/network/interfaces 2>/dev/null; then
    mode=migrate
    [[ -d "/sys/class/net/${iface}/wireless" ]] \
      && die "$iface is Wi-Fi managed by ifupdown; migrating would drop its credentials. Connect it with nmcli first, then re-run."
  elif [[ "$nm_state" == unmanaged ]]; then
    die "$iface is not managed by NetworkManager and not defined in /etc/network/interfaces (check /etc/network/interfaces.d/ or netplan). Hand it to NetworkManager, then re-run."
  fi

  # Build the new profile under a temporary name when the active one already
  # carries the final name (re-run with a changed IP/MAC): deleting the live
  # profile first would drop the link with nothing to roll back to.
  local final_con="purrbrews-${iface}" new_con="purrbrews-${iface}"
  [[ "$active_con" == "$final_con" ]] && new_con="${final_con}-next"
  local dns="${BOOTSTRAP_DNS// /,}"

  warn "About to switch $iface to static $addr${want_mac:+, MAC $cur_mac → $want_mac} (gateway $GATEWAY). If connected over SSH, reconnect to ${OPS_USER}@${target}."
  confirm "Apply static IP now? (auto-rollback in ~60 s if the gateway is unreachable)" \
    || { warn "Skipped static IP — re-run with --only network when ready."; return; }

  install -m 755 "${LIB_SRC}/net-apply.sh" "${LIB_DST}/net-apply.sh"

  nmcli connection delete "${final_con}-next" &>/dev/null || true
  [[ "$new_con" == "$final_con" ]] && { nmcli connection delete "$final_con" &>/dev/null || true; }
  nmcli connection add type ethernet ifname "$iface" con-name "$new_con" \
    ipv4.method manual ipv4.addresses "$addr" ipv4.gateway "$GATEWAY" ipv4.dns "$dns" \
    ipv4.ignore-auto-dns yes ipv6.method disabled \
    802-3-ethernet.cloned-mac-address "$mac_arg" \
    connection.autoconnect yes connection.autoconnect-priority 100 >/dev/null

  if [[ "$mode" == migrate ]]; then
    [[ -f /etc/network/interfaces.pre-purrbrews.bak ]] || cp /etc/network/interfaces /etc/network/interfaces.pre-purrbrews.bak
    # Prepare a copy with this interface's stanza commented out. net-apply.sh
    # swaps it in only AFTER 'ifdown' has released the DHCP lease, because
    # ifdown needs the original stanza to know how to deconfigure the interface.
    awk -v ifc="$iface" '
      $1=="auto" || $1=="allow-hotplug" { if ($2==ifc) { print "# purrbrews: " $0; next } }
      $1=="iface" { inblk = ($2==ifc) }
      $1!="iface" && $0 !~ /^[[:space:]]/ && $0 !~ /^$/ { inblk=0 }
      inblk { print "# purrbrews: " $0; next }
      { print }' /etc/network/interfaces > /etc/network/interfaces.purrbrews-new
  fi

  systemctl reset-failed purrbrews-net-apply.service &>/dev/null || true
  systemd-run --unit=purrbrews-net-apply --description="PurrBrews static IP switch" \
    --on-active=5 "${LIB_DST}/net-apply.sh" "$iface" "$new_con" "$addr" "$GATEWAY" "$mode" "$active_con" "$cur_mac" "$want_mac" >/dev/null
  NETWORK_SCHEDULED=true
  ok "static IP${want_mac:+ + MAC} switch scheduled in 5 s (log: ${LOG_DIR}/net-apply.log)"
}

summary() {
  CURRENT_STEP="summary"
  local stack_dir="${PROJECT_DIR}/stacks/${NODE}"
  printf '\n%s━━━ %s is initialised ━━━%s\n' "$C_G" "$NODE" "$C_0"
  cat <<EOF
  Address      ${NODE_IP[$NODE]}/${SUBNET_CIDR}  (gateway ${GATEWAY})
  MAC          $( [[ "$CLONE_MAC" == true ]] && echo "${NODE_MAC[$NODE]} (cloned; burned-in MAC still used for Wake-on-LAN)" || echo "burned-in (CLONE_MAC=false)" )
  Login        ssh ${OPS_USER}@${NODE_IP[$NODE]}   (key only; 'sudo' asks for ${OPS_USER}'s password)
  Docker       sudo docker compose ...   (${OPS_USER} is deliberately not in the docker group)
  Repo         ${PROJECT_DIR}  ←  ${REPO_URL} (${REPO_BRANCH})
  Data         ${DATA_DIR}, ${MEDIA_DIR}
  Timers       systemctl list-timers 'purrbrews-*'
  Log          ${RUN_LOG}
EOF
  if [[ ${#WARNINGS[@]} -gt 0 ]]; then
    printf '\n%sWarnings:%s\n' "$C_Y" "$C_0"
    printf '  - %s\n' "${WARNINGS[@]}"
  fi
  printf '\nNext:\n'
  if [[ -d "$stack_dir" ]]; then
    printf '  cd %s   # and run this node\x27s container setup (e.g. sudo ./setup-secrets.sh)\n' "$stack_dir"
  else
    printf '  %s does not exist yet — add the stack to the repo, then: sudo systemctl start purrbrews-pull\n' "$stack_dir"
  fi
  [[ "$ENV_FILE" == "${ETC_DIR}/purrbrews-init.env" || -n "${PURRBREWS_BOOTSTRAP:-}" ]] \
    || printf '  A root-only copy of the settings is in %s; you can delete %q\n' "${ETC_DIR}/purrbrews-init.env" "$ENV_FILE"
  if [[ "${NETWORK_SCHEDULED:-false}" == true ]]; then
    printf '\n%sNetwork is switching to %s now — reconnect with: ssh %s@%s%s\n' "$C_Y" "${NODE_IP[$NODE]}" "$OPS_USER" "${NODE_IP[$NODE]}" "$C_0"
  fi
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
  NODE=""; ONLY=""; SKIP=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --env)        ENV_FILE="$(realpath -m "${2:?--env needs a file}")"; shift 2 ;;
      --yes|-y)     AUTO_YES=true; shift ;;
      --only)       ONLY="${2:?--only needs step names}"; shift 2 ;;
      --skip)       SKIP="${2:?--skip needs step names}"; shift 2 ;;
      --list-steps) printf '%s\n' "${ALL_STEPS[@]}"; exit 0 ;;
      -h|--help)    sed -n '2,40p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
      -*)           die "Unknown option: $1 (see --help)" ;;
      *)            [[ -z "$NODE" ]] || die "Only one node name allowed."; NODE="$1"; shift ;;
    esac
  done

  local s x
  for x in ${ONLY//,/ } ${SKIP//,/ }; do
    [[ " ${ALL_STEPS[*]} " == *" $x "* ]] || die "Unknown step '$x'. Steps: ${ALL_STEPS[*]}"
  done

  [[ "$(id -u)" -eq 0 ]] || die "Run as root: sudo ./$SCRIPT_NAME [node]"
  mkdir -p "$LOG_DIR"; chmod 750 "$LOG_DIR"
  RUN_LOG="${LOG_DIR}/init-$(date +%Y%m%d-%H%M%S).log"
  exec > >(tee -a "$RUN_LOG") 2>&1

  cd /   # the ops user must be able to read the working directory for git
  umask 022
  exec 9>/run/purrbrews-init.lock
  flock -n 9 || die "Another purrbrews-init.sh is already running."

  preflight
  for s in "${ALL_STEPS[@]}"; do
    step_enabled "$s" || continue
    CURRENT_STEP="$s"
    log "[$s]"
    "step_$s"
  done
  summary
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
