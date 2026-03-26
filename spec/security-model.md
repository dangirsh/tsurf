# Security Model Specification

This document specifies the core security invariants, threat model, and privilege separation
boundaries that tsurf implements. All claims are derived from source code, `@decision` annotations,
and build-time assertions.

Source: `SECURITY.md`, `modules/users.nix`, `modules/networking.nix`, `modules/agent-sandbox.nix`

## Threat Model

The system assumes:
- Root is the operator, trusted with full administrative access (deploy, maintenance, SSH).
- The agent user is untrusted — it runs LLM-directed code that may be adversarial.
- The host network is partially hostile (public internet on eth0).
- Secrets are high-value targets (API keys, SSH keys).

## Non-Deployability

| ID | Claim | Source |
|----|-------|--------|
| SEC-001 | Public flake exports only eval-prefixed nixosConfigurations (`eval-services`, `eval-dev`, `eval-dev-alt-agent`) | `flake.nix` lines 103-110 |
| SEC-002 | Public flake exports no `deploy.nodes` targets | `flake.nix`, `tests/eval/config-checks.nix:public-deploy-empty` |
| SEC-003 | `scripts/deploy.sh` refuses to deploy unless the enclosing flake contains a `tsurf.url` input | `scripts/deploy.sh` safety guard |
| SEC-004 | All exported nixosConfigurations are prefixed with `eval-` | `tests/eval/config-checks.nix:fixture-output-names` |

## Eval Fixture Isolation

| ID | Claim | Source |
|----|-------|--------|
| SEC-005 | `tsurf.template.allowUnsafePlaceholders` defaults to `false` | `modules/users.nix` line 21 |
| SEC-006 | Host source files (`hosts/services/default.nix`, `hosts/dev/default.nix`) do not set `allowUnsafePlaceholders` | `tests/eval/config-checks.nix:secure-host-services`, `secure-host-dev` |
| SEC-007 | Eval fixtures inject `allowUnsafePlaceholders = true` via `mkEvalFixture` only | `flake.nix` line 95 |
| SEC-008 | When `allowUnsafePlaceholders` is false, build-time assertions require at least one root SSH authorized key | `modules/users.nix` |
| SEC-009 | `allowUnsafePlaceholders` exists only to let eval fixtures omit private root SSH material and bypass the root-login lockout assertion (`users.allowNoPasswordLogin = true`) | `modules/users.nix`, `flake.nix` |

## Privilege Separation

| ID | Claim | Source |
|----|-------|--------|
| SEC-010 | Two-user model: `root` (operator) and `agent` (sandboxed tools) | `modules/users.nix`, `@decision SEC-152-01` |
| SEC-011 | Agent user is not in `wheel`; launcher sudo access comes from explicit sudoers rules only | `modules/users.nix`, `modules/agent-launcher.nix` |
| SEC-012 | Agent user is NOT in `docker` group — enforced by build-time assertion | `modules/users.nix` line 86 |
| SEC-014 | `users.mutableUsers = false` — no runtime user modification | `modules/users.nix` line 59 |
| SEC-015 | Agent user identity is parameterized via `tsurf.agent.{user, uid, gid, home, projectRoot}` | `modules/users.nix` lines 30-56 |
| SEC-016 | Non-default agent identity propagates correctly through users and sandbox modules | `tests/eval/config-checks.nix:alt-agent-parameterization` |

## Nix Daemon Access Control

| ID | Claim | Source |
|----|-------|--------|
| SEC-017 | `nix.settings.allowed-users = [ "root" "<agent-user>" ]` | `modules/base.nix`, `@decision SEC-124-01` |
| SEC-018 | `nix.settings.trusted-users = [ "root" ]` — root-only | `modules/base.nix` |
| SEC-019 | Nix channels disabled, nixPath cleared, defaultPackages emptied | `modules/base.nix` lines 11-13, `@decision SYS-02` |

## Kernel Hardening

| ID | Claim | Source |
|----|-------|--------|
| SEC-020 | Kernel hardening via nix-mineral (compatibility preset): dmesg_restrict, kptr_restrict, bpf hardening, ICMP redirects, etc. | `modules/base.nix`, `@decision SEC-145-05` |

## Supply Chain

| ID | Claim | Source |
|----|-------|--------|
| SEC-026 | All Nix inputs pinned by `flake.lock` | `flake.nix` |
| SEC-027 | Prebuilt binaries (`nono`, `cass`) are SHA256-pinned | `packages/nono.nix`, `extras/cass.nix` |
| SEC-028 | `claude-code` and `codex` come from the pinned `llm-agents.nix` input | `flake.nix` line 18 |
| SEC-029 | No signature verification for prebuilt binaries (accepted risk) | `SECURITY.md` |
| SEC-030 | Supply chain env vars set in agent wrapper: `NPM_CONFIG_IGNORE_SCRIPTS=true`, `NPM_CONFIG_AUDIT=true`, `NPM_CONFIG_SAVE_EXACT=true`, `NPM_CONFIG_MINIMUM_RELEASE_AGE=1440` | `scripts/agent-wrapper.sh` lines 225-228 |
| SEC-031 | Telemetry suppressed: `DISABLE_TELEMETRY=1`, `DISABLE_ERROR_REPORTING=1`, `CLAUDE_CODE_DISABLE_FEEDBACK_SURVEY=1` | `scripts/agent-wrapper.sh` lines 231-233 |

## No-Sandbox Escape

| ID | Claim | Source |
|----|-------|--------|
| SEC-032 | Public wrapper has no `--no-sandbox` or `AGENT_ALLOW_NOSANDBOX` escape hatch | `tests/eval/config-checks.nix:public-no-sandbox-removed` |
| SEC-033 | Raw agent binaries are NOT installed in PATH by `agent-compute.nix` | `tests/eval/config-checks.nix:agent-binaries-not-in-path`, `@decision SEC-116-01` |

## Accepted Risks

| ID | Risk | Source |
|----|------|--------|
| SEC-AR-001 | Service-host role does not include agent sandbox | `SECURITY.md` |
| SEC-AR-002 | Sandbox does not make current workspace immutable — writable by design | `SECURITY.md` |
| SEC-AR-003 | Agent egress allowlist is coarse (UID-scoped, not per-wrapper or per-destination) | `SECURITY.md` |
| SEC-AR-004 | No signature verification for prebuilt binaries | `SECURITY.md` |
| SEC-AR-005 | Operators must keep agents away from repos that define their own security boundaries; the public wrapper does not classify repos automatically | `SECURITY.md` |
