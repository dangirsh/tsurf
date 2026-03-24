# Agent Compute Specification

This document specifies the agent runtime support layer: the cgroup slice,
shared tooling, and resource controls for all agent workloads.

Source: `modules/agent-compute.nix`, `modules/agent-sandbox.nix`, `extras/dev-agent.nix`

## Agent Slice

| ID | Claim | Source |
|----|-------|--------|
| AGT-001 | `tsurf-agents.slice` defined with aggregate resource ceiling | `modules/agent-compute.nix` lines 25-32, `@decision SEC-116-02` |
| AGT-002 | Slice aggregate limits: `MemoryMax=8G`, `CPUQuota=300%`, `TasksMax=1024` | `modules/agent-compute.nix` lines 28-30 |
| AGT-003 | Slice defined on dev host | `tests/eval/config-checks.nix:agent-slice-exists-dev` |
| AGT-004 | All interactive and unattended agent sessions run inside `tsurf-agents.slice` | `modules/agent-sandbox.nix` line 56, `extras/dev-agent.nix` line 167 |

## Per-Session Resource Limits

| ID | Claim | Source |
|----|-------|--------|
| AGT-005 | Interactive sessions: `MemoryMax=4G`, `CPUQuota=200%`, `TasksMax=256` | `modules/agent-sandbox.nix` lines 57-59 |
| AGT-006 | Dev-agent service: `MemoryMax=4G`, `CPUQuota=200%`, `TasksMax=256`, `OOMPolicy=kill` | `extras/dev-agent.nix` lines 168-171 |

## Shared Tooling

| ID | Claim | Source |
|----|-------|--------|
| AGT-007 | `zmx` and `nodejs` installed as system packages when `agentCompute.enable = true` | `modules/agent-compute.nix` lines 17-20 |
| AGT-008 | Raw agent binaries (claude-code, codex, pi) NOT installed in PATH | `modules/agent-compute.nix`, `tests/eval/config-checks.nix:agent-binaries-not-in-path`, `@decision SEC-116-01` |
| AGT-009 | Agent runtime PATH scoped to: `bash`, `coreutils`, `git`, `nono`, `python3`, `util-linux` | `modules/agent-sandbox.nix` lines 22-29 |

## Project Workspace

| ID | Claim | Source |
|----|-------|--------|
| AGT-010 | `/data/projects` persisted across reboots via impermanence | `modules/agent-compute.nix` lines 34-36 |
| AGT-011 | Agent `projectRoot` defaults to `/data/projects` | `modules/users.nix` line 54 |

## Dev-Agent Service

| ID | Claim | Source |
|----|-------|--------|
| AGT-012 | Dev-agent is opt-in: `services.devAgent.enable` defaults to `false` | `extras/dev-agent.nix` line 43, `@decision DEV-AGENT-106` |
| AGT-013 | Dev-agent not defined in public dev config (opt-in works) | `tests/eval/config-checks.nix:dev-agent-not-in-template` |
| AGT-014 | Dev-agent runs as the dedicated agent user, not operator | `extras/dev-agent.nix` line 139, `@decision SEC-115-04` |
| AGT-015 | Dev-agent reaches Claude through the same brokered immutable launcher path | `extras/dev-agent.nix` line 122 (invokes `/run/current-system/sw/bin/claude`), `@decision SEC-145-03` |
| AGT-016 | Dev-agent requires agentSandbox, nonoSandbox, and agentCompute all enabled — enforced by assertions | `extras/dev-agent.nix` lines 108-125 |
| AGT-017 | Dev-agent requires exactly one of `prompt` or `command` — enforced by assertion | `extras/dev-agent.nix` lines 122-124 |
| AGT-018 | Default working directory: `${projectRoot}/dev-agent-workspace` (not the control-plane repo) | `extras/dev-agent.nix` line 48, `tests/eval/config-checks.nix:dev-agent-not-control-plane` |
| AGT-019 | Dev-agent runs as supervised systemd service (`Type=simple`) with `ExecStop` for zmx cleanup | `extras/dev-agent.nix` lines 132-143, `tests/eval/config-checks.nix:dev-agent-supervised` |
| AGT-020 | Task configuration parameterized via `prompt`/`command`/`model`/`permissionMode`/`extraArgs` | `extras/dev-agent.nix` lines 67-104, `tests/eval/config-checks.nix:dev-agent-parameterized-task` |
| AGT-021 | Default `permissionMode = "bypassPermissions"` — accepted risk, nono is the real boundary | `extras/dev-agent.nix` line 93, `@decision DEV-AGENT-98` |
| AGT-022 | Dev-agent working directory created as tmpfiles rule with agent ownership | `extras/dev-agent.nix` lines 127-129 |

## Dev-Agent Systemd Hardening

| ID | Claim | Source |
|----|-------|--------|
| AGT-023 | `NoNewPrivileges=true`, `CapabilityBoundingSet=` (empty) | `extras/dev-agent.nix` lines 158-159 |
| AGT-024 | `PrivateTmp=true`, `ProtectClock=true`, `ProtectKernelTunables/Modules/Logs=true`, `ProtectControlGroups=true` | `extras/dev-agent.nix` lines 147-152 |
| AGT-025 | `SystemCallArchitectures=native`, `LockPersonality=true`, `RestrictRealtime=true`, `RestrictSUIDSGID=true`, `RestrictNamespaces=true` | `extras/dev-agent.nix` lines 153-157 |
| AGT-026 | `MemoryDenyWriteExecute` omitted — Node.js V8 JIT requires W+X pages | `extras/dev-agent.nix` line 163, `@decision SEC-125-02` |
