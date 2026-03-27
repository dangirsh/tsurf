# Testing Specification

This document specifies the test architecture, test layers, and maps
spec claims to their verification coverage.

Source: `tests/eval/config-checks.nix`, `tests/live/*.bats`, `tests/vm/sandbox-behavioral.nix`, `flake.nix`

## Test Layers

| ID | Claim | Source |
|----|-------|--------|
| TST-001 | Eval checks: 50+ Nix eval-time assertions via `nix flake check`; fast, every commit | `tests/eval/config-checks.nix`, `flake.nix` lines 253-281 |
| TST-002 | Live tests: BATS tests over SSH against deployed hosts via `nix run .#test-live -- --host <hostname>` | `flake.nix` lines 122-193 |
| TST-003 | VM sandbox test: NixOS VM user privilege separation smoke test (requires KVM) via `nix build .#vm-test-sandbox` | `flake.nix` lines 117-120 |
| TST-004 | ShellCheck: all shell scripts validated | `flake.nix` lines 261-269 |
| TST-005 | Unit tests: deploy script and Python unit tests | `flake.nix` lines 270-279 |

## Eval Check Inventory

### Public Output Safety
| ID | Claim | Checks |
|----|-------|--------|
| TST-006 | All nixosConfigurations prefixed with `eval-` | `fixture-output-names` |
| TST-007 | No `deploy.nodes` exported | `public-deploy-empty` |
| TST-008 | Eval fixtures have `allowUnsafePlaceholders = true` | `fixture-mode-services`, `fixture-mode-dev` |
| TST-009 | Eval fixtures also set `users.allowNoPasswordLogin = true` to bypass the root-login lockout assertion | `fixture-root-login-bypass` |
| TST-010 | Host source files do not set `allowUnsafePlaceholders` | `secure-host-services`, `secure-host-dev` |
| TST-011 | Both `eval-services` and `eval-dev` configs evaluate successfully | `eval-services`, `eval-dev`, `eval-dev-alt-agent` |

### Firewall and Network
| ID | Claim | Checks |
|----|-------|--------|
| TST-012 | Firewall ports match nginx state | `firewall-ports-services`, `firewall-ports-dev` |
| TST-013 | `trustedInterfaces` resolves to loopback only on both host fixtures | `trusted-interfaces-loopback-only-services`, `trusted-interfaces-loopback-only-dev` |
| TST-014 | Metadata block nftables table defined | `metadata-block` |
| TST-015 | Agent egress table defined with UID scoping and private range blocking | `agent-egress-table`, `agent-egress-policy` |
| TST-016 | SSH ed25519 host key only | `ssh-ed25519-only` |

### Agent Sandbox
| ID | Claim | Checks |
|----|-------|--------|
| TST-017 | Agent sandbox enabled on dev host | `agent-sandbox-dev-enabled` |
| TST-018 | nono sandbox enabled on dev host | `nono-sandbox-dev-enabled` |
| TST-019 | Core wrapper only includes Claude | `core-agent-sandbox-only-claude` |
| TST-020 | Journald-only launch logging (no file audit) | `agent-journald-logging` |
| TST-021 | nono profile denies `/run/secrets` | `nono-profile-denies-run-secrets` |
| TST-022 | nono profile has no raw credential sourcing | `proxy-credential-profile` |
| TST-023 | Wrapper uses credential proxy and setpriv | `proxy-credential-wrapper` |

### Brokered Launch
| ID | Claim | Checks |
|----|-------|--------|
| TST-024 | Immutable per-agent launchers defined | `brokered-launch-launcher` |
| TST-025 | systemd-run used for privilege drop | `brokered-launch-systemd-run` |
| TST-026 | No SETENV or preserve-env in sudoers | `brokered-launch-sudoers` |
| TST-027 | Root-brokered launcher with root-only short-circuit | `brokered-launch-agent-fallback` |

### Sandbox Read-Scope
| ID | Claim | Checks |
|----|-------|--------|
| TST-028 | Fail-closed git-root validation | `sandbox-git-root-fail-closed` |
| TST-029 | Refuses read access to entire project root | `sandbox-refuses-project-root-read` |
| TST-032 | No `--no-sandbox` escape hatch | `public-no-sandbox-removed` |

### User Model
| ID | Claim | Checks |
|----|-------|--------|
| TST-033 | Agent user exists and is normal user | `agent-user-exists-dev` |
| TST-035 | Agent user not in docker | `agent-user-no-docker` |
| TST-036 | Agent user has explicit UID | `agent-uid-explicit` |
| TST-037 | Agent persist paths derived from config (not hardcoded) | `impermanence-agent-home` |
| TST-038 | Alt-agent fixture propagates correctly | `alt-agent-parameterization` |
| TST-039 | Raw agent binaries not in PATH | `agent-binaries-not-in-path` |
| TST-040 | Agent slice defined on dev host | `agent-slice-exists-dev` |

### Nix Daemon
| ID | Claim | Checks |
|----|-------|--------|
| TST-041 | `allowed-users` restricted to root + agent user | `nix-allowed-users-services` |
| TST-042 | `trusted-users` is root-only | `nix-trusted-users-services` |

### Services
| ID | Claim | Checks |
|----|-------|--------|
| TST-049 | CASS timer imported by default in public host fixtures | `cass-indexer-enabled` |
| TST-050 | Restic backup opt-in only | `restic-opt-in` |
| TST-052 | Cost tracker uses DynamicUser | `cost-tracker-dynamic-user` |
| TST-053 | Cost tracker has correct capability config | `cost-tracker-secret-capability` |

### CASS
| ID | Claim | Checks |
|----|-------|--------|
| TST-054 | CASS uses a system timer instead of user linger | `cass-indexer-resource-limits`, `no-linger-persistence` |
| TST-055 | CASS resource limits stay in place | `cass-indexer-resource-limits` |

### Hardening Baseline
| ID | Claim | Checks |
|----|-------|--------|
| TST-057 | All services have SystemCallArchitectures=native | `systemd-hardening-baseline` |
| TST-058 | Provider API keys owned by root | `agent-api-key-ownership-dev` |
| TST-065 | Eval fixtures disable coredumps at both the systemd and kernel layers | `coredumps-disabled`, `core-pattern-disabled` |

### Stale Content
| ID | Claim | Checks |
|----|-------|--------|
| TST-059 | No stale phrases in CLAUDE.md | `stale-phrases-claude-md` |
| TST-060 | No stale phrases in README.md | `stale-phrases-readme` |

### Script Safety
| ID | Claim | Checks |
|----|-------|--------|
| TST-061 | deploy.sh has no repo-source calls | `deploy-no-repo-source` |
| TST-062 | clone-repos.sh uses GIT_ASKPASS | `clone-repos-no-cli-credentials` |
| TST-063 | No deprecated Home Manager options | `home-profile-no-deprecated-options` |
| TST-064 | Scripts avoid /tmp | `agent-scripts-avoid-global-tmp` |

## Live Test Files

| File | Coverage Area |
|------|--------------|
| `tests/live/security.bats` | SSH hardening, kernel sysctls, metadata blocking, firewall |
| `tests/live/secrets.bats` | `/run/secrets` presence, root ownership, permissions |
| `tests/live/networking.bats` | DNS reachability, metadata-block rule, agent egress table |
| `tests/live/sandbox-behavioral.bats` | Sandbox deny/allow paths |
| `tests/live/agent-sandbox.bats` | Wrapper structure, nono invocation, journald logging |
| `tests/live/service-health.bats` | systemd unit health |
| `tests/live/impermanence.bats` | /persist mount, BTRFS type, critical persist dirs, machine-id |

## Phase 147: New Eval Checks

| ID | Claim | Check |
|----|-------|-------|
| TST-065 | SEC-019, BAS-009: Nix channels disabled | `nix-channels-disabled` |
| TST-066 | BAS-010: defaultPackages empty | `default-packages-empty` |
| TST-067 | SEC-014: mutableUsers = false | `mutable-users-disabled` |
| TST-068 | NET-001: nftables enabled | `nftables-enabled` |
| TST-069 | NET-021: fail2ban disabled | `fail2ban-disabled` |
| TST-070 | IMP-015: hideMounts = true | `impermanence-hide-mounts` |
| TST-071 | IMP-026: setupSecrets depends on persist-files | `secrets-depend-on-persist` |
| TST-072 | SBX-005: AGENT_REAL_BINARY /nix/store guard | `wrapper-nix-store-guard` |
| TST-073 | SCR-013: credential proxy flow | `wrapper-credential-proxy-flow` |
| TST-074 | SEC-030: supply chain env vars | `wrapper-supply-chain-hardening` |
| TST-075 | SEC-031: telemetry suppression | `wrapper-telemetry-suppression` |
| TST-076 | SBX-048: MCP auto-loading disabled | `claude-settings-mcp-disabled` |
| TST-077 | SBX-019: seccomp syscall filter | `launcher-seccomp-filter` |
| TST-078 | BAS-005: non-systemd initrd | `no-systemd-initrd` |
| TST-079 | LAUNCHER-152: per-agent `extraDeny` options are wired into generated nono profiles | `agent-launcher-extra-deny-wired` |
| TST-080 | EXT-020: cost-tracker provider labels are exposed and serialized | `cost-tracker-provider-label` |

## Phase 147: New Live Sandbox Probes

| Claim | Probe | Test |
|-------|-------|------|
| SBX-031 | `denied-aws` | sandbox denies ~/.aws |
| SBX-032 | `denied-kube` | sandbox denies ~/.kube |
| SBX-033 | `denied-docker` | sandbox denies ~/.docker |
| SBX-034 | `denied-npmrc` | sandbox denies ~/.npmrc |
| SBX-038 | `denied-git-credentials` | sandbox denies ~/.git-credentials |
| SBX-039 | `denied-etc-nono` | sandbox denies /etc/nono |

## Phase 147: New Live Security Tests

| Claim | Test |
|-------|------|
| SEC-023 | net.core.bpf_jit_harden = 2 |
| SEC-025 | net.ipv4.conf.all.log_martians = 1 |
| NET-015 | SSH PermitRootLogin is prohibit-password |
| NET-017 | SSH MaxAuthTries is 3 |
| NET-004 | no trusted firewall interfaces |

## Coverage Map

Claims with no test coverage (candidates for future tests):

| Spec File | Uncovered Claims |
|-----------|-----------------|
| `secrets.md` | SCR-015 (session token randomness), SCR-020 (proxy port timeout) |
| `sandbox.md` | SBX-010 through SBX-018 (systemd-run resource properties; live runtime only) |
| `deployment.md` | DEP-007 through DEP-011 (watchdog; requires deploy target) |
| `backup.md` | BAK-008 (retention policy; requires deployed restic) |
| `impermanence.md` | IMP-002 through IMP-005 (rollback script; requires reboot) |
