#!/usr/bin/env bats
# tests/live/networking.bats — DNS and nftables deep validation.
# @decision TEST-48-02: Networking tests focus on concrete connectivity and metadata endpoint blocking guarantees.

load "../lib/common"
bats_load_library bats-support
bats_load_library bats-assert

# Validates NET-034 (partial): DNS allowed for agent egress
@test "${HOST}: DNS resolution works for external hosts" {
  remote host github.com >/dev/null 2>&1 || {
    remote curl -sf --max-time 5 https://github.com >/dev/null 2>&1 || {
      echo "FAIL: DNS/HTTPS resolution for github.com failed"
      echo "DEBUG: ssh ${SSH_USER}@${HOST} cat /etc/resolv.conf"
      return 1
    }
  }
}

# Validates NET-010, NET-011: metadata block nftables table exists
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

# Validates NET-010: metadata block rule drops IPv4 and IPv6 cloud metadata endpoints
@test "${HOST}: nftables metadata block rule drops cloud metadata endpoints" {
  local rules
  rules="$(remote nft list table inet agent-metadata-block 2>&1)" || {
    echo "FAIL: unable to list nft table inet agent-metadata-block"
    return 1
  }

  if [[ "$rules" != *"169.254.169.254"* ]]; then
    echo "FAIL: metadata block table missing 169.254.169.254 reference"
    echo "DEBUG: rules: $rules"
    return 1
  fi
  if [[ "$rules" != *"fd00:ec2::254"* ]]; then
    echo "FAIL: metadata block table missing fd00:ec2::254 reference"
    echo "DEBUG: rules: $rules"
    return 1
  fi
  if [[ "$rules" != *"drop"* ]]; then
    echo "FAIL: metadata block table missing drop action"
    echo "DEBUG: rules: $rules"
    return 1
  fi
}

# Validates NET-033: agent egress enforced at host nftables
@test "${HOST}: nftables agent-egress table exists" {
  local tables
  tables="$(remote nft list tables 2>&1)" || {
    echo "FAIL: unable to list nftables tables"
    return 1
  }

  if [[ "$tables" != *"agent-egress"* ]]; then
    echo "FAIL: nftables table 'agent-egress' not found"
    echo "DEBUG: tables: $tables"
    return 1
  fi
}

# Validates NET-033, NET-034, NET-035, NET-039, NET-041: egress UID scoping, port allowlist, private range block, terminal drop
@test "${HOST}: nftables agent-egress policy scopes by uid and default-denies loopback" {
  local rules
  rules="$(remote nft list table inet agent-egress 2>&1)" || {
    echo "FAIL: unable to list nft table inet agent-egress"
    return 1
  }

  if [[ "$rules" != *"meta skuid"* ]]; then
    echo "FAIL: agent-egress table missing UID scoping"
    echo "DEBUG: rules: $rules"
    return 1
  fi
  if [[ "$rules" != *"100.64.0.0/10"* ]]; then
    echo "FAIL: agent-egress table missing CGNAT/private-range block"
    echo "DEBUG: rules: $rules"
    return 1
  fi
  if [[ "$rules" != *"443"* ]]; then
    echo "FAIL: agent-egress table missing HTTPS allowlist"
    echo "DEBUG: rules: $rules"
    return 1
  fi
  if [[ "$rules" != *"20000-20199"* ]]; then
    echo "FAIL: agent-egress table missing reserved nono proxy port range"
    echo "DEBUG: rules: $rules"
    return 1
  fi
  if [[ "$rules" != *'oifname "lo"'* || "$rules" != *"drop"* ]]; then
    echo "FAIL: agent-egress table missing loopback drop"
    echo "DEBUG: rules: $rules"
    return 1
  fi
  if [[ "$rules" == *'oifname "lo" accept'* ]]; then
    echo "FAIL: agent-egress table still has blanket loopback accept"
    echo "DEBUG: rules: $rules"
    return 1
  fi
  if [[ "$rules" != *"drop"* ]]; then
    echo "FAIL: agent-egress table missing terminal drop"
    echo "DEBUG: rules: $rules"
    return 1
  fi
}

# Validates NET-034: allowed public HTTPS works for the dedicated agent UID
@test "${HOST}: agent UID can reach allowed public HTTPS" {
  if ! has_agent_sandbox; then skip "agent sandbox not enabled on this host"; fi

  run remote_as_agent "curl -fsS --connect-timeout 5 --max-time 10 https://github.com/ >/dev/null"
  assert_success
}

# Validates NET-039: terminal drop rejects agent UID traffic to non-allowlisted public TCP ports
@test "${HOST}: agent UID cannot reach disallowed public TCP ports" {
  if ! has_agent_sandbox; then skip "agent sandbox not enabled on this host"; fi

  local probe="timeout 5 bash -lc ':</dev/tcp/1.1.1.1/853'"
  if ! remote "$probe" >/dev/null 2>&1; then
    skip "root cannot reach 1.1.1.1:853 from this host"
  fi

  run remote_as_agent "$probe"
  assert_failure
}

# Validates NET-035: private/link-local ranges are blocked for the dedicated agent UID
@test "${HOST}: agent UID cannot reach cloud metadata endpoint" {
  if ! has_agent_sandbox; then skip "agent sandbox not enabled on this host"; fi

  run remote_as_agent "curl -sf --connect-timeout 2 --max-time 3 http://169.254.169.254/ >/dev/null"
  assert_failure
}

# Validates NET-035: tailnet/CGNAT ranges are blocked for the dedicated agent UID when reachable by root
@test "${HOST}: agent UID cannot reach reachable tailnet targets" {
  if ! has_agent_sandbox; then skip "agent sandbox not enabled on this host"; fi

  local probe="timeout 5 bash -lc ':</dev/tcp/100.64.0.5/443'"
  if ! remote "$probe" >/dev/null 2>&1; then
    skip "root cannot reach 100.64.0.5:443 from this host"
  fi

  run remote_as_agent "$probe"
  assert_failure
}

# Validates NET-041: arbitrary loopback service ports are denied for the agent UID
@test "${HOST}: agent UID cannot reach arbitrary loopback service ports" {
  if ! has_agent_sandbox; then skip "agent sandbox not enabled on this host"; fi

  remote "python3 -m http.server 18081 --bind 127.0.0.1 >/tmp/tsurf-loopback-test.log 2>&1 & echo \$! >/tmp/tsurf-loopback-test.pid"
  remote "for i in \$(seq 1 20); do timeout 1 bash -lc ':</dev/tcp/127.0.0.1/18081' && exit 0; sleep 0.1; done; exit 1" || {
    remote "if [[ -f /tmp/tsurf-loopback-test.pid ]]; then kill \$(cat /tmp/tsurf-loopback-test.pid) 2>/dev/null || true; fi"
    skip "could not start root-reachable loopback listener on 18081"
  }

  run remote_as_agent "timeout 3 bash -lc ':</dev/tcp/127.0.0.1/18081'"
  remote "kill \$(cat /tmp/tsurf-loopback-test.pid) 2>/dev/null || true"
  assert_failure
}
