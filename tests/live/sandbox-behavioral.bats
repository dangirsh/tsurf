#!/usr/bin/env bats
# tests/live/sandbox-behavioral.bats — Behavioral sandbox tests.
# Unlike agent-sandbox.bats (source-text regression guards), these tests
# exercise the sandbox at runtime as the agent user, proving that denied
# paths are denied and allowed paths are allowed.
# @decision TEST-121-01: Behavioral runtime sandbox tests run as agent user
#   inside nono sandbox, complementing source-text guards in agent-sandbox.bats.

load "../lib/common"
bats_load_library bats-support
bats_load_library bats-assert

# Copy sandbox-probe.sh to the remote host once per test file.
setup_file() {
  if ! is_ovh; then return; fi
  # Upload probe script to a location the agent user can access inside the sandbox
  local probe_src
  probe_src="$(cd "$(dirname "${BATS_TEST_FILENAME}")"/../../scripts && pwd)/sandbox-probe.sh"
  scp "${SSH_OPTS[@]}" "$probe_src" "root@${HOST}:/data/projects/tsurf/scripts/sandbox-probe.sh"
  remote "chmod +x /data/projects/tsurf/scripts/sandbox-probe.sh"
  remote "chown agent:users /data/projects/tsurf/scripts/sandbox-probe.sh"
}

# Helper: run a probe check inside the nono sandbox as the agent user.
# The probe script is at /data/projects/tsurf/scripts/sandbox-probe.sh.
run_sandbox_probe() {
  local check="$1"
  remote "sudo -u agent bash -c 'cd /data/projects/tsurf && nono run --profile tsurf --read /data/projects/tsurf -- bash scripts/sandbox-probe.sh ${check}'"
}

@test "${HOST}: agent user identity is correct inside sandbox" {
  if ! is_ovh; then skip "agent sandbox only on tsurf-dev"; fi
  run run_sandbox_probe check-identity
  assert_success
  assert_output --partial "PASS: check-identity"
}

@test "${HOST}: sandbox denies read access to /run/secrets" {
  if ! is_ovh; then skip "agent sandbox only on tsurf-dev"; fi
  # Critical regression test: finding 4 — secret-access denial.
  run run_sandbox_probe denied-secrets
  assert_success
  assert_output --partial "PASS: denied-secrets"
}

@test "${HOST}: sandbox denies read access to ~/.ssh" {
  if ! is_ovh; then skip "agent sandbox only on tsurf-dev"; fi
  run run_sandbox_probe denied-ssh
  assert_success
  assert_output --partial "PASS: denied-ssh"
}

@test "${HOST}: sandbox denies read access to ~/.gnupg" {
  if ! is_ovh; then skip "agent sandbox only on tsurf-dev"; fi
  run run_sandbox_probe denied-gnupg
  assert_success
  assert_output --partial "PASS: denied-gnupg"
}

@test "${HOST}: sandbox denies read access to ~/.bash_history" {
  if ! is_ovh; then skip "agent sandbox only on tsurf-dev"; fi
  run run_sandbox_probe denied-bash-history
  assert_success
  assert_output --partial "PASS: denied-bash-history"
}

@test "${HOST}: sandbox allows reading files in current git repo" {
  if ! is_ovh; then skip "agent sandbox only on tsurf-dev"; fi
  run run_sandbox_probe allowed-repo-read
  assert_success
  assert_output --partial "PASS: allowed-repo-read"
}

@test "${HOST}: sandbox allows writing files in workdir" {
  if ! is_ovh; then skip "agent sandbox only on tsurf-dev"; fi
  run run_sandbox_probe allowed-workdir-write
  assert_success
  assert_output --partial "PASS: allowed-workdir-write"
}

@test "${HOST}: --no-sandbox blocked without AGENT_ALLOW_NOSANDBOX" {
  if ! is_ovh; then skip "agent sandbox only on tsurf-dev"; fi
  # Run as agent user (not root). Must exit non-zero with clear error message.
  run remote "sudo -u agent bash -c 'cd /data/projects/tsurf && unset AGENT_ALLOW_NOSANDBOX && claude --no-sandbox --version 2>&1'"
  assert_failure
  assert_output --partial "AGENT_ALLOW_NOSANDBOX"
}
