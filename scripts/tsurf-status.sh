#!/usr/bin/env bash
# tsurf-status.sh — Check systemd service status on tsurf hosts.
# Usage: tsurf-status <hostname|all> [hostname2 ...]
set -euo pipefail

# Services to check — agent/infra related
SERVICES=(
  sshd
  nftables
  sops-install-secrets
  agent-launch-claude
  dev-agent
  restic-backups
  cost-tracker
)

usage() {
  echo "Usage: tsurf-status <hostname> [hostname2 ...]"
  echo ""
  echo "Checks systemd service status on tsurf hosts via SSH."
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

  for svc in "${SERVICES[@]}"; do
    # Check if unit exists, then get its status
    local result
    result=$(ssh -o ConnectTimeout=5 -o BatchMode=yes "root@${host}" \
      "systemctl is-enabled '${svc}.service' 2>/dev/null || echo missing" 2>/dev/null)

    if [[ "${result}" == "missing" ]]; then
      printf "  %-30s %s\n" "${svc}" "-"
      continue
    fi

    local active
    active=$(ssh -o ConnectTimeout=5 -o BatchMode=yes "root@${host}" \
      "systemctl is-active '${svc}.service' 2>/dev/null || true" 2>/dev/null)

    local status_icon
    case "${active}" in
      active)   status_icon="[ok]" ;;
      inactive) status_icon="[--]" ;;
      failed)   status_icon="[FAIL]" ;;
      *)        status_icon="[??]" ;;
    esac

    printf "  %-30s %s %s (%s)\n" "${svc}" "${status_icon}" "${active}" "${result}"
  done
  echo ""
}

for host in "${HOSTS[@]}"; do
  check_host "${host}"
done
