#!/usr/bin/env bats
# tests/live/api-endpoints.bats — HTTP endpoint health checks for tsurf hosts.
# @decision TEST-48-01: Endpoint checks run from remote localhost to validate bound services.

load "../lib/common"
bats_load_library bats-support
bats_load_library bats-assert

@test "${HOST}: syncthing GUI responds on localhost:8384" {
  assert_http_ok "http://localhost:8384" "Syncthing GUI"
}

@test "${HOST}: nix-dashboard responds on localhost:8082 (tsurf only)" {
  if ! is_tsurf; then
    skip "nix-dashboard only on tsurf"
  fi
  assert_http_ok "http://localhost:8082" "nix-dashboard"
}

