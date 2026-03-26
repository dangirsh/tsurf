#!/usr/bin/env bats
# tests/live/secrets.bats — sops-nix secret presence/permission verification.
# @decision TEST-48-01: Tests assert existence and permissions only, never secret values.

load "../lib/common"
bats_load_library bats-support
bats_load_library bats-assert

@test "${HOST}: /run/secrets exists and contains at least one file" {
  local count
  count="$(remote find /run/secrets -maxdepth 1 -type f 2>/dev/null | wc -l)" || {
    echo "FAIL: cannot inspect /run/secrets"
    echo "DEBUG: ssh ${SSH_USER}@${HOST} ls -la /run/secrets/"
    return 1
  }

  if [[ "$count" -lt 1 ]]; then
    echo "FAIL: /run/secrets file count='$count', expected >= 1"
    echo "DEBUG: ssh ${SSH_USER}@${HOST} systemctl status sops-nix --no-pager"
    return 1
  fi
}

@test "${HOST}: wrapper API key secrets are root-owned" {
  assert_secret_exists "/run/secrets/anthropic-api-key" "root"
  assert_secret_exists "/run/secrets/openai-api-key" "root"
}

@test "${HOST}: agent user cannot read wrapper API key secrets directly" {
  run remote "sudo -u ${AGENT_USER} test ! -r /run/secrets/anthropic-api-key && test ! -r /run/secrets/openai-api-key"
  assert_success
}

@test "${HOST}: secret files are not world-readable" {
  local world_readable
  world_readable="$(remote find /run/secrets -maxdepth 1 -type f -perm -o+r 2>/dev/null)" || true
  if [[ -n "$world_readable" ]]; then
    echo "FAIL: world-readable secret files found"
    echo "DEBUG: $world_readable"
    return 1
  fi
}

@test "${HOST}: SSH host key exists for sops age key derivation" {
  local key_path
  key_path="$(remote "sshd -T 2>/dev/null | awk '\$1 == \"hostkey\" && \$2 ~ /ssh_host_ed25519_key$/ { print \$2; exit }'")" || {
    echo "FAIL: could not determine sshd host key path"
    return 1
  }

  if [[ -z "$key_path" ]]; then
    key_path="/etc/ssh/ssh_host_ed25519_key"
  fi

  run remote test -f "$key_path"
  if [[ "$status" -ne 0 ]]; then
    echo "FAIL: expected SSH host key missing at '$key_path'"
    return 1
  fi
}
