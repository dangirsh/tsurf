#!/usr/bin/env bash
# scripts/bootstrap-ovh.sh — Zero-touch OVH VPS NixOS bootstrap
#
# USAGE:
#   1. In OVH control panel, reinstall VPS with Ubuntu.
#      When asked for an SSH key, paste the key this script prints.
#   2. Run this script — it handles everything else automatically.
#
# WHAT IT DOES:
#   Phase 1 — Poll until SSH is available on the fresh Ubuntu VPS
#   Phase 2 — Run nixos-anywhere to install NixOS (wipes and repartitions disk)
#   Phase 3 — Poll until Tailscale joins the tailnet (confirms sops + networking work)
#
# REQUIREMENTS: nix, tailscale (running on this machine)
#
# @decision BOOT-01: Single script, zero interaction after VPS reinstall.
# @decision BOOT-02: Deploy key in tmp/ (gitignored); generated once, stable across retries.
# @decision BOOT-03: Disk layout /dev/sda is correct for fresh Ubuntu (no rescue disk present).
# @decision BOOT-04: Tailscale joining = healthy signal (confirms sops decrypt + networking).

set -euo pipefail

FLAKE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VPS_IP="135.125.196.143"
DEPLOY_KEY="$FLAKE_DIR/tmp/ovh_deploy_key"
EXTRA_FILES="$FLAKE_DIR/tmp/ovh-host-keys"
FLAKE_TARGET="$FLAKE_DIR#ovh"
TAILSCALE_HOSTNAME="neurosys-prod"

SSH_OPTS=(
  -i "$DEPLOY_KEY"
  -o StrictHostKeyChecking=no
  -o UserKnownHostsFile=/dev/null
  -o ConnectTimeout=8
  -o BatchMode=yes
)

# ────────────────────────────────────────────────────────────────────────────
# Setup: generate deploy key if missing
# ────────────────────────────────────────────────────────────────────────────
mkdir -p "$FLAKE_DIR/tmp"

if [[ ! -f "$DEPLOY_KEY" ]]; then
  echo "==> Generating deploy SSH key..."
  ssh-keygen -t ed25519 -f "$DEPLOY_KEY" -N "" -C "ovh-bootstrap-$(date +%Y%m%d)"
fi
chmod 600 "$DEPLOY_KEY"

echo ""
echo "╔══════════════════════════════════════════════════════════════════╗"
echo "║  SSH key to paste in the OVH reinstall wizard:                   ║"
echo "╚══════════════════════════════════════════════════════════════════╝"
echo ""
cat "${DEPLOY_KEY}.pub"
echo ""

# ────────────────────────────────────────────────────────────────────────────
# Verify preconditions
# ────────────────────────────────────────────────────────────────────────────
if [[ ! -f "$EXTRA_FILES/persist/etc/ssh/ssh_host_ed25519_key" ]]; then
  echo "ERROR: SSH host key not found at $EXTRA_FILES/persist/etc/ssh/ssh_host_ed25519_key"
  echo "       This key is required for sops-nix age key derivation."
  exit 1
fi
chmod 600 "$EXTRA_FILES/persist/etc/ssh/ssh_host_ed25519_key"

if ! command -v tailscale &>/dev/null; then
  echo "ERROR: tailscale CLI not found. This machine must be on the same tailnet."
  exit 1
fi

# ────────────────────────────────────────────────────────────────────────────
# Phase 1: Wait for SSH (fresh Ubuntu)
# ────────────────────────────────────────────────────────────────────────────
echo "==> [Phase 1] Polling for SSH on root@${VPS_IP}..."
echo "    (Waits until VPS finishes reinstalling Ubuntu — typically 3-5 min)"
echo ""

ssh-keygen -R "$VPS_IP" 2>/dev/null || true

ATTEMPT=0
while ! ssh "${SSH_OPTS[@]}" "root@${VPS_IP}" "exit 0" 2>/dev/null; do
  ATTEMPT=$((ATTEMPT + 1))
  if (( ATTEMPT % 12 == 0 )); then
    echo "  Still waiting (${ATTEMPT} attempts, $((ATTEMPT * 8))s elapsed)..."
  fi
  sleep 8
done

echo "  SSH is up!"
echo ""
ssh "${SSH_OPTS[@]}" "root@${VPS_IP}" "uname -a && lsblk" 2>/dev/null || true
echo ""

# ────────────────────────────────────────────────────────────────────────────
# Phase 2: nixos-anywhere
# ────────────────────────────────────────────────────────────────────────────
echo "==> [Phase 2] Running nixos-anywhere to install NixOS on /dev/sda..."
echo "    (Wipes disk, installs NixOS, reboots — 10-20 min)"
echo ""

nix run github:nix-community/nixos-anywhere -- \
  --extra-files "$EXTRA_FILES" \
  --flake "$FLAKE_TARGET" \
  -i "$DEPLOY_KEY" \
  "root@${VPS_IP}" 2>&1

echo ""
echo "  nixos-anywhere complete — VPS is rebooting into NixOS."
echo ""

# ────────────────────────────────────────────────────────────────────────────
# Phase 3: Wait for Tailscale
# ────────────────────────────────────────────────────────────────────────────
echo "==> [Phase 3] Waiting for ${TAILSCALE_HOSTNAME} to appear in tailnet..."
echo "    (Confirms: sops decrypted, Tailscale auth applied, networking up)"
echo ""

ATTEMPT=0
while ! tailscale status 2>/dev/null | grep -qE "[[:space:]]${TAILSCALE_HOSTNAME}[[:space:]]"; do
  ATTEMPT=$((ATTEMPT + 1))
  if (( ATTEMPT % 6 == 0 )); then
    echo "  Still waiting (${ATTEMPT} attempts, $((ATTEMPT * 10))s elapsed)..."
  fi
  sleep 10
done

TAILSCALE_IP=$(tailscale status 2>/dev/null | awk "/[[:space:]]${TAILSCALE_HOSTNAME}[[:space:]]/{print \$1}")

echo ""
echo "╔══════════════════════════════════════════════════════════════════╗"
echo "║  Bootstrap COMPLETE                                               ║"
echo "╚══════════════════════════════════════════════════════════════════╝"
echo ""
echo "  Host:         ${TAILSCALE_HOSTNAME}"
echo "  Tailscale IP: ${TAILSCALE_IP}"
echo "  SSH:          ssh root@${TAILSCALE_HOSTNAME}"
echo ""
echo "  Future deploys: ./scripts/deploy.sh --node ovh"
echo ""
