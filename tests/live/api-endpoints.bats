#!/usr/bin/env bats
# tests/live/api-endpoints.bats — HTTP endpoint health checks for tsurf hosts.
# @decision TEST-48-01: Endpoint checks run from remote localhost to validate bound services.

load "../lib/common"
bats_load_library bats-support
bats_load_library bats-assert

# Validates EXT-005: dashboard binds 127.0.0.1 on port 8082
@test "${HOST}: nix-dashboard responds on localhost:8082 (if present)" {
  if ! remote systemctl is-active --quiet nix-dashboard.service 2>/dev/null; then
    skip "nix-dashboard not active on this host"
  fi
  assert_http_ok "http://localhost:8082" "nix-dashboard"
}
