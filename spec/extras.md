# Extras Specification

This document specifies the optional batteries: additional agent wrappers,
cost tracker, home-manager profile, and other opt-in features.

Source: `extras/*.nix`, `extras/home/default.nix`

## Codex Agent Wrapper

| ID | Claim | Source |
|----|-------|--------|
| EXT-014 | Codex wrapper opt-in: `services.codexAgent.enable` | `extras/codex.nix` line 87 |
| EXT-015 | Requires `agentSandbox.enable` and `nonoSandbox.enable`; enforced by assertions | `extras/codex.nix` lines 106-115 |
| EXT-016 | Follows same brokered launch pattern: sudo -> systemd-run -> agent-wrapper.sh -> nono | `extras/codex.nix` lines 27-60 |
| EXT-017 | Default credentials: `openai:OPENAI_API_KEY:openai-api-key` | `extras/codex.nix` line 97 |
| EXT-018 | Extended nono profile: extends `tsurf` base, adds `~/.codex` | `extras/codex.nix` lines 16-25 |
| EXT-019 | Codex persist paths: `~/.codex` for both dev and agent | `extras/codex.nix` lines 128-131 |

## Cost Tracker

| ID | Claim | Source |
|----|-------|--------|
| EXT-020 | Cost tracker opt-in: `services.costTracker.enable` | `extras/cost-tracker.nix` line 50 |
| EXT-021 | Oneshot timer service: daily by default with `Persistent=true` | `extras/cost-tracker.nix` lines 67-124 |
| EXT-022 | `DynamicUser=true` with `AmbientCapabilities = [ "CAP_DAC_READ_SEARCH" ]` for secret reads | `extras/cost-tracker.nix` lines 85, 108-109, `@decision COST-05` |
| EXT-023 | Cost tracker fully hardened: `NoNewPrivileges`, `ProtectSystem=strict`, `ProtectHome`, etc. | `extras/cost-tracker.nix` lines 87-111 |
| EXT-024 | `MemoryDenyWriteExecute` omitted; Python runtime may need W+X | `@decision SEC-116-05` |
| EXT-025 | `ReadOnlyPaths = [ "/run/secrets" ]`; reads secrets but cannot modify | `extras/cost-tracker.nix` line 112 |

## Home-Manager Profile

| ID | Claim | Source |
|----|-------|--------|
| EXT-026 | Home profile for agent user with git, ssh, gh, direnv, CASS indexer | `extras/home/default.nix` |
| EXT-027 | Git identity uses placeholder values; private overlay replaces | `extras/home/default.nix` lines 14-15 |
| EXT-028 | SSH: control multiplexing, hash known hosts, server alive interval | `extras/home/default.nix` lines 30-39 |
| EXT-029 | direnv with nix-direnv integration | `extras/home/default.nix` lines 43-47 |
| EXT-030 | No deprecated Home Manager git/ssh options used | `tests/eval/config-checks.nix:home-profile-no-deprecated-options` |

## Systemd Hardening Baseline

| ID | Claim | Source |
|----|-------|--------|
| EXT-031 | All project services have `SystemCallArchitectures = "native"` | `tests/eval/config-checks.nix:systemd-hardening-baseline` |
| EXT-032 | Cost-tracker service uses `DynamicUser=true` | `tests/eval/config-checks.nix:cost-tracker-dynamic-user` |

## Script Safety

| ID | Claim | Source |
|----|-------|--------|
| EXT-033 | Agent helper scripts avoid `/tmp` for transient state | `tests/eval/config-checks.nix:agent-scripts-avoid-global-tmp` |
| EXT-034 | `clone-repos.sh` uses `GIT_ASKPASS` pattern (no credentials on CLI) | `tests/eval/config-checks.nix:clone-repos-no-cli-credentials` |
