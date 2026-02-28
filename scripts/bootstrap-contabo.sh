#!/usr/bin/env bash
# scripts/bootstrap-contabo.sh — Zero-touch Contabo VPS NixOS bootstrap
#
# USAGE:
#   1. In Contabo control panel, reinstall VPS with Ubuntu.
#      Contabo provides a root password via email after reinstall.
#   2. Set CONTABO_PASS env var (or it will be read from default below).
#   3. Run this script — it handles everything else automatically.
#
# WHAT IT DOES:
#   Phase 0 — Verify preconditions (sshpass, host keys, tailscale)
#   Phase 1 — Clear old known_hosts entry, poll until SSH is available via password
#   Phase 1b — Generate a temporary deploy key, copy it to root@ via sshpass
#   Phase 2 — Run nixos-anywhere using the temporary key (wipes and repartitions disk)
#   Phase 3 — Poll until Tailscale hostname appears in tailnet (confirms networking)
#
# REQUIREMENTS: nix, tailscale (running on this machine), sshpass (auto-installed via nix)
#
# @decision BOOT-01: Single script, zero interaction after VPS reinstall + env var set.
# @decision BOOT-02: Temporary deploy key generated fresh each bootstrap run in tmp/;
#   it has a very short lifetime — Ubuntu is wiped by nixos-anywhere immediately after
#   the key is used. The key is never persisted to the flake or secrets.
# @decision BOOT-03: sshpass auto-fallback via `nix shell nixpkgs#sshpass` avoids
#   requiring sshpass to be pre-installed on the admin machine.
# @decision BOOT-04: Contabo gives root directly (no ubuntu@ user, no PAM expiry);
#   no pexpect dependency needed — shell-level sshpass is sufficient.
# @decision BOOT-05: Tailscale joining = healthy signal (confirms sops decrypt + networking).
# @decision BOOT-06: CONTABO_PASS is the ephemeral Ubuntu root password from Contabo's
#   reinstall email. Ubuntu is wiped immediately; the password becomes irrelevant.
#   It is never written to disk or committed to git.

set -euo pipefail

FLAKE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VPS_IP="161.97.74.121"
DEPLOY_KEY="$FLAKE_DIR/tmp/contabo_deploy_key"
EXTRA_FILES="$FLAKE_DIR/tmp/neurosys-host-keys"
FLAKE_TARGET="/data/projects/private-neurosys#neurosys"
TAILSCALE_HOSTNAME="neurosys"

# ────────────────────────────────────────────────────────────────────────────
# sshpass auto-fallback: if sshpass is not on PATH, re-exec via nix shell.
# @decision BOOT-03: avoids requiring sshpass to be pre-installed.
# ────────────────────────────────────────────────────────────────────────────
if ! command -v sshpass &>/dev/null; then
  echo "==> sshpass not found on PATH — re-executing via nix shell nixpkgs#sshpass..."
  exec nix shell nixpkgs#sshpass -c "$0" "$@"
fi

# ────────────────────────────────────────────────────────────────────────────
# Password: read from environment or fall back to the default.
# Contabo sends this via email after Ubuntu reinstall.
# @decision BOOT-06: ephemeral — Ubuntu is wiped immediately by nixos-anywhere.
# ────────────────────────────────────────────────────────────────────────────
CONTABO_PASS="${CONTABO_PASS:-fuckingcontabosecurityshit}"

# ────────────────────────────────────────────────────────────────────────────
# Phase 0: Verify preconditions
# ────────────────────────────────────────────────────────────────────────────
echo "==> [Phase 0] Verifying preconditions..."

# Ensure tmp/ exists for deploy key generation.
mkdir -p "$FLAKE_DIR/tmp"

if [[ ! -f "$EXTRA_FILES/persist/etc/ssh/ssh_host_ed25519_key" ]]; then
  echo "ERROR: SSH host key not found at $EXTRA_FILES/persist/etc/ssh/ssh_host_ed25519_key"
  echo "       This key is required for sops-nix age key derivation."
  echo "       Generate with: ssh-keygen -t ed25519 -f $EXTRA_FILES/persist/etc/ssh/ssh_host_ed25519_key -N ''"
  exit 1
fi
chmod 600 "$EXTRA_FILES/persist/etc/ssh/ssh_host_ed25519_key"

if ! command -v tailscale &>/dev/null; then
  echo "ERROR: tailscale CLI not found. This machine must be on the same tailnet."
  exit 1
fi

echo "  Preconditions OK."
echo ""

# ────────────────────────────────────────────────────────────────────────────
# Phase 1: Clear known_hosts entry, poll until SSH is up
# ────────────────────────────────────────────────────────────────────────────
echo "==> [Phase 1] Clearing old SSH known_hosts entry for ${VPS_IP}..."
ssh-keygen -R "$VPS_IP" 2>/dev/null || true
echo ""

echo "  Polling for SSH on ${VPS_IP} using password auth..."
echo "  (Contabo gives root directly — no PAM expiry handling needed)"
echo ""

ATTEMPT=0
while true; do
  ATTEMPT=$((ATTEMPT + 1))

  # Test SSH access using password. sshpass returns 0 if the remote command succeeds.
  if sshpass -p "$CONTABO_PASS" ssh \
      -o StrictHostKeyChecking=no \
      -o UserKnownHostsFile=/dev/null \
      -o ConnectTimeout=8 \
      "root@${VPS_IP}" "exit 0" 2>/dev/null; then
    echo "  root@ SSH is up (password auth works)!"
    break
  fi

  if (( ATTEMPT % 12 == 0 )); then
    echo "  Still waiting (${ATTEMPT} attempts, $((ATTEMPT * 8))s elapsed)..."
  fi
  sleep 8
done

echo ""

# ────────────────────────────────────────────────────────────────────────────
# Phase 1b: Generate temporary deploy key and copy to root@
# nixos-anywhere requires key-based auth (it forks multiple ssh processes and
# cannot feed a password interactively). We generate a fresh ephemeral key,
# copy it via sshpass, then nixos-anywhere can take it from there.
# @decision BOOT-02: Key is ephemeral; Ubuntu is wiped immediately after use.
# ────────────────────────────────────────────────────────────────────────────
echo "==> [Phase 1b] Generating temporary deploy key and copying to root@${VPS_IP}..."

if [[ -f "$DEPLOY_KEY" ]]; then
  rm -f "$DEPLOY_KEY" "${DEPLOY_KEY}.pub"
fi
ssh-keygen -t ed25519 -f "$DEPLOY_KEY" -N "" -C "contabo-bootstrap-$(date +%Y%m%d)"
chmod 600 "$DEPLOY_KEY"

# ssh-copy-id via sshpass copies the public key into root's authorized_keys.
sshpass -p "$CONTABO_PASS" ssh-copy-id \
  -i "${DEPLOY_KEY}.pub" \
  -o StrictHostKeyChecking=no \
  -o UserKnownHostsFile=/dev/null \
  "root@${VPS_IP}"

echo "  Deploy key copied. Verifying key-based SSH access..."

SSH_KEY_OPTS=(
  -i "$DEPLOY_KEY"
  -o StrictHostKeyChecking=no
  -o UserKnownHostsFile=/dev/null
  -o ConnectTimeout=8
  -o BatchMode=yes
)

VERIFY_ATTEMPT=0
while ! ssh "${SSH_KEY_OPTS[@]}" "root@${VPS_IP}" "exit 0" 2>/dev/null; do
  VERIFY_ATTEMPT=$((VERIFY_ATTEMPT + 1))
  if (( VERIFY_ATTEMPT >= 5 )); then
    echo "ERROR: root@ key-based SSH not working after key copy. Aborting."
    exit 1
  fi
  sleep 3
done

echo "  Key-based SSH confirmed."
echo ""
echo "  System info:"
ssh "${SSH_KEY_OPTS[@]}" "root@${VPS_IP}" "uname -a && lsblk" 2>/dev/null || true
echo ""

# ────────────────────────────────────────────────────────────────────────────
# Phase 2: nixos-anywhere
# ────────────────────────────────────────────────────────────────────────────
echo "==> [Phase 2] Running nixos-anywhere to install NixOS..."
echo "    Target:  ${FLAKE_TARGET}"
echo "    Host:    root@${VPS_IP}"
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

# Clean up the ephemeral deploy key — it is now permanently useless
# (the authorized_keys file was wiped with Ubuntu during nixos-anywhere).
rm -f "$DEPLOY_KEY" "${DEPLOY_KEY}.pub"
echo "  Ephemeral deploy key removed."
echo ""

# ────────────────────────────────────────────────────────────────────────────
# Phase 3: Wait for Tailscale
# ────────────────────────────────────────────────────────────────────────────
echo "==> [Phase 3] Waiting for '${TAILSCALE_HOSTNAME}' to appear in tailnet..."
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
echo "  Future deploys: ./scripts/deploy.sh"
echo ""
