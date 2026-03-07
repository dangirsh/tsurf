#!/usr/bin/env bats
# tests/live/api-endpoints.bats — HTTP endpoint health checks for neurosys hosts.
# @decision TEST-48-01: Endpoint checks run from remote localhost to validate bound services.

load "../lib/common"
bats_load_library bats-support/load
bats_load_library bats-assert/load

@test "${HOST}: syncthing GUI responds on localhost:8384" {
  assert_http_ok "http://localhost:8384" "Syncthing GUI"
}

@test "${HOST}: homepage dashboard responds on localhost:8082 (neurosys only)" {
  if ! is_neurosys; then
    skip "homepage-dashboard only on neurosys"
  fi
  assert_http_ok "http://localhost:8082" "Homepage dashboard"
}

@test "${HOST}: secret-proxy port 9091 is responsive (neurosys only)" {
  if ! is_neurosys; then
    skip "secret-proxy only on neurosys"
  fi

  local status
  status="$(remote curl -so /dev/null -w "%{http_code}" --max-time 10 "http://localhost:9091/" 2>&1)" || true
  if [[ -z "$status" ]] || [[ "$status" == "000" ]]; then
    echo "FAIL: secret-proxy did not return an HTTP response"
    echo "DEBUG: ssh ${SSH_USER}@${HOST} systemctl status secret-proxy-claw-swap --no-pager"
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
