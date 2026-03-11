#!/usr/bin/env bats
# tests/live/sandbox.bats — Bubblewrap sandbox isolation verification.
# @decision TEST-48-02: Isolation tests assert secret path inaccessibility with minimal, deterministic bwrap invocations.

load "../lib/common"
bats_load_library bats-support
bats_load_library bats-assert

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

