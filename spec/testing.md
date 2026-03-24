# Testing Specification

This document specifies the test architecture, test layers, and maps
spec claims to their verification coverage.

Source: `tests/eval/config-checks.nix`, `tests/live/*.bats`, `tests/vm/sandbox-behavioral.nix`, `flake.nix`

## Test Layers

| ID | Claim | Source |
|----|-------|--------|
| TST-001 | Eval checks: 50+ Nix eval-time assertions via `nix flake check` — fast, every commit | `tests/eval/config-checks.nix`, `flake.nix` lines 253-281 |
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
| TST-009 | Host source files do not set `allowUnsafePlaceholders` | `secure-host-services`, `secure-host-dev` |
| TST-010 | Both `eval-services` and `eval-dev` configs evaluate successfully | `eval-services`, `eval-dev`, `eval-dev-alt-agent` |

### Firewall and Network
| ID | Claim | Checks |
|----|-------|--------|
| TST-011 | Firewall ports match nginx state | `firewall-ports-services`, `firewall-ports-dev` |
| TST-012 | `tailscale0` not in trustedInterfaces | `no-trusted-tailscale0-services`, `no-trusted-tailscale0-dev` |
| TST-013 | No `--accept-routes` in Tailscale defaults | `no-accept-routes-services`, `no-accept-routes-dev` |
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
| TST-030 | Refuses protected control-plane repos | `sandbox-refuses-protected-control-plane-repos` |
| TST-031 | Control-plane marker file exists at repo root | `control-plane-marker-file` |
| TST-032 | No `--no-sandbox` escape hatch | `public-no-sandbox-removed` |

### User Model
| ID | Claim | Checks |
|----|-------|--------|
| TST-033 | Agent user exists and is normal user | `agent-user-exists-dev` |
| TST-034 | Agent user not in wheel | `agent-user-no-wheel` |
| TST-035 | Agent user not in docker | `agent-user-no-docker` |
| TST-036 | Agent user has explicit UID | `agent-uid-explicit` |
| TST-037 | Agent persist paths derived from config (not hardcoded) | `impermanence-agent-home` |
| TST-038 | Alt-agent fixture propagates correctly | `alt-agent-parameterization` |
| TST-039 | Raw agent binaries not in PATH | `agent-binaries-not-in-path` |
| TST-040 | Agent slice defined on dev host | `agent-slice-exists-dev` |

### Nix Daemon
| ID | Claim | Checks |
|----|-------|--------|
| TST-041 | `allowed-users` restricted to root + @wheel | `nix-allowed-users-services` |
| TST-042 | `trusted-users` is root-only | `nix-trusted-users-services` |

### Services
| ID | Claim | Checks |
|----|-------|--------|
| TST-043 | Expected services defined on each host | `expected-services-services`, `expected-services-dev` |
| TST-044 | Dashboard enabled on port 8082 | `dashboard-enabled` |
| TST-045 | Dashboard has sufficient entries | `dashboard-entries` |
| TST-046 | Dashboard manifest is valid JSON | `dashboard-manifest` |
| TST-047 | Dashboard security headers present | `dashboard-security-headers` |
| TST-048 | Dashboard no innerHTML XSS | `dashboard-no-innerhtml-xss` |
| TST-049 | dev-agent not active in public config | `dev-agent-not-in-template` |
| TST-050 | Restic backup opt-in only | `restic-opt-in` |
| TST-051 | Restic status server uses DynamicUser | `restic-status-dynamic-user` |
| TST-052 | Cost tracker uses DynamicUser | `cost-tracker-dynamic-user` |
| TST-053 | Cost tracker has correct capability config | `cost-tracker-secret-capability` |

### Dev-Agent
| ID | Claim | Checks |
|----|-------|--------|
| TST-054 | Dev-agent defaults to dedicated workspace | `dev-agent-not-control-plane` |
| TST-055 | Dev-agent is supervised service | `dev-agent-supervised` |
| TST-056 | Dev-agent task is parameterized | `dev-agent-parameterized-task` |

### Hardening Baseline
| ID | Claim | Checks |
|----|-------|--------|
| TST-057 | All services have SystemCallArchitectures=native | `systemd-hardening-baseline` |
| TST-058 | Provider API keys owned by root | `agent-api-key-ownership-dev` |

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
| `tests/live/networking.bats` | Tailscale state, metadata-block rule, agent egress table |
| `tests/live/sandbox-behavioral.bats` | Sandbox deny/allow paths, protected repo rejection |
| `tests/live/agent-sandbox.bats` | Wrapper structure, nono invocation, journald logging |
| `tests/live/service-health.bats` | systemd unit health, Tailscale backend state |
| `tests/live/impermanence.bats` | /persist mount, BTRFS type, critical persist dirs, machine-id |
| `tests/live/api-endpoints.bats` | HTTP endpoint health for localhost-bound services |

## Coverage Map

Claims with no test coverage (candidates for future tests):

| Spec File | Uncovered Claims |
|-----------|-----------------|
| `secrets.md` | SCR-015 (session token randomness), SCR-020 (proxy port timeout) |
| `sandbox.md` | SBX-010 through SBX-019 (systemd-run properties — live runtime only) |
| `deployment.md` | DEP-007 through DEP-011 (watchdog — requires deploy target) |
| `backup.md` | BAK-007/BAK-008 (schedule/retention — requires deployed restic) |
| `impermanence.md` | IMP-001 through IMP-005 (rollback — requires reboot) |
