#!/usr/bin/env bash
# tsurf-status.sh — Check systemd service status on tsurf hosts.
# Usage: tsurf-status <hostname> [hostname2 ...]
# @decision OPS-156-01: Report only persistent systemd units. Interactive
#   agent sessions run as transient units with per-launch names, and scheduled
#   jobs are best represented by their timers instead of short-lived oneshot services.
set -euo pipefail

# Units to check — persistent agent/infra related units only.
UNITS=(
  sshd.service
  nftables.service
  sops-install-secrets.service
  tailscaled.service
  dev-agent.service
  restic-backups-b2.timer
  tsurf-cost-tracker.timer
)

usage() {
  echo "Usage: tsurf-status <hostname> [hostname2 ...]"
  echo ""
  echo "Checks systemd unit status on tsurf hosts via SSH."
  echo "Requires SSH access to the target host(s) as root."
  exit 1
}

if [[ $# -eq 0 ]]; then
  usage
fi

HOSTS=("$@")

check_host() {
  local host="$1"
  echo "=== ${host} ==="

  if ! ssh -o ConnectTimeout=5 -o BatchMode=yes "root@${host}" true 2>/dev/null; then
    echo "  [UNREACHABLE] Cannot SSH to root@${host}"
    echo ""
    return
  fi

  for unit in "${UNITS[@]}"; do
    # Check if unit exists, then get its status
    local result
    result=$(ssh -o ConnectTimeout=5 -o BatchMode=yes "root@${host}" \
      "systemctl is-enabled '${unit}' 2>/dev/null || echo missing" 2>/dev/null)

    if [[ "${result}" == "missing" ]]; then
      printf "  %-30s %s\n" "${unit}" "-"
      continue
    fi

    local active
    active=$(ssh -o ConnectTimeout=5 -o BatchMode=yes "root@${host}" \
      "systemctl is-active '${unit}' 2>/dev/null || true" 2>/dev/null)

    local status_icon
    case "${active}" in
      active)   status_icon="[ok]" ;;
      inactive) status_icon="[--]" ;;
      failed)   status_icon="[FAIL]" ;;
      *)        status_icon="[??]" ;;
    esac

    printf "  %-30s %s %s (%s)\n" "${unit}" "${status_icon}" "${active}" "${result}"
  done
  echo ""
}

for host in "${HOSTS[@]}"; do
  check_host "${host}"
done
