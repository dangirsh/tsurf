# Sandbox Specification

This document specifies the agent sandbox boundary implemented by nono (Landlock),
the agent wrapper script, and the brokered launch path. Applies only to hosts that
import and enable `modules/agent-sandbox.nix` and `modules/nono.nix`.

Source: `modules/agent-sandbox.nix`, `modules/nono.nix`, `scripts/agent-wrapper.sh`

## Launch Path

| ID | Claim | Source |
|----|-------|--------|
| SBX-001 | Interactive wrapper execution follows: `agent (or root) -> wrapper -> sudo tsurf-launch-<agent> -> systemd-run -> agent-wrapper.sh -> nono -> setpriv -> real binary` | `modules/agent-sandbox.nix`, `scripts/agent-wrapper.sh` |
| SBX-002 | Sudo rules expose only immutable per-agent launchers (e.g., `tsurf-launch-claude`), not a generic root helper | `modules/agent-sandbox.nix` lines 160-175, `@decision SEC-135-01` |
| SBX-003 | Sudo rules use `NOPASSWD` only — no `SETENV`, no `--preserve-env` | `tests/eval/config-checks.nix:brokered-launch-sudoers` |
| SBX-004 | Each launcher bakes in: real binary path, nono profile path, credential allowlist, whether Nix daemon access is enabled | `modules/agent-sandbox.nix` lines 38-45 |
| SBX-005 | Launcher rejects any `AGENT_REAL_BINARY` outside `/nix/store` | `scripts/agent-wrapper.sh` lines 48-54 |
| SBX-006 | The caller cannot swap binaries, profiles, or credential tuples across the sudo boundary | `@decision SEC-135-01`, immutable launcher design |
| SBX-007 | The dedicated agent user can invoke the Claude launcher via explicit sudoers rules without needing `wheel` membership | `modules/agent-launcher.nix`, `modules/users.nix` |
| SBX-008 | Launch events logged to journald only (`logger -t agent-launch`), not file-based audit log | `scripts/agent-wrapper.sh` lines 73-78, `@decision AUDIT-117-01` |
| SBX-009 | Logged fields limited to: `mode`, `agent`, `user`, `uid`, `repo_scope` — no raw arguments, prompts, or file paths | `scripts/agent-wrapper.sh` line 76 |

## systemd-run Properties

| ID | Claim | Source |
|----|-------|--------|
| SBX-010 | Per-session resource limits: `MemoryMax=4G`, `CPUQuota=200%`, `TasksMax=256` | `modules/agent-sandbox.nix` lines 57-59 |
| SBX-011 | `NoNewPrivileges=true` — no privilege escalation inside the session | `modules/agent-sandbox.nix` line 60, `@decision SEC-145-03` |
| SBX-012 | `CapabilityBoundingSet=` (empty) — all capabilities dropped | `modules/agent-sandbox.nix` line 61 |
| SBX-013 | `OOMScoreAdjust=500` — agent sessions killed before critical services under memory pressure | `modules/agent-sandbox.nix` line 62 |
| SBX-014 | File descriptor limit: `LimitNOFILE=512` | `modules/agent-sandbox.nix` line 63 |
| SBX-015 | File size limit: `LimitFSIZE=2G` | `modules/agent-sandbox.nix` line 64 |
| SBX-016 | Address space limit: `LimitAS=8G` | `modules/agent-sandbox.nix` line 65 |
| SBX-017 | Core dumps disabled: `LimitCORE=0` | `modules/agent-sandbox.nix` line 66 |
| SBX-018 | Session runtime timeout: `RuntimeMaxSec=14400` (4 hours) | `modules/agent-sandbox.nix` line 67 |
| SBX-019 | Seccomp syscall blocklist: `@mount @clock @cpu-emulation @debug @obsolete @raw-io @reboot @swap kexec_load kexec_file_load open_by_handle_at io_uring_setup io_uring_enter io_uring_register bpf` | `modules/agent-sandbox.nix` line 68, `@decision SEC-145-03` |

## Filesystem Boundary (nono/Landlock)

| ID | Claim | Source |
|----|-------|--------|
| SBX-020 | Wrapper requires `$PWD` inside `services.agentSandbox.projectRoot` (default `/data/projects`) | `scripts/agent-wrapper.sh` lines 85-92 |
| SBX-021 | Wrapper requires `$PWD` inside a Git worktree — fails closed if not in a git repo | `scripts/agent-wrapper.sh` lines 159-162, `tests/eval/config-checks.nix:sandbox-git-root-fail-closed` |
| SBX-022 | Wrapper resolves Git toplevel and passes it to nono with `--read` for scoped read access | `scripts/agent-wrapper.sh` line 195 |
| SBX-023 | Wrapper refuses to run if Git root equals the project root (prevents blanket `/data/projects` read) | `scripts/agent-wrapper.sh` lines 164-167, `tests/eval/config-checks.nix:sandbox-refuses-project-root-read` |
| SBX-026 | `workdir.access = "readwrite"` — current worktree is writable | `modules/nono.nix` line 81 |

## nono Profile Deny List

| ID | Claim | Source |
|----|-------|--------|
| SBX-027 | `/run/secrets` denied | `modules/nono.nix` line 63, `tests/eval/config-checks.nix:nono-profile-denies-run-secrets` |
| SBX-028 | `~/.ssh` denied | `modules/nono.nix` line 64 |
| SBX-029 | `~/.bash_history` denied | `modules/nono.nix` line 65 |
| SBX-030 | `~/.gnupg` denied | `modules/nono.nix` line 66 |
| SBX-031 | `~/.aws` denied | `modules/nono.nix` line 67 |
| SBX-032 | `~/.kube` denied | `modules/nono.nix` line 68 |
| SBX-033 | `~/.docker` denied | `modules/nono.nix` line 69 |
| SBX-034 | `~/.npmrc` denied | `modules/nono.nix` line 70 |
| SBX-035 | `~/.pypirc` denied | `modules/nono.nix` line 71 |
| SBX-036 | `~/.gem` denied | `modules/nono.nix` line 72 |
| SBX-037 | `~/.config/gh` denied | `modules/nono.nix` line 73 |
| SBX-038 | `~/.git-credentials` denied | `modules/nono.nix` line 74 |
| SBX-039 | `/etc/nono` denied | `modules/nono.nix` line 75 |
| SBX-040 | nono profile contains no raw credential sourcing (`custom_credentials`, `env://`) | `tests/eval/config-checks.nix:proxy-credential-profile` |

## nono Profile Allow Lists

| ID | Claim | Source |
|----|-------|--------|
| SBX-041 | Base `tsurf` profile allows `~/.gitconfig` plus agent-specific overlays; Claude adds `~/.claude`, `~/.config/claude`, `~/.claude.json`, and `~/.claude.json.lock` via per-agent `nonoProfile` overrides | `modules/nono.nix`, `modules/agent-sandbox.nix` |
| SBX-042 | Base profile allows NixOS system paths: `/nix/var/nix/profiles`, `/run/current-system`, `/etc/profiles/per-user`, `/etc/ssl`, `/etc/nix`, `/etc/static` | `modules/nono.nix` |
| SBX-043 | Base profile security groups stay generic: `nix_runtime`, `node_runtime`, `rust_runtime`, `python_runtime`, `user_caches_linux`, `unlink_protection` | `modules/nono.nix` |
| SBX-044 | `signal_mode = "isolated"` — process signal isolation | `modules/nono.nix` |
| SBX-045 | `capability_elevation = false` | `modules/nono.nix` |
| SBX-046 | `network.block = false` — nono is NOT the egress boundary; nftables is | `modules/nono.nix` |

## Claude-Level Defense-in-Depth

| ID | Claim | Source |
|----|-------|--------|
| SBX-047 | Managed Claude settings deny: `Read(/run/secrets/**)`, `Read(~/.ssh/**)`, `Read(/etc/nono/**)`, `Read(.env)`, `Read(.envrc)`, `Edit(.git/hooks/**)`, `Edit(.envrc)`, `Edit(.env)`, `Edit(.mcp.json)`, `Edit(.devcontainer/**)` | `modules/agent-sandbox.nix` lines 142-153, `@decision SEC-145-04` |
| SBX-048 | `enableAllProjectMcpServers = false` — prevents malicious repos from injecting MCP servers | `modules/agent-sandbox.nix` line 155, `@decision SEC-145-04` |
| SBX-049 | Managed settings file written to `/etc/claude-agent-settings.json` and injected via `CLAUDE_CODE_MANAGED_SETTINGS_FILE` env var | `modules/agent-sandbox.nix` line 140, `scripts/agent-wrapper.sh` lines 221-223 |

## Core Wrapper Contract

| ID | Claim | Source |
|----|-------|--------|
| SBX-050 | `agent-sandbox.nix` core wrapper list only includes Claude — no codex, pi, opencode | `tests/eval/config-checks.nix:core-agent-sandbox-only-claude` |
| SBX-051 | Additional agent wrappers (codex) are opt-in extras that follow the same wrapper contract | `extras/codex.nix` |
