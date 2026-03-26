# Agent Compute Specification

This document specifies the agent runtime support layer: the cgroup slice,
shared tooling, and resource controls for all agent workloads.

Source: `modules/agent-compute.nix`, `modules/agent-sandbox.nix`, `modules/agent-launcher.nix`, `extras/cass.nix`

## Agent Slice

| ID | Claim | Source |
|----|-------|--------|
| AGT-001 | `tsurf-agents.slice` defined with aggregate resource ceiling | `modules/agent-compute.nix` lines 25-32, `@decision SEC-116-02` |
| AGT-002 | Slice aggregate limits: `MemoryMax=8G`, `CPUQuota=300%`, `TasksMax=1024` | `modules/agent-compute.nix` lines 28-30 |
| AGT-003 | Slice defined on dev host | `tests/eval/config-checks.nix:agent-slice-exists-dev` |
| AGT-004 | All brokered interactive agent sessions run inside `tsurf-agents.slice` | `modules/agent-launcher.nix` |

## Per-Session Resource Limits

| ID | Claim | Source |
|----|-------|--------|
| AGT-005 | Interactive sessions: `MemoryMax=4G`, `CPUQuota=200%`, `TasksMax=256` | `modules/agent-sandbox.nix` lines 57-59 |
| AGT-006 | Brokered interactive sessions: `MemoryMax=4G`, `CPUQuota=200%`, `TasksMax=256` | `modules/agent-launcher.nix` |

## Shared Tooling

| ID | Claim | Source |
|----|-------|--------|
| AGT-007 | `nodejs` installed as a shared system package when `agentCompute.enable = true` | `modules/agent-compute.nix` |
| AGT-008 | Raw agent binaries (claude-code, codex, pi) NOT installed in PATH | `modules/agent-compute.nix`, `tests/eval/config-checks.nix:agent-binaries-not-in-path`, `@decision SEC-116-01` |
| AGT-009 | Agent runtime PATH scoped to: `bash`, `coreutils`, `git`, `nono`, `python3`, `util-linux` | `modules/agent-launcher.nix` |

## Project Workspace

| ID | Claim | Source |
|----|-------|--------|
| AGT-010 | `/data/projects` persisted across reboots via impermanence | `modules/agent-compute.nix` lines 34-36 |
| AGT-011 | Agent `projectRoot` defaults to `/data/projects` | `modules/users.nix` line 54 |

## CASS Indexing

| ID | Claim | Source |
|----|-------|--------|
| AGT-012 | `services.cassIndexer.enable` defaults to `true` when `extras/cass.nix` is imported | `extras/cass.nix` |
| AGT-013 | Public host fixtures import the CASS timer by default | `tests/eval/config-checks.nix:cass-indexer-enabled` |
| AGT-014 | CASS runs as the dedicated agent user, not as root or a DynamicUser | `extras/cass.nix` |
| AGT-015 | CASS indexing is throttled: `CPUQuota=25%`, `MemoryMax=512M`, `IOSchedulingClass=idle` | `extras/cass.nix`, `tests/eval/config-checks.nix:cass-indexer-resource-limits` |
| AGT-016 | CASS uses a system timer, so no user linger state is required | `extras/cass.nix`, `tests/eval/config-checks.nix:no-linger-persistence` |
| AGT-017 | CASS index data persisted under `${agentHome}/.local/share/coding-agent-search` | `extras/cass.nix` |

## CASS Systemd Hardening

| ID | Claim | Source |
|----|-------|--------|
| AGT-023 | `NoNewPrivileges=true`, `CapabilityBoundingSet=` (empty) | `extras/cass.nix` |
| AGT-024 | `PrivateTmp=true` and `RestrictAddressFamilies = [ "AF_UNIX" ]` | `extras/cass.nix` |
| AGT-025 | `SystemCallArchitectures=native`, `LockPersonality=true`, `RestrictNamespaces=true` | `extras/cass.nix` |
