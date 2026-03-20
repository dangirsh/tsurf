#!/usr/bin/env bash
# scripts/sshd-liveness-check.sh — sshd liveness check with auto-rollback
# @decision SEC-70-02: 3 consecutive failures (15 min sustained) trigger rollback.
#   Anti-loop: skips if rollback occurred <10 min ago.
#   Deploy-aware: skips during active deploys or deploy-watchdog.
set -euo pipefail

STATE_DIR="/var/lib/sshd-liveness-check"
FAILURE_FILE="$STATE_DIR/failure-count"
LAST_ROLLBACK_FILE="$STATE_DIR/last-rollback"
mkdir -p "$STATE_DIR"

# Skip during active deploys — deploy-rs has its own rollback mechanism.
if [ -d /var/lock/tsurf-neurosys-deploy.lock ] || \
   [ -d /var/lock/tsurf-ovh-deploy.lock ]; then
  echo "sshd-liveness: deploy in progress — skipping check"
  exit 0
fi

# Skip when deploy-watchdog timer is active (deploy.sh manages rollback)
if systemctl is-active --quiet deploy-watchdog.timer 2>/dev/null; then
  echo "sshd-liveness: deploy watchdog active — skipping check"
  exit 0
fi

# Check 1: sshd.service is active
SSHD_OK=true
if ! systemctl is-active --quiet sshd.service; then
  echo "sshd-liveness: FAIL — sshd.service is not active"
  SSHD_OK=false
fi

# Check 2: port 22 is bound
PORT_OK=true
if ! ss -tlnp | grep -q ':22 '; then
  echo "sshd-liveness: FAIL — port 22 is not bound"
  PORT_OK=false
fi

# Both checks passed — reset failure counter
if [ "$SSHD_OK" = true ] && [ "$PORT_OK" = true ]; then
  echo "sshd-liveness: OK"
  echo 0 > "$FAILURE_FILE"
  exit 0
fi

# Increment failure counter
FAILURES=$(cat "$FAILURE_FILE" 2>/dev/null || echo 0)
FAILURES=$((FAILURES + 1))
echo "$FAILURES" > "$FAILURE_FILE"
echo "sshd-liveness: failure $FAILURES/3"

# Only rollback after 3 consecutive failures (15 min of sustained breakage)
if [ "$FAILURES" -lt 3 ]; then
  exit 0
fi

# Anti-loop: skip rollback if one occurred <10 min ago
if [ -f "$LAST_ROLLBACK_FILE" ]; then
  LAST_TIME=$(cat "$LAST_ROLLBACK_FILE")
  NOW=$(date +%s)
  ELAPSED=$((NOW - LAST_TIME))
  if [ "$ELAPSED" -lt 600 ]; then
    echo "sshd-liveness: SKIPPING rollback (rolled back ${ELAPSED}s ago, <10 min)"
    echo "Manual recovery required — see CLAUDE.md Recovery (Out-of-Band) section"
    echo 0 > "$FAILURE_FILE"
    exit 1
  fi
fi

# 3 consecutive failures, no recent rollback — trigger rollback
echo "sshd-liveness: 3 consecutive failures — triggering NixOS generation rollback"
echo 0 > "$FAILURE_FILE"
date +%s > "$LAST_ROLLBACK_FILE"
nixos-rebuild switch --rollback 2>&1 || {
  echo "sshd-liveness: rollback FAILED — manual recovery required (see CLAUDE.md Recovery (Out-of-Band) section)"
  exit 1
}
echo "sshd-liveness: rollback completed"
