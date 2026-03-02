#!/usr/bin/env bats
# tests/live/service-health.bats — Systemd unit health checks for neurosys hosts.
# @decision TEST-48-01: Host-aware service checks use skip guards for role-specific units.

load "../lib/common"
bats_load_library bats-support/load
bats_load_library bats-assert/load

@test "${HOST}: tailscaled.service is active" {
  assert_unit_active "tailscaled.service"
}

@test "${HOST}: docker.service is active" {
  assert_unit_active "docker.service"
}

@test "${HOST}: syncthing.service is active" {
  assert_unit_active "syncthing.service"
}

@test "${HOST}: sshd.service is active" {
  assert_unit_active "sshd.service"
}

@test "${HOST}: nix-gc.timer is enabled" {
  run remote systemctl is-enabled nix-gc.timer
  assert_success
}

@test "${HOST}: tailscaled.service is enabled" {
  run remote systemctl is-enabled tailscaled.service
  assert_success
}

@test "${HOST}: homepage-dashboard.service is active (neurosys only)" {
  if ! is_neurosys; then
    skip "homepage-dashboard only on neurosys"
  fi
  assert_unit_active "homepage-dashboard.service"
}

@test "${HOST}: restic-backups-b2.timer is enabled (neurosys only)" {
  if ! is_neurosys; then
    skip "restic backup timer only on neurosys"
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

  local expected_prefix
  if is_neurosys; then
    expected_prefix="neurosys"
  else
    expected_prefix="neurosys-dev"
  fi

  if [[ "$ts_hostname" != "${expected_prefix}"* ]]; then
    echo "FAIL: tailscale hostname='$ts_hostname', expected prefix='${expected_prefix}'"
    return 1
  fi
}
