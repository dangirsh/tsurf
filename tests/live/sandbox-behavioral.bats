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

SANDBOX_WORKSPACE="/data/projects/sandbox-fixture"
CONTROL_PLANE_FIXTURE="/data/projects/control-plane-fixture"

# Copy sandbox-probe.sh to the remote host once per test file.
setup_file() {
  if ! has_agent_sandbox; then return; fi

  remote "bash -lc '
    set -euo pipefail
    rm -rf ${SANDBOX_WORKSPACE} ${CONTROL_PLANE_FIXTURE}
    install -d -m 0755 -o ${AGENT_USER} -g ${AGENT_USER} ${SANDBOX_WORKSPACE}
    install -d -m 0755 -o ${AGENT_USER} -g ${AGENT_USER} ${SANDBOX_WORKSPACE}/scripts
    install -d -m 0755 -o ${AGENT_USER} -g ${AGENT_USER} ${CONTROL_PLANE_FIXTURE}
    git -C ${SANDBOX_WORKSPACE} init -q
    git -C ${CONTROL_PLANE_FIXTURE} init -q
    printf \"# sandbox fixture\n\" > ${SANDBOX_WORKSPACE}/README.md
    printf \"# control-plane fixture\n\" > ${CONTROL_PLANE_FIXTURE}/README.md
    touch ${CONTROL_PLANE_FIXTURE}/.tsurf-control-plane
    chown -R ${AGENT_USER}:${AGENT_USER} ${SANDBOX_WORKSPACE} ${CONTROL_PLANE_FIXTURE}
  '"

  # Upload probe script to a workspace repo the agent user can access inside the sandbox.
  local probe_src
  probe_src="$(cd "$(dirname "${BATS_TEST_FILENAME}")"/../../scripts && pwd)/sandbox-probe.sh"
  scp "${SSH_OPTS[@]}" "$probe_src" "root@${HOST}:${SANDBOX_WORKSPACE}/scripts/sandbox-probe.sh"
  remote "chmod +x ${SANDBOX_WORKSPACE}/scripts/sandbox-probe.sh"
  remote "chown ${AGENT_USER}:${AGENT_USER} ${SANDBOX_WORKSPACE}/scripts/sandbox-probe.sh"
}

teardown_file() {
  if ! has_agent_sandbox; then return; fi
  remote "rm -rf ${SANDBOX_WORKSPACE} ${CONTROL_PLANE_FIXTURE}"
}

# Helper: run a probe check inside the nono sandbox as the agent user.
# The probe script lives in a dedicated workspace fixture repo.
run_sandbox_probe() {
  local check="$1"
  remote "sudo -u ${AGENT_USER} bash -lc 'cd ${SANDBOX_WORKSPACE} && EXPECTED_AGENT_USER=${AGENT_USER} nono run --profile tsurf --read ${SANDBOX_WORKSPACE} -- bash scripts/sandbox-probe.sh ${check}'"
}

run_wrapper_in_control_plane_fixture() {
  remote "sudo -u ${AGENT_USER} bash -lc 'cd ${CONTROL_PLANE_FIXTURE} && claude --help'"
}

@test "${HOST}: agent user identity is correct inside sandbox" {
  if ! has_agent_sandbox; then skip "agent sandbox not enabled on this host"; fi
  run run_sandbox_probe check-identity
  assert_success
  assert_output --partial "PASS: check-identity"
}

@test "${HOST}: sandbox denies read access to /run/secrets" {
  if ! has_agent_sandbox; then skip "agent sandbox not enabled on this host"; fi
  # Critical regression test: finding 4 — secret-access denial.
  run run_sandbox_probe denied-secrets
  assert_success
  assert_output --partial "PASS: denied-secrets"
}

@test "${HOST}: sandbox denies read access to ~/.ssh" {
  if ! has_agent_sandbox; then skip "agent sandbox not enabled on this host"; fi
  run run_sandbox_probe denied-ssh
  assert_success
  assert_output --partial "PASS: denied-ssh"
}

@test "${HOST}: sandbox denies read access to ~/.gnupg" {
  if ! has_agent_sandbox; then skip "agent sandbox not enabled on this host"; fi
  run run_sandbox_probe denied-gnupg
  assert_success
  assert_output --partial "PASS: denied-gnupg"
}

@test "${HOST}: sandbox denies read access to ~/.bash_history" {
  if ! has_agent_sandbox; then skip "agent sandbox not enabled on this host"; fi
  run run_sandbox_probe denied-bash-history
  assert_success
  assert_output --partial "PASS: denied-bash-history"
}

@test "${HOST}: sandbox allows reading files in current git repo" {
  if ! has_agent_sandbox; then skip "agent sandbox not enabled on this host"; fi
  run run_sandbox_probe allowed-repo-read
  assert_success
  assert_output --partial "PASS: allowed-repo-read"
}

@test "${HOST}: sandbox allows writing files in workdir" {
  if ! has_agent_sandbox; then skip "agent sandbox not enabled on this host"; fi
  run run_sandbox_probe allowed-workdir-write
  assert_success
  assert_output --partial "PASS: allowed-workdir-write"
}

@test "${HOST}: wrapper refuses protected control-plane repos" {
  if ! has_agent_sandbox; then skip "agent sandbox not enabled on this host"; fi
  run run_wrapper_in_control_plane_fixture
  assert_failure
  assert_output --partial "protected control-plane repo"
}
