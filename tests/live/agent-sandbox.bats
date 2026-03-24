#!/usr/bin/env bats
# tests/live/agent-sandbox.bats — Source-text regression guards for wrapper structure.
# These tests verify that wrapper scripts CONTAIN expected strings (nono invocation,
# journald logging, no secret mounts). They are cheap structural guards, NOT runtime
# behavioral security tests. For actual sandbox behavior verification, see
# sandbox-behavioral.bats which runs probes inside the sandbox as the agent user.
# @decision TEST-73-01: Source-text regression guards verify wrapper structure (nono
#   invocation, journald logging). Behavioral security tests are in sandbox-behavioral.bats.

load "../lib/common"
bats_load_library bats-support
bats_load_library bats-assert

# Validates SBX-001, SBX-050: claude wrapper exists and invokes nono
@test "${HOST}: sandboxed claude wrapper exists in PATH" {
  if ! has_agent_sandbox; then skip "agent sandbox not enabled on this host"; fi
  local claude_path
  # readlink -f resolves /run/current-system/sw/bin/claude → /nix/store/…/bin/claude
  claude_path="$(remote "readlink -f \$(command -v claude)")"
  # The wrapper is a writeShellApplication — its path contains /nix/store
  [[ "$claude_path" == /nix/store/* ]]
  # The wrapper script should reference nono
  remote "grep -q nono ${claude_path}"
}

# Validates SBX-027: wrapper does not mount /run/secrets
@test "${HOST}: sandboxed claude hides /run/secrets" {
  if ! has_agent_sandbox; then skip "agent sandbox not enabled on this host"; fi
  local claude_path script_content
  claude_path="$(remote "readlink -f \$(command -v claude)")"
  script_content="$(remote cat "${claude_path}")"
  # Must NOT contain --ro-bind /run/secrets or --bind /run/secrets
  if echo "$script_content" | grep -q 'bind.*/run/secrets'; then
    echo "FAIL: wrapper script mounts /run/secrets into sandbox"
    return 1
  fi
}

# Validates SBX-028: wrapper does not mount ~/.ssh
@test "${HOST}: sandboxed claude hides ~/.ssh" {
  if ! has_agent_sandbox; then skip "agent sandbox not enabled on this host"; fi
  local claude_path script_content
  claude_path="$(remote "readlink -f \$(command -v claude)")"
  script_content="$(remote cat "${claude_path}")"
  # Must NOT contain --bind .*/.ssh
  if echo "$script_content" | grep -q 'bind.*/\.ssh'; then
    echo "FAIL: wrapper script mounts .ssh into sandbox"
    return 1
  fi
}

# Validates SBX-008: launch events logged to journald via logger
@test "${HOST}: wrapper includes logger (util-linux) for journald logging" {
  if ! has_agent_sandbox; then skip "agent sandbox not enabled on this host"; fi
  local claude_path
  claude_path="$(remote "readlink -f \$(command -v claude)")"
  # The wrapper's runtimeInputs should include util-linux (provides logger)
  remote "grep -q util-linux ${claude_path}"
}

# Validates SBX-008: journald-only logging, no file audit
@test "${HOST}: wrapper does not contain file audit log path" {
  if ! has_agent_sandbox; then skip "agent sandbox not enabled on this host"; fi
  local claude_path script_content
  claude_path="$(remote "readlink -f \$(command -v claude)")"
  script_content="$(remote cat "${claude_path}")"
  if echo "$script_content" | grep -q 'AGENT_AUDIT_LOG'; then
    echo "FAIL: wrapper still exports AGENT_AUDIT_LOG — file audit not removed"
    return 1
  fi
}
