#!/usr/bin/env bats
# tests/live/agent-launch-e2e.bats — Brokered launch end-to-end tests.
# These tests exercise the full operator -> sudo -> systemd-run -> agent-wrapper ->
# nono path, including phantom-token injection and sudo-boundary hardening.
# @decision TEST-131-01: A dedicated probe wrapper verifies the deployed brokered
#   launch path end to end instead of bypassing it with direct `nono run`.

load "../lib/common"
bats_load_library bats-support
bats_load_library bats-assert

readonly PROBE_DIR="/data/projects/tsurf/tmp/agent-launch-e2e"
readonly PROBE_REPORT="${PROBE_DIR}/report.txt"

prepare_probe_dir() {
  remote "install -d -m 0775 -o ${AGENT_USER} -g users ${PROBE_DIR}"
  remote "rm -f ${PROBE_REPORT}"
}

run_brokered_probe() {
  prepare_probe_dir
  remote "sudo -u dev bash -lc 'cd /data/projects/tsurf && agent-sandbox-e2e ${PROBE_REPORT}'"
}

read_recent_launch_log() {
  local since_epoch="$1"
  remote "
    for _ in 1 2 3 4 5; do
      out=\$(journalctl -t agent-launch --since '@${since_epoch}' --no-pager -o cat 2>/dev/null || true)
      if [ -n \"\$out\" ]; then
        printf '%s\n' \"\$out\"
        exit 0
      fi
      sleep 1
    done
    exit 1
  "
}

read_report_value() {
  local key="$1"
  remote "grep '^${key}=' ${PROBE_REPORT} | cut -d= -f2-"
}

@test "${HOST}: brokered launch runs as the configured agent with phantom Anthropic token" {
  if ! is_ovh; then skip "agent sandbox only on tsurf-dev"; fi

  local since_epoch
  since_epoch="$(remote "date +%s")"

  run run_brokered_probe
  assert_success

  local report uid anthropic_key anthropic_base_url raw_secret launch_log
  report="$(remote "cat ${PROBE_REPORT}")"
  assert_contains "$report" "user=${AGENT_USER}" "probe report"
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

  launch_log="$(read_recent_launch_log "$since_epoch")"
  assert_contains "$launch_log" "mode=sandboxed" "agent launch log"
  assert_contains "$launch_log" "agent=agent-sandbox-e2e" "agent launch log"
  assert_contains "$launch_log" "user=${AGENT_USER}" "agent launch log"
  assert_contains "$launch_log" "uid=${uid}" "agent launch log"
  assert_contains "$launch_log" "repo_scope=git-worktree" "agent launch log"
}

@test "${HOST}: sudoers exposes only dedicated per-agent launchers without SETENV" {
  if ! is_ovh; then skip "agent sandbox only on tsurf-dev"; fi

  local sudo_list
  sudo_list="$(remote "sudo -u dev bash -lc 'sudo -l'")"
  assert_contains "$sudo_list" "tsurf-launch-claude" "sudo -l output"
  assert_contains "$sudo_list" "tsurf-launch-agent-sandbox-e2e" "sudo -l output"
  [[ "$sudo_list" != *"tsurf-agent-launch"* ]]
  [[ "$sudo_list" != *"SETENV"* ]]
}
