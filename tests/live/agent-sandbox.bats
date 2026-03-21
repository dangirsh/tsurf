#!/usr/bin/env bats
# tests/live/agent-sandbox.bats — Agent sandbox wrapper verification on OVH.
# @decision TEST-73-01: Wrapper tests verify nono invocation, secret hiding, and journald launch logging.

load "../lib/common"
bats_load_library bats-support
bats_load_library bats-assert

@test "${HOST}: sandboxed claude wrapper exists in PATH" {
  if ! is_ovh; then skip "agent sandbox only on tsurf-dev"; fi
  local claude_path
  # readlink -f resolves /run/current-system/sw/bin/claude → /nix/store/…/bin/claude
  claude_path="$(remote "readlink -f \$(command -v claude)")"
  # The wrapper is a writeShellApplication — its path contains /nix/store
  [[ "$claude_path" == /nix/store/* ]]
  # The wrapper script should reference nono
  remote "grep -q nono ${claude_path}"
}

@test "${HOST}: sandboxed codex wrapper exists in PATH" {
  if ! is_ovh; then skip "agent sandbox only on tsurf-dev"; fi
  local codex_path
  codex_path="$(remote "readlink -f \$(command -v codex)")"
  [[ "$codex_path" == /nix/store/* ]]
  remote "grep -q nono ${codex_path}"
}

@test "${HOST}: sandboxed claude hides /run/secrets" {
  if ! is_ovh; then skip "agent sandbox only on tsurf-dev"; fi
  local claude_path script_content
  claude_path="$(remote "readlink -f \$(command -v claude)")"
  script_content="$(remote cat "${claude_path}")"
  # Must NOT contain --ro-bind /run/secrets or --bind /run/secrets
  if echo "$script_content" | grep -q 'bind.*/run/secrets'; then
    echo "FAIL: wrapper script mounts /run/secrets into sandbox"
    return 1
  fi
}

@test "${HOST}: sandboxed claude hides ~/.ssh" {
  if ! is_ovh; then skip "agent sandbox only on tsurf-dev"; fi
  local claude_path script_content
  claude_path="$(remote "readlink -f \$(command -v claude)")"
  script_content="$(remote cat "${claude_path}")"
  # Must NOT contain --bind .*/.ssh
  if echo "$script_content" | grep -q 'bind.*/\.ssh'; then
    echo "FAIL: wrapper script mounts .ssh into sandbox"
    return 1
  fi
}

@test "${HOST}: --no-sandbox blocked without AGENT_ALLOW_NOSANDBOX" {
  if ! is_ovh; then skip "agent sandbox only on tsurf-dev"; fi
  # Running with --no-sandbox but without AGENT_ALLOW_NOSANDBOX should exit non-zero
  run remote "unset AGENT_ALLOW_NOSANDBOX; claude --no-sandbox --version 2>&1 || true"
  assert_output --partial "AGENT_ALLOW_NOSANDBOX=1"
}

@test "${HOST}: wrapper includes logger (util-linux) for journald logging" {
  if ! is_ovh; then skip "agent sandbox only on tsurf-dev"; fi
  local claude_path
  claude_path="$(remote "readlink -f \$(command -v claude)")"
  # The wrapper's runtimeInputs should include util-linux (provides logger)
  remote "grep -q util-linux ${claude_path}"
}

@test "${HOST}: wrapper does not contain file audit log path" {
  if ! is_ovh; then skip "agent sandbox only on tsurf-dev"; fi
  local claude_path script_content
  claude_path="$(remote "readlink -f \$(command -v claude)")"
  script_content="$(remote cat "${claude_path}")"
  if echo "$script_content" | grep -q 'AGENT_AUDIT_LOG'; then
    echo "FAIL: wrapper still exports AGENT_AUDIT_LOG — file audit not removed"
    return 1
  fi
}
