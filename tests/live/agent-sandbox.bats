#!/usr/bin/env bats
# tests/live/agent-sandbox.bats — Agent sandbox wrapper verification on OVH.
# @decision TEST-73-01: Wrapper tests verify bwrap invocation, secret hiding, and audit logging.

load "../lib/common"
bats_load_library bats-support
bats_load_library bats-assert

@test "${HOST}: sandboxed claude wrapper exists in PATH" {
  if ! is_ovh; then skip "agent sandbox only on neurosys-dev"; fi
  local claude_path
  # readlink -f resolves /run/current-system/sw/bin/claude → /nix/store/…/bin/claude
  claude_path="$(remote "readlink -f \$(command -v claude)")"
  # The wrapper is a writeShellApplication — its path contains /nix/store
  [[ "$claude_path" == /nix/store/* ]]
  # The wrapper script should reference bwrap
  remote "grep -q bwrap ${claude_path}"
}

@test "${HOST}: sandboxed codex wrapper exists in PATH" {
  if ! is_ovh; then skip "agent sandbox only on neurosys-dev"; fi
  local codex_path
  codex_path="$(remote "readlink -f \$(command -v codex)")"
  [[ "$codex_path" == /nix/store/* ]]
  remote "grep -q bwrap ${codex_path}"
}

@test "${HOST}: sandboxed claude hides /run/secrets" {
  if ! is_ovh; then skip "agent sandbox only on neurosys-dev"; fi
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
  if ! is_ovh; then skip "agent sandbox only on neurosys-dev"; fi
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
  if ! is_ovh; then skip "agent sandbox only on neurosys-dev"; fi
  # Running with --no-sandbox but without AGENT_ALLOW_NOSANDBOX should exit non-zero
  run remote "unset AGENT_ALLOW_NOSANDBOX; claude --no-sandbox --version 2>&1 || true"
  assert_output --partial "AGENT_ALLOW_NOSANDBOX=1"
}

@test "${HOST}: audit log directory exists with correct permissions" {
  if ! is_ovh; then skip "agent sandbox only on neurosys-dev"; fi
  remote test -d /data/projects/.agent-audit
  local perms
  perms="$(remote stat -c '%a' /data/projects/.agent-audit)"
  [[ "$perms" == "750" ]]
}
