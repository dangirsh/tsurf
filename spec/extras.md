# Extras Specification

This document specifies the optional batteries: additional agent wrappers,
dashboard, cost tracker, home-manager profile, and other opt-in features.

Source: `extras/*.nix`, `extras/home/default.nix`

## Dashboard

| ID | Claim | Source |
|----|-------|--------|
| EXT-001 | Dashboard enabled via `services.dashboard.enable` | `extras/dashboard.nix` line 61 |
| EXT-002 | Modules self-register via `services.dashboard.entries.<name>` | `extras/dashboard.nix` lines 75-125 |
| EXT-003 | Build-time JSON manifest generated at `/etc/dashboard/manifest.json` | `extras/dashboard.nix` line 144 |
| EXT-004 | Dashboard manifest is valid JSON | `tests/eval/config-checks.nix:dashboard-manifest` |
| EXT-005 | HTTP server binds `127.0.0.1` on configurable port (default 8082) | `extras/dashboard.nix` lines 63-72 |
| EXT-006 | Dashboard service uses `DynamicUser=true` | `extras/dashboard.nix` line 189 |
| EXT-007 | Dashboard fully hardened: `NoNewPrivileges`, `ProtectSystem=strict`, `ProtectHome`, `PrivateDevices`, `CapabilityBoundingSet=""`, `MemoryDenyWriteExecute`, etc. | `extras/dashboard.nix` lines 190-213 |
| EXT-008 | Dashboard has security response headers: `X-Content-Type-Options`, `X-Frame-Options`, `Referrer-Policy` | `tests/eval/config-checks.nix:dashboard-security-headers` |
| EXT-009 | Dashboard frontend has no `innerHTML` XSS sinks | `tests/eval/config-checks.nix:dashboard-no-innerhtml-xss` |
| EXT-010 | Dashboard enabled on services host with port 8082 | `tests/eval/config-checks.nix:dashboard-enabled` |
| EXT-011 | Dashboard has >= 3 entries | `tests/eval/config-checks.nix:dashboard-entries` |
| EXT-012 | Multi-host aggregation via `services.dashboard.extraManifests` | `extras/dashboard.nix` lines 127-137 |
| EXT-013 | Tailscale and SSH entries always registered (unconditional config block) | `extras/dashboard.nix` lines 146-161 |

## Codex Agent Wrapper

| ID | Claim | Source |
|----|-------|--------|
| EXT-014 | Codex wrapper opt-in: `services.codexAgent.enable` | `extras/codex.nix` line 87 |
| EXT-015 | Requires `agentSandbox.enable` and `nonoSandbox.enable` — enforced by assertions | `extras/codex.nix` lines 106-115 |
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
| EXT-024 | `MemoryDenyWriteExecute` omitted — Python runtime may need W+X | `@decision SEC-116-05` |
| EXT-025 | `ReadOnlyPaths = [ "/run/secrets" ]` — reads secrets but cannot modify | `extras/cost-tracker.nix` line 112 |

## Home-Manager Profile

| ID | Claim | Source |
|----|-------|--------|
| EXT-026 | Home profile for `dev` user with git, ssh, gh, direnv inlined | `extras/home/default.nix` |
| EXT-027 | Git identity uses placeholder values — private overlay replaces | `extras/home/default.nix` lines 14-15 |
| EXT-028 | SSH: control multiplexing, hash known hosts, server alive interval | `extras/home/default.nix` lines 30-39 |
| EXT-029 | direnv with nix-direnv integration | `extras/home/default.nix` lines 43-47 |
| EXT-030 | No deprecated Home Manager git/ssh options used | `tests/eval/config-checks.nix:home-profile-no-deprecated-options` |

## Systemd Hardening Baseline

| ID | Claim | Source |
|----|-------|--------|
| EXT-031 | All project services have `SystemCallArchitectures = "native"` | `tests/eval/config-checks.nix:systemd-hardening-baseline` |
| EXT-032 | Dashboard, restic-status, cost-tracker services all use `DynamicUser=true` | Various eval checks |

## Script Safety

| ID | Claim | Source |
|----|-------|--------|
| EXT-033 | Agent helper scripts avoid `/tmp` for transient state | `tests/eval/config-checks.nix:agent-scripts-avoid-global-tmp` |
| EXT-034 | `clone-repos.sh` uses `GIT_ASKPASS` pattern (no credentials on CLI) | `tests/eval/config-checks.nix:clone-repos-no-cli-credentials` |
