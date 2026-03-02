#!/usr/bin/env bats
# tests/live/impermanence.bats — Impermanence mount and persist path verification.
# @decision TEST-48-02: Impermanence assertions must skip cleanly on hosts where /persist is not activated.

load "../lib/common"
bats_load_library bats-support/load
bats_load_library bats-assert/load

# Skip helper for hosts without impermanence activation.
require_impermanence() {
  remote test -d /persist || skip "not an impermanence-activated system (/persist missing)"
}

@test "${HOST}: /persist is a mounted filesystem" {
  require_impermanence

  remote mountpoint -q /persist || {
    echo "FAIL: /persist exists but is not a mountpoint"
    echo "DEBUG: ssh ${SSH_USER}@${HOST} mount | grep persist"
    return 1
  }
}

@test "${HOST}: /persist filesystem type is btrfs" {
  require_impermanence

  local fstype
  fstype="$(remote stat -f -c '%T' /persist 2>&1)" || {
    echo "FAIL: unable to read /persist filesystem type"
    return 1
  }
  if [[ "$fstype" != "btrfs" ]]; then
    echo "FAIL: /persist filesystem type='$fstype', expected 'btrfs'"
    return 1
  fi
}

@test "${HOST}: critical persist directories are present" {
  require_impermanence

  local required_dirs=(
    "/persist/var/lib/tailscale"
    "/persist/etc/ssh"
    "/persist/home/myuser"
    "/persist/data"
  )

  local missing=()
  local path
  for path in "${required_dirs[@]}"; do
    remote test -d "$path" || missing+=("$path")
  done

  if [[ "${#missing[@]}" -gt 0 ]]; then
    echo "FAIL: missing persist directories: ${missing[*]}"
    return 1
  fi
}

@test "${HOST}: /etc/machine-id is persisted via /persist" {
  require_impermanence

  local machine_id
  machine_id="$(remote cat /etc/machine-id 2>&1)" || {
    echo "FAIL: /etc/machine-id is not readable"
    return 1
  }
  if [[ -z "$machine_id" ]] || [[ "$machine_id" == "uninitialized" ]]; then
    echo "FAIL: /etc/machine-id is empty or uninitialized"
    return 1
  fi

  remote test -f /persist/etc/machine-id || {
    echo "FAIL: /persist/etc/machine-id missing"
    return 1
  }
}

@test "${HOST}: root filesystem type is btrfs" {
  require_impermanence

  local root_fstype
  root_fstype="$(remote stat -f -c '%T' / 2>&1)" || {
    echo "FAIL: unable to read root filesystem type"
    return 1
  }
  if [[ "$root_fstype" != "btrfs" ]]; then
    echo "FAIL: root filesystem type='$root_fstype', expected 'btrfs'"
    return 1
  fi
}
