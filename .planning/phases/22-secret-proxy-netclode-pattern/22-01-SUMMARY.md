---
phase: 22-secret-proxy-netclode-pattern
plan: 01
subsystem: agent-security
tags: [nixos, secret-proxy, sops, bubblewrap, anthropic, python, systemd]

requires:
  - phase: 11-agent-sandboxing-default-on-bubblewrap-srt-isolation-for-all-coding-agents
    provides: "bubblewrap sandbox with --clearenv; agent-spawn reads secrets pre-sandbox and injects via --setenv"

provides:
  - "anthropic-secret-proxy systemd service (port 9091) — real Anthropic key never enters sandbox env"
  - "claw-swap agent sandboxes get ANTHROPIC_API_KEY=placeholder + ANTHROPIC_BASE_URL=http://127.0.0.1:9091"
  - "proxy reads real key from sops template owned by secret-proxy system user"
  - "port 9091 added to internalOnlyPorts build-time assertion"
  - "deployed and smoke-tested: proxy replaces x-api-key header transparently, real response confirmed"
affects: [modules-secret-proxy, modules-agent-compute, modules-networking, modules-default]

tech-stack:
  added: [anthropic-secret-proxy (writePython3Bin), secret-proxy system user, sops.templates.secret-proxy-env]
  patterns: [ANTHROPIC_BASE_URL redirect (no TLS MITM), sops template with least-privilege file ownership]

key-files:
  created:
    - modules/secret-proxy.nix
  modified:
    - modules/agent-compute.nix
    - modules/networking.nix
    - modules/default.nix

approach-change:
  original-plan: TLS MITM via HTTPS_PROXY + CA cert injection + PROXY_TOKEN bearer auth (plans 22-02, 22-03)
  implemented: ANTHROPIC_BASE_URL redirect to plain-HTTP local proxy; SDK speaks HTTP to proxy, proxy speaks HTTPS upstream
  rationale: No TLS MITM complexity, no cert injection into sandbox, no CA trust bootstrapping needed
  tradeoffs: Only works for Anthropic SDK (respects ANTHROPIC_BASE_URL); OPENAI_BASE_URL, GOOGLE_BASE_URL etc. needed separately for other providers

scope: claw-swap projects only (PROJECT_DIR == /data/projects/claw-swap*); other projects still receive real key until full rollout

bugs-fixed-during-deploy:
  - "x-api-key header required (not Authorization: Bearer) — Anthropic rejects Bearer for sk-ant-api03- keys"
  - "strip() on KEY to handle trailing whitespace from sops template EnvironmentFile rendering"
  - "allow_reuse_address=True to survive EADDRINUSE during NixOS service restart race"
  - "pass Content-Length through response (only strip Transfer-Encoding + Connection) for proper HTTP framing"

stale-plans:
  - 22-02-PLAN.md: designed for TLS MITM with CA cert + PROXY_TOKEN — superseded, deleted
  - 22-03-PLAN.md: designed for TLS MITM validation — superseded, deleted
---

Implemented the secret proxy for Anthropic API key isolation in agent sandboxes (claw-swap scope).

## What Changed

**`modules/secret-proxy.nix`** (new) — ~60-line Python stdlib reverse proxy (`writePython3Bin`). Binds to `127.0.0.1:9091`, strips incoming `x-api-key`/`authorization` headers, injects real key from `REAL_ANTHROPIC_API_KEY` env var (sourced from sops template), forwards to `https://api.anthropic.com`. Runs as `secret-proxy` system user with sops template owned by that user.

**`modules/agent-compute.nix`** — claw-swap project sandboxes get:
- `ANTHROPIC_API_KEY=sk-ant-api03-proxy000...AA` (placeholder)
- `ANTHROPIC_BASE_URL=http://127.0.0.1:9091`

All other projects continue receiving the real key (unchanged behavior).

**`modules/networking.nix`** — `9091` added to `internalOnlyPorts` (build-time assertion prevents public exposure).

**`modules/default.nix`** — imports `./secret-proxy.nix`.

## Key Decision: Approach Pivot

Plans 22-02 and 22-03 specified a TLS MITM approach using `HTTPS_PROXY`, CA cert injection into sandbox trust stores, and a `PROXY_TOKEN` bearer auth scheme. This was superseded by the simpler `ANTHROPIC_BASE_URL` approach: the Anthropic SDK respects this env var and makes plain HTTP requests to the proxy, so no TLS interception or cert injection is needed. Plans 22-02 and 22-03 were deleted as obsolete.

## Smoke Test Result

```
curl http://127.0.0.1:9091/v1/messages -H "x-api-key: sk-ant-placeholder" ...
→ {"type":"message","content":[{"type":"text","text":"Hi! 👋"}],...}
```

Real key injected server-side; placeholder key accepted by proxy and never forwarded.

## Remaining Work (deferred to agentic-dev-maxing phase)

- Remove `[[ "$PROJECT_DIR" == /data/projects/claw-swap* ]]` guard to roll out to all projects
- Add similar proxy support for OPENAI_BASE_URL, OPENROUTER_BASE_URL etc.
