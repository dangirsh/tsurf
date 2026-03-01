#!/usr/bin/env bats
# tests/live/api-endpoints.bats — HTTP endpoint health checks for neurosys hosts.
# @decision TEST-48-01: Endpoint checks run from remote localhost to validate bound services.

load "../lib/common"
bats_load_library bats-support/load
bats_load_library bats-assert/load

@test "${HOST}: prometheus /-/healthy returns 200" {
  assert_http_ok "http://localhost:9090/-/healthy" "Prometheus health"
}

@test "${HOST}: prometheus /api/v1/targets has active targets" {
  local body
  body="$(remote_curl "http://localhost:9090/api/v1/targets")" || {
    echo "FAIL: unable to query Prometheus targets endpoint"
    echo "DEBUG: ssh ${SSH_USER}@${HOST} curl -sv http://localhost:9090/api/v1/targets"
    return 1
  }

  local active_count
  active_count="$(echo "$body" | jq ".data.activeTargets | length" 2>/dev/null)" || {
    echo "FAIL: could not parse Prometheus targets JSON"
    return 1
  }
  if [[ "$active_count" -lt 1 ]]; then
    echo "FAIL: active target count='$active_count', expected >= 1"
    echo "DEBUG: response body: $body"
    return 1
  fi
}

@test "${HOST}: prometheus /api/v1/rules has rule groups" {
  local body
  body="$(remote_curl "http://localhost:9090/api/v1/rules")" || {
    echo "FAIL: unable to query Prometheus rules endpoint"
    return 1
  }

  local groups
  groups="$(echo "$body" | jq ".data.groups | length" 2>/dev/null)" || {
    echo "FAIL: could not parse Prometheus rules JSON"
    return 1
  }
  if [[ "$groups" -lt 1 ]]; then
    echo "FAIL: Prometheus rule groups='$groups', expected >= 1"
    return 1
  fi
}

@test "${HOST}: node-exporter metrics endpoint returns expected metric" {
  local body
  body="$(remote_curl "http://localhost:9100/metrics")" || {
    echo "FAIL: node-exporter endpoint not reachable"
    echo "DEBUG: ssh ${SSH_USER}@${HOST} curl -sv http://localhost:9100/metrics"
    return 1
  }
  assert_contains "$body" "node_cpu_seconds_total" "node-exporter metrics"
}

@test "${HOST}: syncthing GUI responds on localhost:8384" {
  assert_http_ok "http://localhost:8384" "Syncthing GUI"
}

@test "${HOST}: homepage dashboard responds on localhost:8082 (neurosys only)" {
  if ! is_neurosys; then
    skip "homepage-dashboard only on neurosys"
  fi
  assert_http_ok "http://localhost:8082" "Homepage dashboard"
}

@test "${HOST}: homepage restic custom query is successful (neurosys only)" {
  if ! is_neurosys; then
    skip "homepage Prometheus widget check only on neurosys"
  fi

  local body
  body="$(remote_curl "http://localhost:9090/api/v1/query?query=time()-restic_backup_last_run_timestamp")" || {
    echo "FAIL: could not query restic metric via Prometheus API"
    return 1
  }

  local status
  status="$(echo "$body" | jq -r ".status" 2>/dev/null)" || {
    echo "FAIL: could not parse Prometheus query response"
    return 1
  }
  if [[ "$status" != "success" ]]; then
    echo "FAIL: Prometheus query status='$status', expected 'success'"
    return 1
  fi
}

@test "${HOST}: neurosys-mcp port 8400 is responsive (neurosys only)" {
  if ! is_neurosys; then
    skip "neurosys-mcp only on neurosys"
  fi

  local status
  status="$(remote curl -so /dev/null -w "%{http_code}" --max-time 10 "http://localhost:8400/" 2>&1)" || true
  if [[ -z "$status" ]] || [[ "$status" == "000" ]]; then
    echo "FAIL: neurosys-mcp did not return an HTTP response"
    echo "DEBUG: ssh ${SSH_USER}@${HOST} systemctl status neurosys-mcp --no-pager"
    return 1
  fi
}

@test "${HOST}: secret-proxy port 9091 is responsive (neurosys only)" {
  if ! is_neurosys; then
    skip "secret-proxy only on neurosys"
  fi

  local status
  status="$(remote curl -so /dev/null -w "%{http_code}" --max-time 10 "http://localhost:9091/" 2>&1)" || true
  if [[ -z "$status" ]] || [[ "$status" == "000" ]]; then
    echo "FAIL: secret-proxy did not return an HTTP response"
    echo "DEBUG: ssh ${SSH_USER}@${HOST} systemctl status anthropic-secret-proxy --no-pager"
    return 1
  fi
}

@test "${HOST}: docker daemon responds to docker ps (neurosys only)" {
  if ! is_neurosys; then
    skip "container presence check only on neurosys"
  fi

  run remote docker ps --format "{{.Names}}"
  if [[ "$status" -ne 0 ]]; then
    echo "FAIL: docker ps failed with status='$status'"
    echo "DEBUG: output: $output"
    return 1
  fi
}
