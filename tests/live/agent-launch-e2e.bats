#!/usr/bin/env bats
# tests/live/agent-launch-e2e.bats — Brokered launch end-to-end tests.
# These tests exercise the full operator -> sudo -> systemd-run -> agent-wrapper ->
# nono path, including phantom-token injection and launcher tamper rejection.
# @decision TEST-131-01: A dedicated probe wrapper verifies the deployed brokered
#   launch path end to end instead of bypassing it with direct `nono run`.

load "../lib/common"
bats_load_library bats-support
bats_load_library bats-assert

readonly PROBE_DIR="/data/projects/tsurf/tmp/agent-launch-e2e"
readonly PROBE_REPORT="${PROBE_DIR}/report.txt"

prepare_probe_dir() {
  remote "install -d -m 0775 -o agent -g users ${PROBE_DIR}"
  remote "rm -f ${PROBE_REPORT}"
}

run_brokered_probe() {
  prepare_probe_dir
  remote "sudo -u dev bash -lc 'cd /data/projects/tsurf && agent-sandbox-e2e ${PROBE_REPORT}'"
}

read_report_value() {
  local key="$1"
  remote "grep '^${key}=' ${PROBE_REPORT} | cut -d= -f2-"
}

launcher_path() {
  remote "sudo -u dev bash -lc 'sudo -l' | grep -o '/nix/store/[^ ,]*/bin/tsurf-agent-launch' | head -n1"
}

@test "${HOST}: brokered launch runs as agent with phantom Anthropic token" {
  if ! is_ovh; then skip "agent sandbox only on tsurf-dev"; fi

  run run_brokered_probe
  assert_success

  local report uid anthropic_key anthropic_base_url raw_secret
  report="$(remote "cat ${PROBE_REPORT}")"
  assert_contains "$report" "user=agent" "probe report"
  assert_contains "$report" "secrets_read=denied" "probe report"
  assert_contains "$report" "repo_read=readable" "probe report"
  assert_contains "$report" "workdir_write=ok" "probe report"

  uid="$(read_report_value uid)"
  [ "$uid" -ne 0 ]

  anthropic_key="$(read_report_value anthropic_api_key)"
  [ -n "$anthropic_key" ]
  raw_secret="$(remote "cat /run/secrets/anthropic-api-key")"
  [ "$anthropic_key" != "$raw_secret" ]
  [[ "$anthropic_key" =~ ^[0-9a-f]{64}$ ]]

  anthropic_base_url="$(read_report_value anthropic_base_url)"
  [[ "$anthropic_base_url" =~ ^http://127\.0\.0\.1:[0-9]+/anthropic$ ]]
}

@test "${HOST}: brokered launcher rejects tampered binary paths" {
  if ! is_ovh; then skip "agent sandbox only on tsurf-dev"; fi

  local launcher
  launcher="$(launcher_path)"
  [ -n "$launcher" ]

  run remote "sudo -u dev bash -lc 'sudo AGENT_NAME=tamper AGENT_REAL_BINARY=/usr/bin/evil AGENT_PROJECT_ROOT=/data/projects ${launcher} --version 2>&1'"
  assert_failure
  assert_output --partial "/nix/store"
}
