#!/usr/bin/env bats
# tests/live/agentd.bats — Deep agentd service validation for neurosys hosts.
# @decision TEST-48-02: Agentd tests must tolerate public-repo runs where private overlay agents are absent.

load "../lib/common"
bats_load_library bats-support/load
bats_load_library bats-assert/load

@test "${HOST}: agentd proxy port 9201 responds to GET /v1/agents (if configured)" {
  if ! is_neurosys; then
    skip "agentd proxies are expected on neurosys"
  fi

  local status
  status="$(remote curl -so /dev/null -w '%{http_code}' --max-time 5 'http://localhost:9201/v1/agents' 2>&1)" || true
  if [[ "$status" == "000" ]]; then
    skip "port 9201 not listening (agent may be private-overlay only)"
  fi
  if [[ ! "$status" =~ ^[0-9]{3}$ ]]; then
    echo "FAIL: unexpected HTTP status output for port 9201: $status"
    return 1
  fi
}

@test "${HOST}: agentd proxy port 9202 responds to GET /v1/agents (if configured)" {
  if ! is_neurosys; then
    skip "agentd proxies are expected on neurosys"
  fi

  local status
  status="$(remote curl -so /dev/null -w '%{http_code}' --max-time 5 'http://localhost:9202/v1/agents' 2>&1)" || true
  if [[ "$status" == "000" ]]; then
    skip "port 9202 not listening (agent may be private-overlay only)"
  fi
  if [[ ! "$status" =~ ^[0-9]{3}$ ]]; then
    echo "FAIL: unexpected HTTP status output for port 9202: $status"
    return 1
  fi
}

@test "${HOST}: agentd jcard.toml files exist under /etc/agentd (if agents configured)" {
  if ! is_neurosys; then
    skip "agentd is expected on neurosys"
  fi

  local count
  count="$(remote find /etc/agentd -name 'jcard.toml' 2>/dev/null | wc -l)" || true
  if [[ "$count" -eq 0 ]]; then
    skip "no jcard.toml files found (agents may be private-overlay only)"
  fi
}

@test "${HOST}: agentd jcard.toml files parse as TOML" {
  if ! is_neurosys; then
    skip "agentd is expected on neurosys"
  fi

  local jcards
  jcards="$(remote find /etc/agentd -name 'jcard.toml' 2>/dev/null)" || true
  if [[ -z "$jcards" ]]; then
    skip "no jcard.toml files to validate"
  fi

  if remote command -v python3 >/dev/null 2>&1; then
    while IFS= read -r jcard; do
      remote python3 -c "import tomllib, pathlib; tomllib.loads(pathlib.Path('$jcard').read_text())" >/dev/null 2>&1 || {
        echo "FAIL: invalid TOML in $jcard"
        return 1
      }
    done <<< "$jcards"
    return 0
  fi

  if remote command -v yq >/dev/null 2>&1; then
    while IFS= read -r jcard; do
      remote yq -p toml '.' "$jcard" >/dev/null 2>&1 || {
        echo "FAIL: invalid TOML in $jcard"
        return 1
      }
    done <<< "$jcards"
    return 0
  fi

  skip "no TOML parser available on target host (python3/yq missing)"
}

@test "${HOST}: agentd service units use Restart=on-failure" {
  if ! is_neurosys; then
    skip "agentd is expected on neurosys"
  fi

  local units
  units="$(remote systemctl list-units --type=service --all --no-legend --no-pager 'agentd-*.service' 2>/dev/null | awk '{print $1}')" || true
  if [[ -z "$units" ]]; then
    skip "no agentd-*.service units found"
  fi

  while IFS= read -r unit; do
    local restart_policy
    restart_policy="$(remote systemctl show -p Restart "$unit" 2>/dev/null | cut -d= -f2)" || true
    if [[ "$restart_policy" != "on-failure" ]]; then
      echo "FAIL: $unit has Restart=$restart_policy, expected on-failure"
      return 1
    fi
  done <<< "$units"
}

@test "${HOST}: rendered agentd-env contains ANTHROPIC_API_KEY key" {
  if ! is_neurosys; then
    skip "agentd is expected on neurosys"
  fi

  remote test -f /run/secrets/rendered/agentd-env || {
    skip "agentd-env is not rendered (agents may be private-overlay only)"
  }

  remote grep -q '^ANTHROPIC_API_KEY=' /run/secrets/rendered/agentd-env || {
    echo "FAIL: /run/secrets/rendered/agentd-env missing ANTHROPIC_API_KEY entry"
    return 1
  }
}
