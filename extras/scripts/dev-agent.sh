#!/usr/bin/env bash
# extras/scripts/dev-agent.sh — Manager loop for the unattended dev-agent service.
# Keeps a zmx session alive, initializes a git workspace, and lets systemd supervise.
set -euo pipefail

: "${DEV_AGENT_SESSION_NAME:?must be set}"
: "${DEV_AGENT_TASK_SCRIPT:?must be set}"
: "${DEV_AGENT_POLL_INTERVAL_SEC:?must be set}"

# Set XDG_RUNTIME_DIR from actual UID (systemd %U resolves to root in system units)
XDG_RUNTIME_DIR="/run/user/$(id -u)"
export XDG_RUNTIME_DIR

# API key loading handled by agent-wrapper.sh via the brokered launcher path.

if ! git rev-parse --show-toplevel >/dev/null 2>&1; then
  git init -q
fi

while true; do
  if zmx list --short 2>/dev/null | grep -Fxq "$DEV_AGENT_SESSION_NAME"; then
    sleep "$DEV_AGENT_POLL_INTERVAL_SEC"
    continue
  fi

  zmx run "$DEV_AGENT_SESSION_NAME" "$DEV_AGENT_TASK_SCRIPT"
  sleep "$DEV_AGENT_POLL_INTERVAL_SEC"
done
