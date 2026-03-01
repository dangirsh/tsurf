#!/usr/bin/env bats
# tests/live/networking.bats — Tailscale, DNS, and nftables deep validation.
# @decision TEST-48-02: Networking tests focus on concrete connectivity and metadata endpoint blocking guarantees.

load "../lib/common"
bats_load_library bats-support/load
bats_load_library bats-assert/load

@test "${HOST}: tailscale has at least one peer" {
  local status_json
  status_json="$(remote tailscale status --json 2>&1)" || {
    echo "FAIL: tailscale status --json failed"
    echo "DEBUG: ssh ${SSH_USER}@${HOST} tailscale status"
    return 1
  }

  local peers
  peers="$(echo "$status_json" | jq '.Peer | length' 2>/dev/null)" || {
    echo "FAIL: could not parse tailscale status JSON"
    return 1
  }
  if [[ "$peers" -lt 1 ]]; then
    echo "FAIL: tailscale peer count='$peers', expected >= 1"
    echo "DEBUG: ssh ${SSH_USER}@${HOST} tailscale status"
    return 1
  fi
}

@test "${HOST}: DNS resolution works for external hosts" {
  remote host github.com >/dev/null 2>&1 || {
    remote curl -sf --max-time 5 https://github.com >/dev/null 2>&1 || {
      echo "FAIL: DNS/HTTPS resolution for github.com failed"
      echo "DEBUG: ssh ${SSH_USER}@${HOST} cat /etc/resolv.conf"
      return 1
    }
  }
}

@test "${HOST}: nftables agent-metadata-block table exists" {
  local tables
  tables="$(remote nft list tables 2>&1)" || {
    echo "FAIL: unable to list nftables tables"
    return 1
  }

  if [[ "$tables" != *"agent-metadata-block"* ]]; then
    echo "FAIL: nftables table 'agent-metadata-block' not found"
    echo "DEBUG: tables: $tables"
    return 1
  fi
}

@test "${HOST}: nftables metadata block rule drops 169.254.169.254" {
  local rules
  rules="$(remote nft list table ip agent-metadata-block 2>&1)" || {
    echo "FAIL: unable to list nft table ip agent-metadata-block"
    return 1
  }

  if [[ "$rules" != *"169.254.169.254"* ]]; then
    echo "FAIL: metadata block table missing 169.254.169.254 reference"
    echo "DEBUG: rules: $rules"
    return 1
  fi
  if [[ "$rules" != *"drop"* ]]; then
    echo "FAIL: metadata block table missing drop action"
    echo "DEBUG: rules: $rules"
    return 1
  fi
}
