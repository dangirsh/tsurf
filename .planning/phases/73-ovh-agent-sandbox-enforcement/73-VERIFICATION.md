# Phase 73 Verification — OVH Agent Sandbox Enforcement

**Status: passed**

All must-have items verified against the actual codebase as of 2026-03-11.

---

## Plan 73-01 Checklist

- [x] `modules/agent-sandbox.nix` exists with `options.services.agentSandbox.enable`
  - File present at `/data/projects/neurosys/modules/agent-sandbox.nix`
  - `options.services.agentSandbox.enable` declared at line 116 via `lib.mkEnableOption`

- [x] Wrapper scripts invoke `bwrap` by default
  - `mkWrapper` function builds a `writeShellApplication` that calls `exec bwrap "${BWRAP_ARGS[@]}" -- "$REAL_BINARY" "$@"` as the default (non-`--no-sandbox`) path (line 98)
  - Both `claude-sandboxed` and `codex-sandboxed` wrappers generated via `mkWrapper`

- [x] `--no-sandbox` requires `AGENT_ALLOW_NOSANDBOX=1` or exits 1
  - Lines 68–78: if `$1 == "--no-sandbox"` and `$AGENT_ALLOW_NOSANDBOX != "1"`, prints error and `exit 1`
  - Warning printed when override is granted; no `--no-sandbox` flag is forwarded to real binary

- [x] `hosts/dev/default.nix` imports `agent-sandbox.nix` and sets `services.agentSandbox.enable = true`
  - Import at line 18: `../../modules/agent-sandbox.nix`
  - `services.agentSandbox.enable = true` at line 77

- [x] `hosts/services/default.nix` does NOT import `agent-sandbox.nix`
  - Imports list (lines 3–22) contains no reference to `agent-sandbox.nix`

- [x] `tests/eval/config-checks.nix` has `agent-sandbox-ovh-enabled` check
  - Lines 315–319: asserts `ovhCfg.services.agentSandbox.enable` is true

- [x] `tests/eval/config-checks.nix` has `agent-sandbox-module-has-bwrap` check
  - Lines 321–329: source-reads `modules/agent-sandbox.nix` and asserts it contains the string "bubblewrap"

- [x] `.test-status` contains `pass|0|<timestamp>`
  - Contents: `pass|0|1773222838`

## Plan 73-02 Checklist

- [x] `tests/live/agent-sandbox.bats` exists
  - File present at `/data/projects/neurosys/tests/live/agent-sandbox.bats`
  - 6 `@test` blocks present

- [x] Tests have `is_ovh` skip guard
  - Every test starts with `if ! is_ovh; then skip "agent sandbox only on neurosys-dev"; fi`

- [x] Tests have `${HOST}:` prefix convention
  - All test names use `"${HOST}: <description>"` format (lines 9, 20, 28, 40, 52, 59)

- [x] `tests/eval/config-checks.nix` has `agent-audit-dir` check
  - Lines 331–335: asserts `ovhCfg.systemd.tmpfiles.rules` contains a rule with `.agent-audit`
  - The rule `"d /data/projects/.agent-audit 0750 dev users -"` is declared in `modules/agent-compute.nix` (line 72), which is imported by the OVH host — check will pass at eval time

---

## Summary

All 13 checklist items pass. No gaps found. The module enforces sandbox-by-default with an explicit `AGENT_ALLOW_NOSANDBOX=1` override path, audit logging, secret-proxy placeholder injection, and OVH-only NixOS enforcement. Contabo (`hosts/services/`) is correctly excluded.
