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

@test "${HOST}: agent user cannot connect to non-whitelisted port" {
  if ! is_ovh; then skip "agent sandbox only on tsurf-dev"; fi
  # Port 8080 is not in the egress allowlist — connection should be dropped
  run remote "su -s /bin/sh ${AGENT_USER} -c 'nc -z -w2 1.1.1.1 8080'" 2>&1
  [ "$status" -ne 0 ]
}

@test "${HOST}: agent user can reach DNS (port 53)" {
  if ! is_ovh; then skip "agent sandbox only on tsurf-dev"; fi
  run remote "su -s /bin/sh ${AGENT_USER} -c 'nc -z -w2 8.8.8.8 53'"
  [ "$status" -eq 0 ]
}
