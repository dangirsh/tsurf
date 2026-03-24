# Secrets Management Specification

This document specifies how secrets are stored, decrypted, owned, and injected
into agent processes.

Source: `modules/secrets.nix`, `scripts/agent-wrapper.sh`, `scripts/credential-proxy.py`

## Secret Storage

| ID | Claim | Source |
|----|-------|--------|
| SCR-001 | Secrets managed via sops-nix with age encryption | `flake.nix` (sops-nix input), `SECURITY.md` |
| SCR-002 | Age identity derived from host SSH ed25519 key | `SECURITY.md` |
| SCR-003 | Secrets decrypted to `/run/secrets` at activation time | sops-nix behavior |
| SCR-004 | `setupSecrets` activation depends on `persist-files` — ensures SSH host key available before decryption after hard reboot | `modules/impermanence.nix` lines 12-14, `@decision IMP-06` |

## Secret Ownership

| ID | Claim | Source |
|----|-------|--------|
| SCR-005 | `anthropic-api-key` owned by `root` | `SECURITY.md`, `tests/eval/config-checks.nix:agent-api-key-ownership-dev` |
| SCR-006 | `openai-api-key` owned by `root` | `SECURITY.md`, `tests/eval/config-checks.nix:agent-api-key-ownership-dev` |
| SCR-007 | `google-api-key` owned by `dev` | `SECURITY.md` |
| SCR-008 | `xai-api-key` owned by `dev` | `SECURITY.md` |
| SCR-009 | `openrouter-api-key` owned by `dev` | `SECURITY.md` |
| SCR-010 | `github-pat` owned by `dev` | `SECURITY.md` |
| SCR-011 | `tailscale-authkey` owned by root/default | `SECURITY.md` |
| SCR-012 | Backup secrets (`b2-account-id`, `b2-account-key`, `restic-password`) owned by root/default | `SECURITY.md` |

## Credential Proxy (Broker Model)

| ID | Claim | Source |
|----|-------|--------|
| SCR-013 | Agent wrapper starts a root-owned loopback credential proxy before privilege drop | `scripts/agent-wrapper.sh` lines 129-155, `tests/eval/config-checks.nix:proxy-credential-wrapper` |
| SCR-014 | Proxy reads raw secret files from `/run/secrets` as root | `scripts/agent-wrapper.sh` lines 104-113 |
| SCR-015 | Per-session random tokens generated (64 hex chars from `/dev/urandom`) | `scripts/agent-wrapper.sh` lines 80-82, 115 |
| SCR-016 | Child process receives only session token (e.g., `ANTHROPIC_API_KEY=<64-hex-token>`) and localhost base URL (e.g., `ANTHROPIC_BASE_URL=http://127.0.0.1:<port>/anthropic`) | `scripts/agent-wrapper.sh` lines 117-119 |
| SCR-017 | Child process does NOT receive raw `/run/secrets/*` files or raw provider API keys | `SECURITY.md`, `@decision SEC-145-01` |
| SCR-018 | Missing secret files produce a warning and empty env var — not a hard failure | `scripts/agent-wrapper.sh` lines 105-108 |
| SCR-019 | Values prefixed with `PLACEHOLDER` are skipped silently | `scripts/agent-wrapper.sh` lines 111-113 |
| SCR-020 | Proxy port published to a temp file; wrapper waits up to 5 seconds for port publication | `scripts/agent-wrapper.sh` lines 137-148 |
| SCR-021 | Proxy cleanup on exit: proxy process killed, temp directory removed | `scripts/agent-wrapper.sh` lines 59-70 |

## Credential Scoping

| ID | Claim | Source |
|----|-------|--------|
| SCR-022 | Each wrapper carries a per-wrapper `AGENT_CREDENTIALS` allowlist of `SERVICE:ENV_VAR:secret-file-name` triples | `scripts/agent-wrapper.sh` line 17, `modules/agent-sandbox.nix` line 46 |
| SCR-023 | Core Claude wrapper: Anthropic only | `modules/agent-sandbox.nix` line 46 |
| SCR-024 | Codex wrapper: OpenAI only | `extras/codex.nix` line 97 |
| SCR-025 | Extra agents must opt into credentials explicitly | `SECURITY.md` |

## Privilege Drop

| ID | Claim | Source |
|----|-------|--------|
| SCR-026 | After proxy setup, agent binary launched via `setpriv --reuid --regid --init-groups --reset-env` | `scripts/agent-wrapper.sh` lines 200-208 |
| SCR-027 | Child environment reset: only `HOME`, `USER`, `LOGNAME`, `PATH`, `TERM`, `LANG`, session tokens, and hardening env vars | `scripts/agent-wrapper.sh` lines 209-234 |
