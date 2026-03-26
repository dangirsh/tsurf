#!/usr/bin/env bats
# tests/live/service-health.bats — Systemd unit health checks for tsurf hosts.
# @decision TEST-48-01: Host-aware service checks use skip guards for role-specific units.

load "../lib/common"
bats_load_library bats-support
bats_load_library bats-assert

# Validates NET-028: sshd must be enabled
@test "${HOST}: sshd.service is active" {
  assert_unit_active "sshd.service"
}

# Validates BAS-008: weekly garbage collection
@test "${HOST}: nix-gc.timer is enabled" {
  run remote systemctl is-enabled nix-gc.timer
  assert_success
}

# Validates BAK-007: daily backup timer
@test "${HOST}: restic-backups-b2.timer is enabled (if present)" {
  if ! remote systemctl list-unit-files restic-backups-b2.timer --no-legend | grep -q restic-backups-b2; then
    skip "restic backup timer not installed on this host"
  fi
  run remote systemctl is-enabled restic-backups-b2.timer
  assert_success
}

@test "${HOST}: no systemd units are in failed state" {
  local failed
  failed="$(remote systemctl --failed --no-legend --no-pager 2>&1 | sed '/^$/d')" || true
  if [[ -n "$failed" ]]; then
    echo "FAIL: failed systemd units detected"
    echo "DEBUG: $failed"
    echo "DEBUG: ssh ${SSH_USER}@${HOST} systemctl --failed --no-pager"
    return 1
  fi
}
