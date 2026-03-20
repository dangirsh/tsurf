#!/usr/bin/env bash
# examples/bootstrap/bootstrap-ovh.sh — Zero-touch OVH VPS NixOS bootstrap
#
# USAGE:
#   1. In OVH control panel, reinstall VPS with Ubuntu.
#      When asked for an SSH key, paste the key this script prints.
#   2. Run this script — it handles everything else automatically.
#
# WHAT IT DOES:
#   Phase 0 — Generate deploy key (once); print it for OVH reinstall wizard
#   Phase 1 — Poll until SSH is available (ubuntu@ or root@)
#   Phase 1b — Handle OVH PAM password expiry: change ubuntu password, copy key to root
#   Phase 2 — Run nixos-anywhere to install NixOS (wipes and repartitions disk)
#   Phase 3 — Poll until Tailscale joins the tailnet (confirms sops + networking work)
#
# REQUIREMENTS: nix, tailscale (running on this machine), python3 + pexpect
#
# @decision BOOT-01: Single script, zero interaction after VPS reinstall.
# @decision BOOT-02: Deploy key in tmp/ (gitignored); generated once, stable across retries.
# @decision BOOT-03: Disk layout /dev/sda is correct for fresh Ubuntu (no rescue disk present).
# @decision BOOT-04: Tailscale joining = healthy signal (confirms sops decrypt + networking).
# @decision BOOT-05: PAM password expiry handled via pexpect; new password is ephemeral
#   (Ubuntu gets wiped by nixos-anywhere immediately after). If root@ already works
#   (rescue mode or key already in root), the ubuntu@ step is skipped entirely.

set -euo pipefail

FLAKE_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
VPS_IP="<OVH_PUBLIC_IP>"
# DEPLOY_KEY: override with OVH_DEPLOY_KEY env var if the OVH wizard used a different key
# than the auto-generated one (e.g. a pre-registered key from your OVH account).
# Example: OVH_DEPLOY_KEY=~/.ssh/id_ed25519 bash examples/bootstrap/bootstrap-ovh.sh
DEPLOY_KEY="${OVH_DEPLOY_KEY:-$FLAKE_DIR/tmp/ovh_deploy_key}"
EXTRA_FILES="$FLAKE_DIR/tmp/ovh-host-keys"
FLAKE_TARGET="$FLAKE_DIR#ovh"
TAILSCALE_HOSTNAME="neurosys-dev"

# Ephemeral random password for Ubuntu PAM change (Ubuntu is wiped by nixos-anywhere).
OVH_NEW_PASS="$(openssl rand -base64 16)"

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

if ! python3 -c "import pexpect" 2>/dev/null; then
  echo "ERROR: python3 pexpect module not found."
  echo "       Install with: pip3 install pexpect  or  nix-shell -p python3Packages.pexpect"
  exit 1
fi

if ! command -v openssl &>/dev/null; then
  echo "ERROR: openssl not found. Required for random password generation."
  echo "       Install with: nix-shell -p openssl"
  exit 1
fi

# ────────────────────────────────────────────────────────────────────────────
# Phase 1: Wait for SSH (root@ first — works in rescue mode or if key already there)
# ────────────────────────────────────────────────────────────────────────────
echo "==> [Phase 1] Polling for SSH on ${VPS_IP}..."
echo "    (First tries root@; falls back to ubuntu@ with PAM handling)"
echo ""

ssh-keygen -R "$VPS_IP" 2>/dev/null || true

ROOT_SSH_OK=0
UBUNTU_SSH_OK=0
ATTEMPT=0

# Poll until EITHER root@ or ubuntu@ (key-based) responds.
while true; do
  ATTEMPT=$((ATTEMPT + 1))

  if ssh "${SSH_OPTS[@]}" "root@${VPS_IP}" "exit 0" 2>/dev/null; then
    ROOT_SSH_OK=1
    echo "  root@ SSH is up (key auth works directly)!"
    break
  fi

  # Try ubuntu@ — capture output to detect PAM expiry even when command fails.
  # OVH images use pam_unix with expired passwords; key auth succeeds but PAM blocks
  # the command with "Password change required but no TTY available" (exit 1).
  # We must NOT use 2>/dev/null here so we can detect that message.
  UBUNTU_OUT=$(ssh "${SSH_OPTS[@]}" "ubuntu@${VPS_IP}" "exit 0" 2>&1) && {
    UBUNTU_SSH_OK=1
    echo "  ubuntu@ SSH is up (key auth works)!"
    break
  } || {
    if echo "$UBUNTU_OUT" | grep -qi "password\|expired\|TTY"; then
      UBUNTU_SSH_OK=1
      echo "  ubuntu@ is up (PAM expiry detected — will handle in Phase 1b)"
      break
    fi
  }

  if (( ATTEMPT % 12 == 0 )); then
    echo "  Still waiting (${ATTEMPT} attempts, $((ATTEMPT * 8))s elapsed)..."
  fi
  sleep 8
done

echo ""

# ────────────────────────────────────────────────────────────────────────────
# Phase 1b: PAM password expiry handling (only if we connected as ubuntu@)
# ────────────────────────────────────────────────────────────────────────────
# OVH Ubuntu images force a password change on first login via PAM even when
# using key-based auth (pam_unix + pam_pwquality enforce it). This causes
# interactive SSH sessions to get "Current password:" before executing any
# command. We use pexpect to handle the change, then copy the deploy key to
# root so nixos-anywhere can run as root.
# ────────────────────────────────────────────────────────────────────────────

if [[ "$UBUNTU_SSH_OK" -eq 1 ]]; then
  echo "==> [Phase 1b] Checking for OVH PAM password expiry on ubuntu@${VPS_IP}..."

  # Prompt for the OVH initial password (or use OVH_INIT_PASS env var if set).
  if [[ -z "${OVH_INIT_PASS:-}" ]]; then
    read -r -s -p "Enter OVH initial ubuntu password (shown in OVH reinstall wizard): " OVH_INIT_PASS
    echo ""
  else
    echo "  Using OVH_INIT_PASS from environment."
  fi

  python3 - <<PYEOF
import sys, os, pexpect

deploy_key = os.environ.get("DEPLOY_KEY") or "$DEPLOY_KEY"
vps_ip     = "$VPS_IP"
init_pass  = """$OVH_INIT_PASS"""
new_pass   = "$OVH_NEW_PASS"

ssh_cmd = (
    f"ssh -i {deploy_key} -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "
    f"-o ConnectTimeout=15 -tt ubuntu@{vps_ip} "
    f"'sudo mkdir -p /root/.ssh && sudo cp /home/ubuntu/.ssh/authorized_keys "
    f"/root/.ssh/authorized_keys && sudo chmod 700 /root/.ssh && "
    f"sudo chmod 600 /root/.ssh/authorized_keys && echo KEYS_COPIED'"
)

print(f"  Connecting: ssh ubuntu@{vps_ip} ...")
child = pexpect.spawn(ssh_cmd, timeout=60, encoding="utf-8")
child.logfile_read = sys.stdout

idx = child.expect([
    "Current password:",   # 0 — PAM expiry prompt
    r"\\\$",               # 1 — shell prompt (no expiry)
    "KEYS_COPIED",         # 2 — command ran fine
    pexpect.EOF,           # 3
    pexpect.TIMEOUT,       # 4
])

if idx == 0:
    print("\n  PAM expiry detected — changing password...")
    child.sendline(init_pass)
    child.expect("New password:")
    child.sendline(new_pass)
    child.expect("Retype new password:")
    child.sendline(new_pass)
    # PAM closes the connection after the password change.
    child.expect([pexpect.EOF, pexpect.TIMEOUT], timeout=30)
    child.close()

    print("  Password changed. Reconnecting to copy key to root...")
    child2 = pexpect.spawn(ssh_cmd, timeout=60, encoding="utf-8")
    child2.logfile_read = sys.stdout
    result = child2.expect(["KEYS_COPIED", pexpect.EOF, pexpect.TIMEOUT], timeout=30)
    child2.close()
    if result != 0:
        print("ERROR: Failed to copy deploy key to root after password change.", file=sys.stderr)
        sys.exit(1)
    print("  Deploy key copied to /root/.ssh/authorized_keys.")

elif idx == 2:
    child.close()
    print("  No PAM expiry — key already in root (or sudo worked cleanly).")
elif idx in (1,):
    # We got a shell prompt without KEYS_COPIED — send the commands explicitly.
    child.sendline(
        "sudo mkdir -p /root/.ssh && sudo cp /home/ubuntu/.ssh/authorized_keys "
        "/root/.ssh/authorized_keys && sudo chmod 700 /root/.ssh && "
        "sudo chmod 600 /root/.ssh/authorized_keys && echo KEYS_COPIED"
    )
    child.expect("KEYS_COPIED", timeout=30)
    child.close()
    print("  Deploy key copied to /root/.ssh/authorized_keys.")
else:
    print(f"ERROR: Unexpected pexpect result idx={idx}. Check SSH connectivity.", file=sys.stderr)
    sys.exit(1)

print("  ubuntu@ PAM step complete.")
PYEOF

  echo ""
  echo "  Verifying root@ SSH access..."
  VERIFY_ATTEMPT=0
  while ! ssh "${SSH_OPTS[@]}" "root@${VPS_IP}" "exit 0" 2>/dev/null; do
    VERIFY_ATTEMPT=$((VERIFY_ATTEMPT + 1))
    if (( VERIFY_ATTEMPT >= 5 )); then
      echo "ERROR: root@ SSH still not working after key copy. Aborting."
      exit 1
    fi
    sleep 3
  done
  echo "  root@ SSH confirmed."
  echo ""
fi

# At this point root@ SSH always works (either it worked from the start,
# or we just copied the key via the ubuntu@ PAM flow).
echo "  System info:"
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
echo "║  Bootstrap COMPLETE — base NixOS installed                        ║"
echo "╚══════════════════════════════════════════════════════════════════╝"
echo ""
echo "  Host:         ${TAILSCALE_HOSTNAME}"
echo "  Tailscale IP: ${TAILSCALE_IP}"
echo "  SSH:          ssh root@${TAILSCALE_HOSTNAME}"
echo ""
echo "╔══════════════════════════════════════════════════════════════════╗"
echo "║  REQUIRED NEXT STEP: Deploy private overlay                       ║"
echo "╚══════════════════════════════════════════════════════════════════╝"
echo ""
echo "  The server has the PUBLIC base config (no private services)."
echo "  You MUST now deploy the private overlay to get:"
echo "    - Real SSH keys + your-user user"
echo "    - nginx, Matrix/Conduit, private agents, etc."
echo ""
echo "    cd /data/projects/private-neurosys"
echo "    ./scripts/deploy.sh --node neurosys-dev --first-deploy"
echo ""
echo "  WARNING: Do NOT run ./scripts/deploy.sh --node neurosys-dev from the"
echo "  PUBLIC repo (neurosys) — it will strip private services and"
echo "  lock you out. The public deploy.sh hard-refuses --node neurosys-dev."
echo ""
