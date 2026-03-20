#!/usr/bin/env bats
# tests/live/api-endpoints.bats — HTTP endpoint health checks for neurosys hosts.
# @decision TEST-48-01: Endpoint checks run from remote localhost to validate bound services.

load "../lib/common"
bats_load_library bats-support
bats_load_library bats-assert

@test "${HOST}: syncthing GUI responds on localhost:8384" {
  assert_http_ok "http://localhost:8384" "Syncthing GUI"
}

@test "${HOST}: nix-dashboard responds on localhost:8082 (neurosys only)" {
  if ! is_neurosys; then
    skip "nix-dashboard only on neurosys"
  fi
  assert_http_ok "http://localhost:8082" "nix-dashboard"
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
