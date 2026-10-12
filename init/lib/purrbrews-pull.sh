#!/usr/bin/env bash
#
# purrbrews-pull.sh — unattended fetch of release candidates for PROJECT_DIR.
# Run by purrbrews-pull.timer as OPS_USER. Never changes the active checkout,
# merges, pushes or restarts containers. Output goes to the journal:
#   journalctl -u purrbrews-pull.service
#
# Env (from /etc/purrbrews/pull.env via the systemd unit):
#   PROJECT_DIR           default /opt/purrbrews
#   PULL_HEALTHCHECK_URL  optional; pinged on success, <url>/fail on failure
#                         (healthchecks.io convention — the dead man's switch)
#
set -Eeuo pipefail

PROJECT_DIR="${PROJECT_DIR:-/opt/purrbrews}"
PULL_HEALTHCHECK_URL="${PULL_HEALTHCHECK_URL:-}"
export GIT_TERMINAL_PROMPT=0   # never hang on a credential prompt

ping_hc() {  # ping_hc [suffix]
  [[ -n "$PULL_HEALTHCHECK_URL" ]] || return 0
  curl -fsS -m 10 --retry 3 -o /dev/null "${PULL_HEALTHCHECK_URL}${1:-}" 2>/dev/null || true
}

fail() { echo "FAILED: $*" >&2; ping_hc /fail; exit 1; }

[[ -e "$PROJECT_DIR/.git" ]] || fail "$PROJECT_DIR is not a git repository."

cd "$PROJECT_DIR"
before="$(git rev-parse HEAD)"

if ! git diff --quiet || ! git diff --cached --quiet; then
  fail "Tracked files have local changes — fleet nodes should not be edited in place. Inspect with 'git -C $PROJECT_DIR status'."
fi

# Git transport errors can contain credential-bearing URLs. Keep them out of
# unattended journals and healthcheck notifications.
git fetch --quiet origin >/dev/null 2>&1 || fail "Fetch failed; check connectivity and origin configuration locally."
echo "OK: fetched origin; active checkout remains ${before:0:12}."
echo "Review a tested revision and follow docs/operations.md to deploy it."
ping_hc
