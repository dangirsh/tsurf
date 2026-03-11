#!/usr/bin/env bats
# tests/live/api-endpoints.bats — HTTP endpoint health checks for neurosys hosts.
# @decision TEST-48-01: Endpoint checks run from remote localhost to validate bound services.

load "../lib/common"
bats_load_library bats-support
bats_load_library bats-assert

@test "${HOST}: syncthing GUI responds on localhost:8384" {
  assert_http_ok "http://localhost:8384" "Syncthing GUI"
}

@test "${HOST}: homepage dashboard responds on localhost:8082 (neurosys only)" {
  if ! is_neurosys; then
    skip "homepage-dashboard only on neurosys"
  fi
  assert_http_ok "http://localhost:8082" "Homepage dashboard"
}

@test "${HOST}: secret-proxy port 9091 is responsive" {
  local status
  status="$(remote curl -so /dev/null -w "%{http_code}" --max-time 10 "http://localhost:9091/" 2>&1)" || true
  if [[ -z "$status" ]] || [[ "$status" == "000" ]]; then
    echo "FAIL: secret-proxy did not return an HTTP response"
    echo "DEBUG: ssh ${SSH_USER}@${HOST} systemctl status 'secret-proxy-*' --no-pager"
    return 1
  fi
}

@test "${HOST}: secret-proxy /health returns 200 with status ok (neurosys-dev only)" {
  if ! is_ovh; then
    skip "detailed secret-proxy tests on neurosys-dev only"
  fi
  local response
  response="$(remote curl -sf --max-time 10 "http://localhost:9091/health" 2>&1)" || {
    echo "FAIL: /health endpoint not reachable"
    echo "DEBUG: ssh ${SSH_USER}@${HOST} curl -v http://localhost:9091/health"
    return 1
  }

  local status
  status="$(echo "$response" | jq -r ".status" 2>/dev/null)" || {
    echo "FAIL: /health response is not valid JSON"
    echo "DEBUG: response=$response"
    return 1
  }
  if [[ "$status" != "ok" ]]; then
    echo "FAIL: /health status='$status', expected 'ok'"
    return 1
  fi
}

@test "${HOST}: secret-proxy rejects disallowed Host header with 403 (neurosys-dev only)" {
  if ! is_ovh; then
    skip "detailed secret-proxy tests on neurosys-dev only"
  fi
  local http_code
  http_code="$(remote curl -so /dev/null -w "%{http_code}" --max-time 10 \
    -H "Host: evil.example.com" "http://localhost:9091/v1/test" 2>&1)" || true
  if [[ "$http_code" != "403" ]]; then
    echo "FAIL: expected 403 for disallowed host, got '$http_code'"
    echo "DEBUG: ssh ${SSH_USER}@${HOST} curl -sv -H 'Host: evil.example.com' http://localhost:9091/v1/test"
    return 1
  fi
}

@test "${HOST}: secret-proxy e2e Anthropic API call succeeds (neurosys-dev only, opt-in)" {
  if ! is_ovh; then
    skip "e2e proxy test on neurosys-dev only"
  fi
  if [[ "${NEUROSYS_E2E_PROXY:-}" != "1" ]]; then
    skip "set NEUROSYS_E2E_PROXY=1 to run (makes real API call)"
  fi

  local response
  response="$(remote curl -sf --max-time 30 \
    -H "Host: api.anthropic.com" \
    -H "x-api-key: sk-ant-placeholder-dev" \
    -H "content-type: application/json" \
    -H "anthropic-version: 2023-06-01" \
    -d '{"model":"claude-sonnet-4-20250514","max_tokens":10,"messages":[{"role":"user","content":"Say hi"}]}' \
    "http://localhost:9091/v1/messages" 2>&1)" || {
    echo "FAIL: e2e proxy call failed"
    echo "DEBUG: ssh ${SSH_USER}@${HOST} journalctl -u secret-proxy-dev -n 20 --no-pager"
    return 1
  }

  local msg_type
  msg_type="$(echo "$response" | jq -r ".type" 2>/dev/null)"
  if [[ "$msg_type" != "message" ]]; then
    echo "FAIL: expected type=message, got '$msg_type'"
    echo "DEBUG: response=$response"
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
