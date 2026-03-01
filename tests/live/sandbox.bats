#!/usr/bin/env bats
# tests/live/sandbox.bats — Bubblewrap sandbox isolation verification.
# @decision TEST-48-02: Isolation tests assert secret path inaccessibility with minimal, deterministic bwrap invocations.

load "../lib/common"
bats_load_library bats-support/load
bats_load_library bats-assert/load

@test "${HOST}: bubblewrap binary is available" {
  remote command -v bwrap >/dev/null 2>&1 || {
    echo "FAIL: bwrap not found in remote PATH"
    echo "DEBUG: ssh ${SSH_USER}@${HOST} command -v bwrap"
    return 1
  }
}

@test "${HOST}: sandbox does not expose /run/secrets" {
  local output
  output="$(remote bwrap \
    --ro-bind /nix/store /nix/store \
    --ro-bind /run/current-system /run/current-system \
    --proc /proc \
    --dev /dev \
    --tmpfs /tmp \
    --ro-bind /etc/resolv.conf /etc/resolv.conf \
    --ro-bind /etc/passwd /etc/passwd \
    --ro-bind /etc/group /etc/group \
    --die-with-parent \
    -- /run/current-system/sw/bin/ls /run/secrets 2>&1)" || {
    return 0
  }

  echo "FAIL: /run/secrets was visible inside sandbox"
  echo "DEBUG: sandbox output: $output"
  return 1
}

@test "${HOST}: sandbox does not expose /home/myuser/.ssh" {
  local output
  output="$(remote bwrap \
    --ro-bind /nix/store /nix/store \
    --ro-bind /run/current-system /run/current-system \
    --proc /proc \
    --dev /dev \
    --tmpfs /tmp \
    --dir /home \
    --dir /home/myuser \
    --ro-bind /etc/passwd /etc/passwd \
    --ro-bind /etc/group /etc/group \
    --die-with-parent \
    -- /run/current-system/sw/bin/ls /home/myuser/.ssh 2>&1)" || {
    return 0
  }

  echo "FAIL: /home/myuser/.ssh was visible inside sandbox"
  echo "DEBUG: sandbox output: $output"
  return 1
}

@test "${HOST}: generated agent wrapper sets SANDBOX env var" {
  if ! is_neurosys; then
    skip "agentd wrapper verification is expected on neurosys"
  fi

  local wrappers
  wrappers="$(remote "find /nix/store -maxdepth 4 -type f -path '*/bin/agent' 2>/dev/null | head -n 30")" || true
  if [[ -z "$wrappers" ]]; then
    skip "no candidate agent wrappers found in /nix/store"
  fi

  local wrapper
  while IFS= read -r wrapper; do
    if remote grep -q "AGENTD_SPAWN" "$wrapper" 2>/dev/null; then
      remote grep -q -- "--setenv SANDBOX 1" "$wrapper" || {
        echo "FAIL: wrapper missing '--setenv SANDBOX 1': $wrapper"
        return 1
      }
      return 0
    fi
  done <<< "$wrappers"

  skip "no generated agent wrapper found (agents may be private-overlay only)"
}
