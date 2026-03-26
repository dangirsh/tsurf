#!/usr/bin/env bash
# tsurf-status.sh — Check persistent tsurf systemd units on one or more hosts.
# Accepts deploy-rs node names, raw hostnames, or `all` to expand every deploy node in the current flake.
# @decision OPS-156-01: Report only persistent systemd units. Interactive agent sessions are transient and should not appear in fleet status.
set -euo pipefail

UNITS=(
  sshd.service
  nftables.service
  sops-install-secrets.service
  tsurf-cass-index.timer
  restic-backups-b2.timer
  tsurf-cost-tracker.timer
)

resolve_flake_dir() {
  local script_path="$1"
  local candidate
  candidate="$(cd "$(dirname "$script_path")" && pwd -P)"

  while [[ "$candidate" != "/" ]]; do
    if [[ -f "$candidate/flake.nix" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
    candidate="$(dirname "$candidate")"
  done

  return 1
}

FLAKE_DIR="$(resolve_flake_dir "${BASH_SOURCE[0]}")"

usage() {
  echo "Usage: tsurf-status <deploy-node|hostname|all> [...]"
  echo ""
  echo "Checks persistent tsurf systemd units over SSH as root."
  exit 1
}

list_deploy_nodes() {
  nix eval --json "${FLAKE_DIR}#deploy.nodes" 2>/dev/null | jq -r 'keys[]'
}

resolve_target_host() {
  local target="$1"
  local host=""
  host="$(nix eval --json "${FLAKE_DIR}#deploy.nodes" 2>/dev/null \
    | jq -r --arg key "${target}" '.[$key].hostname // empty' 2>/dev/null || true)"
  if [[ -n "${host}" ]]; then
    printf '%s\n' "${host}"
  else
    printf '%s\n' "${target}"
  fi
}

expand_targets() {
  local target
  for target in "$@"; do
    if [[ "${target}" == "all" ]]; then
      if ! list_deploy_nodes; then
        echo "ERROR: could not resolve deploy.nodes from ${FLAKE_DIR}" >&2
        exit 1
      fi
      continue
    fi
    printf '%s\n' "${target}"
  done
}

check_host() {
  local label="$1"
  local host="$2"
  echo "=== ${label} (${host}) ==="

  if ! ssh -o ConnectTimeout=5 -o BatchMode=yes "root@${host}" true 2>/dev/null; then
    echo "  [UNREACHABLE] Cannot SSH to root@${host}"
    echo ""
    return
  fi

  for unit in "${UNITS[@]}"; do
    local enabled
    enabled="$(ssh -o ConnectTimeout=5 -o BatchMode=yes "root@${host}" \
      "systemctl is-enabled '${unit}' 2>/dev/null || echo missing" 2>/dev/null)"

    if [[ "${enabled}" == "missing" ]]; then
      printf "  %-30s %s\n" "${unit}" "-"
      continue
    fi

    local active
    active="$(ssh -o ConnectTimeout=5 -o BatchMode=yes "root@${host}" \
      "systemctl is-active '${unit}' 2>/dev/null || true" 2>/dev/null)"

    local status_icon
    case "${active}" in
      active)   status_icon="[ok]" ;;
      inactive) status_icon="[--]" ;;
      failed)   status_icon="[FAIL]" ;;
      *)        status_icon="[??]" ;;
    esac

    printf "  %-30s %s %s (%s)\n" "${unit}" "${status_icon}" "${active}" "${enabled}"
  done
  echo ""
}

if [[ $# -eq 0 ]]; then
  usage
fi

while IFS= read -r target; do
  [[ -n "${target}" ]] || continue
  check_host "${target}" "$(resolve_target_host "${target}")"
done < <(expand_targets "$@")
