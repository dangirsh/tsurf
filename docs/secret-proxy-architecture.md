# Secret Proxy Architecture

The `secret-proxy` module provides a transparent HTTP→HTTPS forwarding proxy that
keeps real API keys out of sandboxed agent processes. Agents receive a placeholder
token and a local `BASE_URL`; the proxy validates the destination, swaps the
placeholder for the real key, and forwards to the real upstream over TLS.

## Data Flow

```
[sandboxed agent]
  ANTHROPIC_BASE_URL=http://127.0.0.1:<port>
  x-api-key: sk-placeholder-…
       │  HTTP (plain, loopback)
[secret-proxy — 127.0.0.1:<port>]
  • extract Host header → allowlist check
  • strip placeholder header
  • inject real key from file
  • forward to https://<allowed_domains[0]>/<path>
       │  HTTPS (real TLS)
[upstream API — e.g. api.anthropic.com]
```

Source files:
- `packages/secret-proxy/src/main.rs` — startup, config loading, secret file reading
- `packages/secret-proxy/src/proxy.rs` — request handler: allowlist check, header injection, forwarding
- `packages/secret-proxy/src/config.rs` — TOML schema (`Config`, `SecretConfig`)
- `packages/secret-proxy/Cargo.toml` — axum 0.8, reqwest 0.12, tokio, serde
- `packages/secret-proxy.nix` — `rustPlatform.buildRustPackage`
- `modules/secret-proxy.nix` — NixOS module: `services.secretProxy.services`

## Key Design Features

### 1. Host-Header Allowlist as Security Boundary

Every request is validated against the HTTP `Host` header before any key
injection or forwarding occurs. Only domains explicitly listed in `allowed_domains`
are accepted; all others receive HTTP 403. This prevents:

- Requests to arbitrary endpoints (exfiltration defense)
- Prompt-injection redirects to attacker-controlled URLs

### 2. Fixed Upstream (`allowed_domains[0]`)

The proxy always forwards to `allowed_domains[0]`, regardless of which entry in
the list matched the Host header. This eliminates SSRF-via-Host-header attacks
within the allowlist and simplifies routing. The semantic is:
`allowed_domains[0]` = canonical upstream; `allowed_domains[1..]` = accepted
Host aliases that still forward to `[0]`.

### 3. Plain-HTTP Agent Interface (no TLS MITM)

The agent sets `ANTHROPIC_BASE_URL=http://127.0.0.1:<port>`. The proxy
terminates HTTP and re-issues HTTPS to the real upstream. This avoids
distributing a custom CA certificate into every sandbox — the agent needs no
TLS configuration.

### 4. File-Based Secret Interface (backend-agnostic)

Secrets are paths to files (e.g. sops-nix `/run/secrets/anthropic-api-key`).
The module works with sops-nix, agenix, or any file-based secret provider.
Real keys never appear in:

- The Nix store (TOML config contains only the path, not the value)
- Environment variables
- Process arguments

Secrets are read once at startup. If any file is missing or empty the binary
aborts immediately (fail-fast).

### 5. Per-Service Isolation

Each entry in `services.secretProxy.services` gets a dedicated systemd unit
(`secret-proxy-<name>`), a dedicated system user (`secret-proxy-<name>`), and
its own port. Services cannot share keys or ports by accident.

### 6. Full Systemd Hardening (SEC66-01)

The generated systemd service includes:
`NoNewPrivileges`, `ProtectSystem=strict`, `ProtectHome`, `PrivateTmp`,
`MemoryDenyWriteExecute`, `ProtectKernelTunables`, `ProtectKernelModules`,
`RestrictAddressFamilies=AF_INET AF_INET6`, `RestrictNamespaces`,
`CapabilityBoundingSet=""`, `SystemCallArchitectures=native`, `PrivateDevices`, `ProtectKernelLogs`, `ProtectControlGroups`, `RestrictRealtime`, `RestrictSUIDSGID`, `LockPersonality`.

### 7. Declarative bwrapArgs

The module computes `bwrapArgs = ["--setenv" "<baseUrlEnvVar>" "http://127.0.0.1:<port>"]`
as a derived read-only attribute. Consumers splice this into their bubblewrap
invocations so the agent automatically sees the right `BASE_URL` without
manual wiring.

### 8. Port Collision Detection

A NixOS assertion fails config evaluation if two services declare the same port.
Port conflicts are caught at `nix flake check` time, not at runtime.

## Limitations

| ID | Description |
|----|-------------|
| L1 | **No upstream timeout.** `reqwest::Client::new()` uses library defaults. A slow upstream holds connections indefinitely. |
| L2 | **Placeholder mismatch is non-enforcing.** Mismatched `x-api-key` values generate a warning but injection proceeds. |
| L3 | **`allowed_domains` dual semantics.** The same field controls both Host acceptance and upstream routing (index 0). The name does not convey the asymmetry. |
| L4 | **Config TOML is world-readable.** Generated via `pkgs.writeText`; lands in `/nix/store`. Contains secret file paths (not values). Paths like `/run/secrets/anthropic-api-key` are predictable anyway — accepted tradeoff. |
| L5 | **No health-check endpoint.** The live test infers health from any HTTP response on the port, which passes even on 403. |
| L6 | **No rate limiting or request-size limiting.** A buggy or compromised sandbox can flood the upstream without circuit-breaking. |
| L7 | **Single upstream per secret.** No round-robin or region-specific routing across multiple Anthropic endpoints. |
| L8 | **Secret rotation requires restart.** Secrets are loaded once at startup; the unit has no `ExecReload` and no SIGHUP handler. |
| L9 | **No certificate pinning.** `reqwest::Client::new()` uses the system CA bundle only. Standard practice but notable for a security-boundary component. |
| L10 | **`bwrapArgs` not auto-wired.** The module computes `bwrapArgs` but does not inject it into `agent-compute.nix`. Consumers must splice it manually (the private overlay does this via its own `agent-compute` override). |

## Test Coverage

| Layer | Test | What it checks | Gap |
|-------|------|----------------|-----|
| Eval | `has-secret-proxy-option` | Module imported; `services.secretProxy.services` option exists | Does not check per-service config or actual values |
| Live | `secret-proxy port 9091 is responsive (neurosys only)` | Port returns an HTTP response | Does not distinguish 403 from 200; does not validate injection |
| — | — | — | No Rust unit tests for proxy logic |
| — | — | — | No BATS test for allowlist enforcement (wrong Host → 403) |
| — | — | — | No BATS test for header injection (real key appears upstream) |
| — | — | — | No BATS test for placeholder-validation behavior |

## Improvement Areas

These are documented for future phases. This document does not implement any of them.

| ID | Priority | Description |
|----|----------|-------------|
| I1 | High | Add explicit upstream connect/read timeouts to `reqwest::Client` |
| I2 | Medium | Rename `allowed_domains` to `upstream_domain` + `also_accept_domains` to make the asymmetry explicit |
| I3 | Medium | Add `GET /health` returning `{"status":"ok","service":"<name>"}` |
| I4 | Low | Add `enforce_placeholder = true` option to reject (403) requests with wrong placeholder |
| I5 | Low | Add `ExecReload` + SIGHUP handler to re-read secrets without full restart |
| I6 | High | Add BATS integration tests for allowlist enforcement and header injection |
| I7 | Low | Add `ReadPaths` to systemd unit for secret file paths (currently relying on `/run/secrets` default) |

## Summary

The secret-proxy is a minimal, well-scoped security boundary for sandboxed agent
API access. At ~320 lines of Rust and ~175 lines of Nix it is small enough to
fully audit in one session.

**Core strengths:** backend-agnostic file interface, Host-allowlist exfiltration
defense, fixed upstream SSRF prevention, per-service systemd isolation with
comprehensive hardening directives, declarative NixOS module.

**Key gaps to address before production hardening:** upstream timeout (L1/I1)
and BATS integration tests (I6). All other limitations are documented accepted
tradeoffs or low-priority improvements.
