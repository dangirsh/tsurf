#!/usr/bin/env bats
# tests/live/service-health.bats — Systemd unit health checks for tsurf hosts.
# @decision TEST-48-01: Host-aware service checks use skip guards for role-specific units.

load "../lib/common"
bats_load_library bats-support
bats_load_library bats-assert

# Validates NET-023: Tailscale enabled
@test "${HOST}: tailscaled.service is active" {
  assert_unit_active "tailscaled.service"
}

# Validates NET-028: sshd must be enabled
@test "${HOST}: sshd.service is active" {
  assert_unit_active "sshd.service"
}

# Validates BAS-008: weekly garbage collection
@test "${HOST}: nix-gc.timer is enabled" {
  run remote systemctl is-enabled nix-gc.timer
  assert_success
}

@test "${HOST}: tailscaled.service is enabled" {
  run remote systemctl is-enabled tailscaled.service
  assert_success
}

# Validates EXT-001, EXT-005: dashboard enabled and active
@test "${HOST}: nix-dashboard.service is active (if present)" {
  if ! remote systemctl list-unit-files nix-dashboard.service --no-legend | grep -q nix-dashboard; then
    skip "nix-dashboard not installed on this host"
  fi
  assert_unit_active "nix-dashboard.service"
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

# Validates NET-023: Tailscale backend running
@test "${HOST}: tailscale backend state is Running" {
  local status_json
  status_json="$(remote tailscale status --json 2>&1)" || {
    echo "FAIL: tailscale status --json failed"
    echo "DEBUG: ssh ${SSH_USER}@${HOST} tailscale status --json"
    return 1
  }

  local backend_state
  backend_state="$(echo "$status_json" | jq -r ".BackendState" 2>/dev/null)" || {
    echo "FAIL: could not parse tailscale status JSON"
    echo "DEBUG: $status_json"
    return 1
  }
  if [[ "$backend_state" != "Running" ]]; then
    echo "FAIL: BackendState='$backend_state', expected 'Running'"
    echo "DEBUG: ssh ${SSH_USER}@${HOST} tailscale status"
    return 1
  fi
}

@test "${HOST}: tailscale hostname matches expected prefix" {
  local status_json
  status_json="$(remote tailscale status --json 2>&1)" || {
    echo "FAIL: tailscale status --json failed"
    return 1
  }

  local ts_hostname
  ts_hostname="$(echo "$status_json" | jq -r ".Self.HostName" 2>/dev/null)" || {
    echo "FAIL: could not parse tailscale hostname"
    return 1
  }

  if [[ "$ts_hostname" != "${HOST}"* ]]; then
    echo "FAIL: tailscale hostname='$ts_hostname', expected prefix='${HOST}'"
    return 1
  fi
}
