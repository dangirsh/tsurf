#!/usr/bin/env bats
# tests/live/monitoring.bats — Prometheus deep validation for neurosys hosts.
# @decision TEST-48-02: Monitoring tests check concrete alert/rule expectations for fast regression diagnosis.

load "../lib/common"
bats_load_library bats-support/load
bats_load_library bats-assert/load

@test "${HOST}: prometheus scrapes node-exporter target as up" {
  local body
  body="$(remote_curl "http://localhost:9090/api/v1/targets")" || {
    echo "FAIL: Prometheus targets endpoint is unreachable"
    return 1
  }

  local node_health
  node_health="$(echo "$body" | jq -r '.data.activeTargets[] | select(.labels.job == "node") | .health' 2>/dev/null | head -n1)" || true
  if [[ -z "$node_health" ]]; then
    echo "FAIL: could not find node scrape target in Prometheus response"
    return 1
  fi
  if [[ "$node_health" != "up" ]]; then
    echo "FAIL: node target health='$node_health', expected 'up'"
    echo "DEBUG: ssh ${SSH_USER}@${HOST} curl -s http://localhost:9090/api/v1/targets | jq '.data.activeTargets'"
    return 1
  fi
}

@test "${HOST}: prometheus self-scrape target is up" {
  local body
  body="$(remote_curl "http://localhost:9090/api/v1/targets")" || {
    echo "FAIL: Prometheus targets endpoint is unreachable"
    return 1
  }

  local prom_health
  prom_health="$(echo "$body" | jq -r '.data.activeTargets[] | select(.labels.job == "prometheus") | .health' 2>/dev/null | head -n1)" || true
  if [[ -z "$prom_health" ]]; then
    echo "FAIL: could not find prometheus self-scrape target"
    return 1
  fi
  if [[ "$prom_health" != "up" ]]; then
    echo "FAIL: prometheus self-scrape health='$prom_health', expected 'up'"
    return 1
  fi
}

@test "${HOST}: prometheus has InstanceDown alert rule" {
  local body
  body="$(remote_curl "http://localhost:9090/api/v1/rules")" || {
    echo "FAIL: Prometheus rules endpoint is unreachable"
    return 1
  }

  local count
  count="$(echo "$body" | jq '[.data.groups[].rules[] | select(.name == "InstanceDown")] | length' 2>/dev/null)" || true
  if [[ -z "$count" ]] || [[ "$count" -lt 1 ]]; then
    echo "FAIL: InstanceDown alert rule not found"
    return 1
  fi
}

@test "${HOST}: prometheus has DiskSpaceCritical alert rule" {
  local body
  body="$(remote_curl "http://localhost:9090/api/v1/rules")" || {
    echo "FAIL: Prometheus rules endpoint is unreachable"
    return 1
  }

  local count
  count="$(echo "$body" | jq '[.data.groups[].rules[] | select(.name == "DiskSpaceCritical")] | length' 2>/dev/null)" || true
  if [[ -z "$count" ]] || [[ "$count" -lt 1 ]]; then
    echo "FAIL: DiskSpaceCritical alert rule not found"
    return 1
  fi
}

@test "${HOST}: prometheus has BackupStale alert rule (neurosys only)" {
  if ! is_neurosys; then
    skip "backup alert check is neurosys-only"
  fi

  local body
  body="$(remote_curl "http://localhost:9090/api/v1/rules")" || {
    echo "FAIL: Prometheus rules endpoint is unreachable"
    return 1
  }

  local count
  count="$(echo "$body" | jq '[.data.groups[].rules[] | select(.name == "BackupStale")] | length' 2>/dev/null)" || true
  if [[ -z "$count" ]] || [[ "$count" -lt 1 ]]; then
    echo "FAIL: BackupStale alert rule not found"
    return 1
  fi
}

@test "${HOST}: node-exporter systemd collector exports unit state metrics" {
  local body
  body="$(remote_curl "http://localhost:9100/metrics")" || {
    echo "FAIL: node-exporter metrics endpoint is unreachable"
    return 1
  }

  if [[ "$body" != *"node_systemd_unit_state"* ]]; then
    echo "FAIL: node-exporter missing systemd collector metric 'node_systemd_unit_state'"
    echo "DEBUG: ssh ${SSH_USER}@${HOST} curl -s http://localhost:9100/metrics | grep node_systemd"
    return 1
  fi
}
