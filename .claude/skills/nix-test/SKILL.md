---
name: nix-test
description: Run tests and manage .test-status for the tsurf repo
user_invocable: true
---

# nix-test Skill

Run tests for this repo and manage `.test-status` for the commit guard.

## Quick reference: run tests and update .test-status

```bash
# Run eval checks (the most common test -- always do this before committing)
nix flake check

# On success, write .test-status for the commit guard hook
nix flake check 2>&1 && echo "pass|0|$(date +%s)" > .test-status
```

## Three-layer test architecture

1. **Eval checks (offline, fast, ~30s)** -- `nix flake check`
   - Validates NixOS config evaluation for both example `services` and `dev` hosts.
   - Runs 50+ assertions in `tests/eval/config-checks.nix`.
   - Catches missing imports, broken option references, assertion violations, and type errors.
   - **Always run before committing.** No exceptions.

2. **VM integration test (requires KVM)** -- `nix build .#vm-test-sandbox`
   - Boots a NixOS VM and verifies the brokered user-privilege model for sandboxed agents.
   - Cannot run on Contabo/OVH VPS (no nested KVM). Run on local dev machine only.
   - Exposed as a package (not a check) so `nix flake check` works everywhere.

3. **Live tests (SSH to running hosts)** -- `nix run .#test-live -- --host <hostname>`
   - BATS tests over SSH to verify services on deployed hosts.
   - Only after deploy. Never during development.
   - JSON output: `scripts/run-tests.sh --live --json` (one JSON object per test).

## The .test-status guard hook

The commit guard hook (`~/.claude/hooks/guard.sh`) blocks commits unless `.test-status` exists at the project root with a recent pass.

- Format: `pass|0|<unix_timestamp>`
- Location: `/data/projects/tsurf/.test-status` (project root), not `.claude/`
- Produce it: `nix flake check 2>&1 && echo "pass|0|$(date +%s)" > .test-status`
- If `nix flake check` fails, fix the error first. Do not write `.test-status` manually without a passing check.

## Adding a new eval check

In `tests/eval/config-checks.nix`, use `mkCheck`:

```nix
my-check-name = mkCheck
  "my-check-name"                               # derivation name
  "PASS message describing what was verified"   # shown on success
  "FAIL message describing what went wrong"     # shown on failure
  (/* boolean condition */);
```

Access host configs:

- `servicesCfg` -- services host
- `devCfg` -- dev host

For source-based checks (verify module content without importing):

```nix
my-source-check =
  let source = builtins.readFile ../../modules/my-module.nix;
  in mkCheck "my-source-check"
    "my-module contains expected pattern"
    "my-module missing expected pattern"
    (lib.hasInfix "expected-string" source);
```

## Debugging eval failures

1. Read `nix flake check` output. The check name (for example `firewall-ports-services`) maps directly to a derivation in `config-checks.nix`.
2. Find that derivation to inspect the condition and failure message.
3. Common causes:
   - **New file not tracked**: `git add modules/new-file.nix`
   - **Assertion violation**: A `networking.nix` assertion fired (for example internal port leaked to public firewall). Check `internalOnlyPorts` and `allowedTCPPorts`.
   - **Missing import**: Host `default.nix` does not import the new module.
   - **Type error**: Wrong option type (for example `port = "8090"` instead of `port = 8090`).
4. Fix the issue, re-run `nix flake check`, then update `.test-status`.

## When tests are not needed

Documentation-only changes (`README.md`, `CLAUDE.md`, `.planning/`) do not require `nix flake check` because they do not affect NixOS evaluation. Running it is still safe and recommended.
