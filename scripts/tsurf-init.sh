#!/usr/bin/env bash
# tsurf-init.sh — Minimal CLI wizard for bootstrapping a tsurf deployment.
# Generates SSH key pair, optionally derives sops age key, validates setup.
# Usage: tsurf-init [--key-path PATH] [--age]
set -euo pipefail

KEY_PATH="${HOME}/.ssh/break-glass-emergency"
GENERATE_AGE=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --key-path) KEY_PATH="$2"; shift 2 ;;
    --age) GENERATE_AGE=true; shift ;;
    -h|--help)
      echo "Usage: tsurf-init [--key-path PATH] [--age]"
      echo ""
      echo "  --key-path PATH    SSH key path (default: ~/.ssh/break-glass-emergency)"
      echo "  --age              Also derive a sops age key from the SSH host key"
      exit 0
      ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

echo "=== tsurf init ==="

# --- 1. Generate root SSH ed25519 key pair ---
if [[ -f "${KEY_PATH}" ]]; then
  echo "[ok] SSH key already exists: ${KEY_PATH}"
else
  echo "[..] Generating ed25519 key pair: ${KEY_PATH}"
  mkdir -p "$(dirname "${KEY_PATH}")"
  ssh-keygen -t ed25519 -C break-glass-emergency -f "${KEY_PATH}" -N ""
  echo "[ok] Key generated."
fi

PUB_KEY=$(cat "${KEY_PATH}.pub")
echo ""
echo "Public key (add to your private overlay users.nix or break-glass-ssh.nix):"
echo "  ${PUB_KEY}"
echo ""

# --- 2. Optionally derive sops age key from SSH host key ---
if [[ "${GENERATE_AGE}" == "true" ]]; then
  SSH_HOST_KEY="/etc/ssh/ssh_host_ed25519_key"
  if [[ ! -f "${SSH_HOST_KEY}" ]]; then
    SSH_HOST_KEY="/persist/etc/ssh/ssh_host_ed25519_key"
  fi
  if [[ -f "${SSH_HOST_KEY}" ]]; then
    if command -v ssh-to-age >/dev/null 2>&1; then
      AGE_KEY=$(ssh-to-age -private-key -i "${SSH_HOST_KEY}" 2>/dev/null || true)
      if [[ -n "${AGE_KEY}" ]]; then
        AGE_DIR="${HOME}/.config/sops/age"
        mkdir -p "${AGE_DIR}"
        echo "${AGE_KEY}" > "${AGE_DIR}/keys.txt"
        chmod 600 "${AGE_DIR}/keys.txt"
        echo "[ok] Age key derived and written to ${AGE_DIR}/keys.txt"
      else
        echo "[!!] ssh-to-age failed to derive key from ${SSH_HOST_KEY}"
      fi
    else
      echo "[!!] ssh-to-age not found — install it or use: nix shell nixpkgs#ssh-to-age"
    fi
  else
    echo "[!!] No SSH host key found at /etc/ssh/ or /persist/etc/ssh/"
    echo "     Run this on the target host, or provide the key manually."
  fi
fi

# --- 3. Validate ---
ERRORS=0

if [[ ! -f "${KEY_PATH}" ]]; then
  echo "[FAIL] SSH key not found: ${KEY_PATH}"
  ERRORS=$((ERRORS + 1))
fi

if [[ ! -f "${KEY_PATH}.pub" ]]; then
  echo "[FAIL] SSH public key not found: ${KEY_PATH}.pub"
  ERRORS=$((ERRORS + 1))
fi

if [[ "${ERRORS}" -eq 0 ]]; then
  echo ""
  echo "[ok] Setup validated. Next steps:"
  echo "  1. Add the public key above to your private overlay's break-glass-ssh.nix"
  echo "  2. Store the private key in a password manager AND an offline backup"
  echo "  3. Never store the private key on any server or in any git repository"
else
  echo ""
  echo "[FAIL] ${ERRORS} validation error(s). Fix before proceeding."
  exit 1
fi
