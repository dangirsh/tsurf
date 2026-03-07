status: passed

# Phase 66 Verification

Goal: Extract the Phase 22 secret-proxy trick into a generic, well-tested, maximally nix-native NixOS module.

## Checklist

- [x] 1. `packages/secret-proxy/` exists with Rust source (Cargo.toml, src/main.rs, Cargo.lock)
- [x] 2. `packages/secret-proxy.nix` exists and uses `rustPlatform.buildRustPackage`
- [x] 3. `flake.nix` exports `packages.x86_64-linux.secret-proxy`
- [x] 4. `modules/secret-proxy.nix` defines `options.services.secretProxy.services` as `attrsOf submodule`
- [x] 5. Module has `bwrapArgs` read-only option on each service
- [x] 6. Module has eval-time assertion for duplicate port detection
- [x] 7. `tests/eval/config-checks.nix` has `has-secret-proxy-option` check
- [x] 8. `tests/live/api-endpoints.bats` references `secret-proxy-claw-swap` (not `anthropic-secret-proxy`) in DEBUG comment
- [x] 9. `.test-status` contains `pass|0|`
- [x] 10. `/data/projects/private-neurosys/flake.nix` has `services.secretProxy.services.claw-swap` declaration
- [x] 11. `grep -r "anthropic-secret-proxy" /data/projects/neurosys/tests/` returns 0 matches

## Evidence

**Check 1** — `packages/secret-proxy/` contains: Cargo.toml, Cargo.lock, src/main.rs, src/config.rs, src/proxy.rs. Cargo.toml declares `name = "secret-proxy"`, edition 2021, with axum/reqwest/tokio dependencies.

**Check 2** — `packages/secret-proxy.nix` (414 B) calls `rustPlatform.buildRustPackage` with `src = ./secret-proxy` and `cargoLock.lockFile = ./secret-proxy/Cargo.lock`.

**Check 3** — `flake.nix` line 99: `secret-proxy = pkgs.callPackage ./packages/secret-proxy.nix { inherit (pkgs) rustPlatform; };` inside the `packages.${system}` attrset.

**Check 4** — `modules/secret-proxy.nix` defines `options.services.secretProxy.services = lib.mkOption { type = lib.types.attrsOf (lib.types.submodule serviceOpts); ... }`.

**Check 5** — `serviceOpts` submodule contains `bwrapArgs = lib.mkOption { type = lib.types.listOf lib.types.str; readOnly = true; ... }` with a `config` stanza that computes it from `baseUrlEnvVar` and `port`.

**Check 6** — The `config` section contains an `assertions` list that folds all ports into a count map, filters for duplicates, and asserts `duplicates == {}` with a descriptive message naming the conflicting services.

**Check 7** — `tests/eval/config-checks.nix` contains the `has-secret-proxy-option` check using `mkCheck` that asserts `neurosysCfg.services.secretProxy.services == {}` (module is imported and the option exists).

**Check 8** — `tests/live/api-endpoints.bats` test "secret-proxy port 9091 is responsive" includes `echo "DEBUG: ssh ${SSH_USER}@${HOST} systemctl status secret-proxy-claw-swap --no-pager"`. No reference to `anthropic-secret-proxy`.

**Check 9** — `/data/projects/neurosys/.test-status` contains `pass|0|1772911706`.

**Check 10 — FAIL** — No reference to `services.secretProxy`, `secretProxy`, `claw-swap`, or `secret-proxy` exists anywhere in `/data/projects/private-neurosys/` (searched flake.nix, modules/, and full tree excluding .git). The private overlay has not been updated to declare `services.secretProxy.services.claw-swap`, meaning the old `anthropic-secret-proxy` service (Phase 22) is still the deployed configuration in production.

**Check 11** — `grep -r "anthropic-secret-proxy" /data/projects/neurosys/tests/` returned no matches (exit 1).

## Summary of Gaps

One gap found:

**Check 10 is the only failing item.** The public module (checks 1-9, 11) is complete: Rust binary, Nix package, flake export, NixOS module with the required options, eval assertion, eval test, and live test are all present and correct. However, the private overlay (`/data/projects/private-neurosys`) has not been updated to wire the new module to the `claw-swap` agent. The old `anthropic-secret-proxy` Python service from Phase 22 is presumably still declared there. Until `services.secretProxy.services.claw-swap` is declared in the private overlay (replacing the Phase 22 hardcoded service), the generic module is not activated on the deployed hosts and the migration from the hardcoded Python proxy is incomplete.

**Required action:** In `/data/projects/private-neurosys`, add `services.secretProxy.services.claw-swap = { port = 9091; secrets.api-key = { headerName = "x-api-key"; secretFile = config.sops.secrets."anthropic-api-key".path; allowedDomains = [ "api.anthropic.com" ]; }; };` and remove the old `anthropic-secret-proxy` service declaration.
