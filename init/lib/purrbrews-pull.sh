#!/usr/bin/env bash
#
# purrbrews-pull.sh — unattended `git pull --ff-only` of PROJECT_DIR.
# Run by purrbrews-pull.timer as OPS_USER. Pull-only: never pushes, never
# merges, never restarts containers. Output goes to the journal:
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
  curl -fsS -m 10 --retry 3 -o /dev/null "${PULL_HEALTHCHECK_URL}${1:-}" || true
}

fail() { echo "FAILED: $*" >&2; ping_hc /fail; exit 1; }

[[ -d "$PROJECT_DIR/.git" ]] || fail "$PROJECT_DIR is not a git repository."

cd "$PROJECT_DIR"
before="$(git rev-parse HEAD)"

if ! git diff --quiet || ! git diff --cached --quiet; then
  fail "Tracked files have local changes — fleet nodes should not be edited in place. Inspect with 'git -C $PROJECT_DIR status'."
fi

out="$(git pull --ff-only 2>&1)" || fail "git pull --ff-only: $out"
after="$(git rev-parse HEAD)"

if [[ "$before" == "$after" ]]; then
  echo "OK: up to date at ${after:0:12}"
else
  echo "OK: ${before:0:12} -> ${after:0:12}"
  git --no-pager log --oneline "${before}..${after}"
  echo "NOTE: containers are not restarted automatically — redeploy changed stacks yourself."
fi
ping_hc
