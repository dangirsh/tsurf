# Phase 71 Research — Secret Proxy Reference Documentation & Issue Audit

## 1. Current Implementation Audit

### 1.1 Repository layout

```
nix-secret-proxy/
  src/main.rs       — entrypoint, CLI arg parsing, secret loading, server startup
  src/config.rs     — TOML schema (Config, SecretConfig)
  src/proxy.rs      — axum router, request handling, upstream forwarding
  module.nix        — NixOS module (services.secretProxy.services.<name>)
  package.nix       — rustPlatform.buildRustPackage
  flake.nix         — packages, nixosModules.default, overlays.default
  README.md         — minimal usage doc
```

### 1.2 main.rs

- **CLI interface**: single required flag `--config <path>`. No other flags. No env-var overrides for config path.
- **Startup sequence**:
  1. Initialize `tracing_subscriber` with `RUST_LOG` env var; default level `info` for the `secret_proxy` crate.
  2. Parse `--config <path>` from `argv`.
  3. Read and TOML-parse the config file. Hard `exit(1)` on any error.
  4. For each `[[secret]]` entry:
     - Validate `allowed_domains` is non-empty.
     - Read `file` contents (the real key). Hard `exit(1)` on read failure or empty file.
     - `.trim()` the key value. Normalize domains to lowercase.
     - Set `upstream_host = allowed_domains[0]`.
  5. Build a `reqwest::Client::new()` (default settings — no timeout, no TLS verification override, system roots).
  6. Bind to `SocketAddr::from(([127, 0, 0, 1], config.port))` — **hardcoded 127.0.0.1**; not configurable.
  7. Call `axum::serve(listener, app).await.unwrap()` — no graceful shutdown hook.

- **No signal handling** — `axum::serve` runs until the process is killed. SIGTERM drops in-flight connections.
- **No health endpoint** — no `/health` or `/ready` route. The test in `api-endpoints.bats` calls port 9091 root path and accepts any HTTP status.

### 1.3 config.rs

TOML schema:

```toml
port = <u16>                   # required; no default
placeholder = "<string>"       # required; no default

[[secret]]
header = "x-api-key"           # required; header to inject
name = "anthropic-api-key"     # required; used in log messages
file = "/run/secrets/..."      # required; path to secret file
allowed_domains = ["api.anthropic.com"]  # required; non-empty list
```

- **No `bind` field** — bind address is hardcoded to `127.0.0.1` in main.rs.
- **No `timeout` field** — no configurable upstream timeout.
- **No `max_body_size` field** — no configurable body limit.
- **No `log_level` field** — log level controlled via `RUST_LOG` env var.
- Config file is embedded in the Nix store (via `pkgs.writeText`) and references secret file paths at runtime. The config file itself contains no secrets.

### 1.4 proxy.rs

**Request path:**
1. Extract `Host` header (strips port suffix, lowercases). Returns 403 if missing or empty.
2. Match `Host` against `allowed_domains` across all loaded secrets. Returns 403 on no match.
3. Build `forward_headers`: copy all incoming headers **except** `REQUEST_SKIP_HEADERS`:
   - `x-api-key`, `authorization`, `host`, `content-length`, `transfer-encoding`
4. Insert the real key as `<secret.header>` in `forward_headers`.
5. Construct target URL: `https://<allowed_domains[0]><path_and_query>` — upstream host is **always** the first configured domain, regardless of what the client sends in the Host header. This is the SSRF-prevention design.
6. Forward the request via `reqwest`, streaming the body via `reqwest::Body::wrap_stream(body.into_data_stream())`.
7. **Response is also streamed**: `upstream_response.bytes_stream()` → `Body::from_stream(upstream_stream)`. This is a true streaming pipeline; the response body is never buffered.
8. Copy response headers except `RESPONSE_SKIP_HEADERS`: `transfer-encoding`, `connection`.

**Streaming verdict**: The proxy is fully streaming in both directions (request body and response body). It does NOT call `body::to_bytes` anywhere. SSE (Server-Sent Events) streams should pass through correctly, assuming the downstream HTTP client handles streaming.

**Placeholder validation**: If the incoming request has the secret header (e.g., `x-api-key`) set to a value other than the configured placeholder, the proxy logs a `warn` but still proceeds to inject the real key. This is intentional: it means clients that happen to send any value (or the right placeholder) all get the real key injected. The placeholder check is informational, not a gate.

**Both `x-api-key` AND `authorization` are stripped** from incoming headers regardless of which one is configured for injection. This means if a client sends an `Authorization: Bearer ...` header for a different purpose (e.g., a different auth scheme), it is silently dropped. This could be an issue for non-Anthropic APIs that use `Authorization`.

**Error responses** on upstream failure: plain text `"Upstream request failed\n"` with HTTP 502. No JSON formatting. Anthropic SDKs that parse error responses looking for `{"error": {...}}` will receive an unexpected body and may surface confusing errors.

### 1.5 module.nix

NixOS options exposed:

| Option | Type | Default | Notes |
|--------|------|---------|-------|
| `services.secretProxy.package` | package | `pkgs.callPackage ./package.nix {}` | Override the binary |
| `services.secretProxy.services.<name>.port` | port | (required) | Loopback port |
| `services.secretProxy.services.<name>.placeholder` | string | `"sk-placeholder-${name}"` | Fake token |
| `services.secretProxy.services.<name>.baseUrlEnvVar` | string | `"ANTHROPIC_BASE_URL"` | Env var name |
| `services.secretProxy.services.<name>.secrets.<key>.headerName` | string | (required) | Header to inject |
| `services.secretProxy.services.<name>.secrets.<key>.secretFile` | path | (required) | File path |
| `services.secretProxy.services.<name>.secrets.<key>.allowedDomains` | nonEmptyListOf str | (required) | Host allowlist |
| `services.secretProxy.services.<name>.bwrapArgs` | listOf str | (read-only, computed) | `["--setenv" <baseUrlEnvVar> "http://127.0.0.1:<port>"]` |

**Systemd hardening** (per service unit):
- `User = "secret-proxy-${name}"` (dedicated system user)
- `NoNewPrivileges = true`
- `ProtectSystem = "strict"`
- `ProtectHome = true`
- `PrivateTmp = true`
- `MemoryDenyWriteExecute = true`
- `ProtectKernelTunables / Modules / Logs = true`
- `ProtectControlGroups = true`
- `RestrictAddressFamilies = [ "AF_INET" "AF_INET6" ]`
- `RestrictNamespaces = true`
- `RestrictRealtime = true`
- `RestrictSUIDSGID = true`
- `CapabilityBoundingSet = ""`
- `SystemCallArchitectures = "native"`
- `LockPersonality = true`
- `PrivateDevices = true`

**No `ReadOnlyPaths` / `ReadWritePaths`** set — relies on `ProtectSystem = strict` which makes most paths read-only. The secret file path is under `/run/secrets` (sops-nix), which `ProtectSystem = strict` keeps accessible at startup (secrets are read once at startup, not on every request).

**Assertion**: duplicate port detection across all `services.secretProxy.services` entries.

**bwrapArgs**: computed read-only attribute — the caller (e.g., `agent-compute.nix`) splices these into bubblewrap invocations to set `ANTHROPIC_BASE_URL` inside the sandbox.

**TOML config file**: generated via `pkgs.writeText` and stored in the Nix store. It references secret *file paths* (not the secret values themselves). The real keys never appear in the Nix store.

### 1.6 package.nix

- `rustPlatform.buildRustPackage` with `cargoLock.lockFile = ./Cargo.lock`.
- `nativeBuildInputs = [ pkgs.pkg-config ]`, `buildInputs = [ pkgs.openssl ]`.
- `meta.platforms = [ "x86_64-linux" ]` — **aarch64-linux not listed in meta.platforms** even though `flake.nix` generates packages for both systems.

### 1.7 flake.nix

- `packages`: `secret-proxy` + `default` for `x86_64-linux` and `aarch64-linux`.
- `nixosModules.default`: `./module.nix`.
- `overlays.default`: exposes `secret-proxy` in pkgs.
- `checks`: just the build derivation (no unit tests, no integration tests).

### 1.8 Current README

The README covers:
- One-paragraph "how it works" description (3 bullet points)
- Flake input + module import snippet
- Three NixOS config examples (sops-nix, agenix, plain file)
- Options table (7 rows)
- 4-bullet security section

**Missing from current README:**
- No explanation of the threat model or what the proxy protects against / does not protect against
- No attribution to Stanislas Polu / Netclode
- No non-NixOS usage (Docker, systemd, bare-metal)
- No configuration reference for the TOML config file format
- No mention of streaming/SSE behavior
- No mention of known limitations or caveats
- No placeholder format guidance (SDK key format validation)
- No mention of multi-secret support (single proxy instance can inject multiple secrets for multiple domains)
- No architecture diagram or conceptual overview
- No mention of `RUST_LOG` for debugging

---

## 2. Issue Verification

Each issue from the roadmap, verified against the source code:

### 2.1 Streaming / SSE

**Verdict: NOT a problem. Fully streaming.**

- Request body: `reqwest::Body::wrap_stream(body.into_data_stream())` — streams request body to upstream without buffering.
- Response body: `upstream_response.bytes_stream()` → `Body::from_stream(upstream_stream)` — streams response back to client without buffering.
- The proxy never calls `body::to_bytes()`.
- SSE responses (which use `text/event-stream` with chunked encoding) should pass through correctly. The `transfer-encoding: chunked` response header is filtered out (in `RESPONSE_SKIP_HEADERS`), but axum/hyper handles framing independently of this header for HTTP/1.1 responses.

**Nuance**: `content-type: text/event-stream` is NOT in the skip list and will be forwarded. The SSE event stream itself flows through the `Body::from_stream` pipeline. This is correct behavior.

**Note for documentation**: Confirm that `transfer-encoding` filtering from response does not break SSE in practice. The filtering is necessary because re-encoding headers from an HTTP/1.1 upstream response can confuse downstream HTTP/1.1 clients; axum handles the actual framing.

### 2.2 Bind address

**Verdict: NOT a problem in current code. Hardcoded to 127.0.0.1.**

`main.rs` line 90: `let addr = SocketAddr::from(([127, 0, 0, 1], config.port));`

This is hardcoded; there is no `bind` field in `config.rs`. The roadmap Phase 72 plans to add a `bind` config field. The current hardcoded 127.0.0.1 is correct for NixOS deployments but prevents use with Docker containers (which need `host.docker.internal` or a bridge IP). This is an **informational** issue for the current phase — a real limitation but not a bug in the stated use case.

### 2.3 Body size limit

**Verdict: REAL issue — no limit configured.**

Axum has a default body size limit of 2 MB (`DefaultBodyLimit::max(2_097_152)`). However, inspecting `make_router`:

```rust
pub fn make_router(state: Arc<ProxyState>) -> Router {
    Router::new()
        .route("/", any(proxy_handler))
        .route("/{*path}", any(proxy_handler))
        .with_state(state)
}
```

No `layer(DefaultBodyLimit::max(...))` is applied. Axum 0.8 applies a default body limit of 2 MB unless explicitly overridden. For Anthropic API calls with large image inputs (base64-encoded), payloads can easily exceed 2 MB. A 2 MB limit would return a 413 with a generic error, confusing callers.

**Severity: Degraded** — will block multimodal (vision) API calls with large images.

### 2.4 Upstream timeout

**Verdict: REAL issue — no timeout configured.**

`reqwest::Client::new()` creates a client with no connection timeout and no request timeout. Extended Anthropic thinking can take several minutes. However, if the upstream hangs indefinitely (network partition), the proxy will hold the connection open forever. Tokio will not kill the future; it will just sit there consuming a connection slot.

**Severity: Degraded** — not immediately breaking for normal use, but a robustness issue for long-running or hung requests.

### 2.5 Health endpoint

**Verdict: REAL issue — no health route.**

`make_router` only registers `/` and `/{*path}` — both handled by `proxy_handler`. There is no `/health` or similar route. A request to `/health` with no `Host` header (or a Host not in the allowlist) returns HTTP 403.

The live test in `api-endpoints.bats` works around this by making a bare curl to the root and accepting any HTTP status. This is not a real health check.

**Severity: Informational** — operational inconvenience; no functional breakage.

### 2.6 TLS verification

**Verdict: NOT a problem.**

`reqwest::Client::new()` uses the system's native TLS stack with default settings. It does NOT call `danger_accept_invalid_certs(true)` or similar. TLS to upstream (e.g., `api.anthropic.com`) is fully verified using system certificate roots (openssl on NixOS).

### 2.7 Header forwarding

**Verdict: Mostly correct, one edge case.**

Request skip list: `x-api-key`, `authorization`, `host`, `content-length`, `transfer-encoding`.

- `x-api-key` and `authorization` are stripped from incoming headers, then the configured header (whichever it is) is injected with the real key. This is correct.
- `host` is stripped — correct, because the upstream target URL already encodes the correct host.
- `content-length` is stripped — correct, because reqwest will compute the correct content-length for the potentially re-framed body.
- `transfer-encoding` is stripped — correct for HTTP/1.1 to HTTP/1.1 forwarding with re-framing.

**Edge case**: Both `x-api-key` AND `authorization` are always stripped, regardless of which one is configured for injection. If a downstream service uses `Authorization` for something other than the API key (e.g., a JWT for a different auth system that also happens to be in `allowedDomains`), it will be silently dropped. In practice this is unlikely for the current use case (Anthropic API only uses `x-api-key`), but it's a documentation gap.

**Another edge case**: The `content-type` header is forwarded as-is. For SSE requests, the client should send `Accept: text/event-stream`; this is forwarded correctly.

**Rate-limiting headers**: `retry-after` and `x-ratelimit-*` are NOT in `RESPONSE_SKIP_HEADERS`, so they are forwarded from upstream to the client. This is correct behavior.

### 2.8 Error response format

**Verdict: REAL issue — non-JSON 502 on upstream failure.**

When `state.client.request(...).send().await` fails (connection refused, DNS failure, timeout), the proxy returns:

```
HTTP/1.1 502 Bad Gateway
Content-Type: (none)

Upstream request failed
```

The Anthropic SDK expects error responses in the format:
```json
{"error": {"type": "...", "message": "..."}}
```

A plain-text 502 body will cause SDK exception parsing to fail, resulting in confusing stack traces rather than a clear "proxy unreachable" error.

**Severity: Degraded** — bad developer experience when the proxy is down or misconfigured.

### 2.9 Graceful shutdown

**Verdict: REAL issue — no graceful shutdown.**

`axum::serve(listener, app).await.unwrap()` runs forever. There is no `with_graceful_shutdown` hook. On SIGTERM (systemd stop), the process is killed immediately, dropping any in-flight streaming responses mid-stream.

For SSE/streaming responses this means the client will see a truncated response and likely get a connection-reset error, possibly mid-event.

The systemd unit has `Restart = "on-failure"` but no `TimeoutStopSec` override. Systemd defaults to 90s timeout before SIGKILL — since the process terminates immediately on SIGTERM (no signal handling), this is not a practical problem. The issue is that in-flight requests are not drained.

**Severity: Degraded for streaming** — SSE responses can be truncated on service restart; non-streaming requests will likely complete before systemd issues SIGTERM.

### 2.10 Multi-agent rate limiting

**Verdict: INFORMATIONAL — by design, not a bug.**

All agents using the same proxy instance share the single real API key. No per-agent quota enforcement exists or is architecturally feasible without significant additional complexity (tracking per-sandbox placeholder→request mapping).

**Severity: Informational** — documented limitation.

### 2.11 Per-request audit trail

**Verdict: PARTIAL.**

The proxy logs:
- `ALLOW method={} host={} secret_name={} upstream={}` on each forwarded request
- `DENY host={} secret_name=<none>` on blocked requests

What is NOT logged:
- No request ID
- No response status code from upstream
- No token counts / response size
- No caller identity (which sandbox, which agent invocation)

Logs go to stdout and are captured by journald in the systemd unit. Attribution to a specific sandbox requires correlating timestamps with agent audit logs.

**Severity: Informational** — current logging is useful but not comprehensive.

### 2.12 Proxy chaining (corporate HTTP proxy)

**Verdict: INFORMATIONAL — reqwest honors env vars, but undocumented.**

`reqwest::Client::new()` respects `HTTP_PROXY`, `HTTPS_PROXY`, `NO_PROXY` environment variables by default (via the `reqwest` default proxy feature). The systemd unit does not set these. In a corporate proxy environment, the operator would need to add `Environment = "HTTPS_PROXY=..."` to the systemd service configuration (NixOS: `serviceConfig.Environment`).

**Severity: Informational** — not broken, just undocumented.

### 2.13 Docker / container networking

**Verdict: REAL limitation — 127.0.0.1 is unreachable from Docker containers.**

`main.rs` hardcodes `127.0.0.1`. Docker containers have their own network namespace. `127.0.0.1` inside a container refers to the container loopback, not the host. Agents running in Docker containers cannot reach the proxy at `http://127.0.0.1:<port>`.

Workarounds (to be documented, not fixed in this phase):
- Run the proxy in the same container as the agent (not recommended — defeats isolation).
- Bind to `0.0.0.0` or the Docker bridge IP (e.g., `172.17.0.1`) — requires Phase 72 `bind` config field.
- Use `host.docker.internal` DNS name (Docker Desktop / macOS only; not available on Linux).
- Use `--network host` mode in Docker to let the container share the host network namespace.

**Severity: Blocking for Docker deployments** — this is why the Docker usage guide in 71-01 needs explicit documentation of the workaround.

### 2.14 IPv6

**Verdict: UNTESTED.**

The bind address is hardcoded to IPv4 `127.0.0.1`. IPv6 loopback (`::1`) is not supported. Dual-stack is not supported. Upstream connections via reqwest will use IPv6 if the DNS resolution returns an AAAA record and the system prefers IPv6, but this is untested.

**Severity: Informational** — not relevant to current deployments.

### 2.15 SDK key format validation

**Verdict: REAL issue — placeholder format may fail SDK-side validation.**

Several SDKs validate the key format before sending the request:
- The official Anthropic Python SDK (`anthropic-sdk-python`) validates that the key matches a specific pattern (historically `sk-ant-*`, now more permissive but still checks).
- The default placeholder `"sk-placeholder-${name}"` (e.g., `"sk-placeholder-my-agent"`) does NOT match `sk-ant-*`.
- If an SDK performs client-side key format validation, the request will fail before it even reaches the proxy.

**Verified from module.nix**: `default = "sk-placeholder-${name}"`. This does not resemble a real Anthropic key.

**Workaround (to be documented)**: use a placeholder like `sk-ant-api03-placeholder-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA` (84 characters after `sk-ant-api03-`).

**Severity: Blocking** if the SDK validates key format client-side. Which SDK versions enforce this is unclear and needs documentation.

### 2.16 `authorization` header stripping for non-x-api-key APIs

**Verified**: proxy unconditionally strips both `x-api-key` and `authorization` from incoming requests. If a caller needs to use `Authorization: Bearer` for an allowed domain (OpenAI-compatible endpoint), the caller's `Authorization` header is dropped and only the configured header is injected.

This is actually a documented (implicit) design constraint: the proxy is designed for Anthropic's `x-api-key`. OpenAI-compat requires a second proxy instance using `headerName = "authorization"` with value `Bearer <key>`.

**Severity: Informational** — by design, but undocumented.

---

## 3. Documentation Gaps

The current README is missing the following (prioritized for 71-01 and 71-02):

### 3.1 Conceptual understanding (for 71-01)
- What the pattern is and why it exists (the "problem statement")
- What it protects against and what it explicitly does NOT protect against
- Trust boundaries diagram: sandbox process → HTTP → proxy → HTTPS → Anthropic API
- Attribution to Stanislas Polu / Netclode blog post

### 3.2 Non-NixOS usage guides (for 71-01)
- Docker Compose: how to run the proxy as a sidecar, expose on bridge network, set agent env vars
- Plain systemd (bare-metal, Ubuntu): how to run `secret-proxy` as a systemd service with a secrets file, without NixOS
- CI: ephemeral deployment (e.g., GitHub Actions) for sandboxed agent runs

### 3.3 Config reference (for 71-01)
- Complete TOML config file documentation (all fields, types, required/optional, defaults)
- Multiple `[[secret]]` blocks in one config file (multi-domain support)
- `RUST_LOG` env var for debug logging

### 3.4 Issue catalogue (for 71-02)
- Every issue in section 2 above, formatted as a structured catalogue

---

## 4. Pattern Comparison: Netclode vs nix-secret-proxy

### Stanislas Polu's Netclode approach (from blog post)

The February 2026 post describes a more complex variant:

1. **Transport**: Uses HTTP CONNECT / HTTPS MITM (acts as a real HTTPS proxy with its own CA cert). The sandbox has the proxy CA cert in its trust store. This enables the proxy to intercept HTTPS traffic without the sandbox knowing the upstream is being proxied.
2. **Caller identity validation**: Validates a ServiceAccount token (Kubernetes-style) before substituting the key. This provides per-caller isolation — different sandboxes can present different SA tokens and get different real keys, or be denied.
3. **Per-session key selection**: Based on the SDK type / caller identity, the proxy selects which real key to use from a pool.
4. **More complete SSRF protection**: Because HTTPS is properly intercepted, the proxy can enforce domain allowlists more rigorously at the TLS layer.

### nix-secret-proxy approach (simpler variant)

1. **Transport**: HTTP only between sandbox and proxy. The sandbox sets `ANTHROPIC_BASE_URL=http://127.0.0.1:<port>`. The proxy makes the HTTPS connection to upstream. No CA cert needed.
2. **No caller identity**: Any process that can reach the proxy port gets key substitution. Isolation is enforced at the OS level (loopback + bubblewrap sandbox network namespace).
3. **Single key per proxy instance**: One secret per allowed domain. Multiple instances needed for per-consumer key isolation.
4. **Simpler SSRF model**: Upstream URL is fully determined by config (`allowed_domains[0]`), not by the HTTP CONNECT target. The sandbox cannot influence the upstream destination at all.

### Trade-off summary

| Dimension | Netclode | nix-secret-proxy |
|-----------|----------|-----------------|
| Transport | HTTPS MITM (CA cert in sandbox) | HTTP on loopback |
| Caller identity | SA token validation | None (OS isolation) |
| Per-caller key | Yes (pool) | No (one key per instance) |
| Setup complexity | High (CA cert, SA tokens) | Low (file path + port) |
| SSRF protection | TLS layer | Config-only allowlist |
| Non-NixOS portability | Higher (language-agnostic) | Requires config file |
| Key rotation | Runtime (if pool-aware) | Service restart |

The nix-secret-proxy design trade-off: simpler at the cost of no per-caller identity. Appropriate when the caller isolation guarantee comes from the OS (bwrap namespaces, separate systemd users) rather than cryptographic identity.

---

## 5. How nix-secret-proxy Is Consumed (neurosys context)

From `flake.nix`:
- `nix-secret-proxy` is a flake input (`path:/data/projects/nix-secret-proxy`)
- `nix-secret-proxy.nixosModules.default` is included in `commonModules` for both hosts
- The public repo includes the module but declares no proxy services (services defined in private overlay)
- Private overlay declares `services.secretProxy.services.dev` on the OVH host (service name: `secret-proxy-dev`, port 9091)
- The `bwrapArgs` computed attribute is spliced into bubblewrap invocations in `agent-compute.nix`
- Live test: `api-endpoints.bats` checks that port 9091 returns any HTTP status (proxy is responsive)
- Deploy health check: `scripts/deploy.sh` checks `secret-proxy-dev` service is active after OVH deploy

---

## 6. Key Findings for Plan Authors

### For 71-01 (architecture doc + usage guide)

1. **Attribution**: Credit Stanislas Polu at the top of the architecture doc. His post is the canonical external reference. The neurosys implementation is a simpler, NixOS-native variant.
2. **Trust model**: The proxy's security guarantee rests on OS-level isolation (loopback-only bind + bubblewrap namespaces), not cryptographic identity. This must be made explicit.
3. **Upstream control**: @decision(66-01) in proxy.rs — upstream host is always `allowed_domains[0]`, making SSRF-via-Host-header manipulation impossible. This is a key security property worth highlighting.
4. **Multi-secret support**: One proxy instance can serve multiple `[[secret]]` blocks for different domains. This is undocumented. E.g., both `api.anthropic.com` and `api.openai.com` could be served by one binary with different header injection.
5. **Docker guide**: Must explicitly address the 127.0.0.1 limitation. The recommended workaround until Phase 72 is `--network host`.
6. **TOML config reference**: Must document all 4 fields at top level (`port`, `placeholder`) plus `[[secret]]` array fields (`header`, `name`, `file`, `allowed_domains`).

### For 71-02 (issue catalogue)

Severity classification:

| Issue | Severity | Notes |
|-------|----------|-------|
| Streaming/SSE | OK — not an issue | Fully streaming; no buffering |
| Bind address (127.0.0.1 hardcoded) | Blocking for Docker | Fix planned in Phase 72 |
| Body size limit (2 MB axum default) | Degraded | Blocks multimodal API calls |
| Upstream timeout (none) | Degraded | Robustness issue |
| Health endpoint (absent) | Informational | Operational convenience |
| TLS verification | OK — not an issue | System roots, verified |
| Header forwarding (auth strip) | Informational | By design; document |
| Error response format (plain text 502) | Degraded | SDK parsing confusion |
| Graceful shutdown (none) | Degraded for streaming | Truncated SSE on restart |
| Rate limiting (shared key) | Informational | By design |
| Audit trail (partial) | Informational | Timestamps only |
| Proxy chaining | Informational | reqwest honors env vars |
| Docker networking | Blocking for Docker | See bind address above |
| IPv6 | Informational | Untested |
| SDK key format (placeholder validation) | Blocking (SDK-dependent) | Document workaround |
| Authorization strip for non-x-api-key APIs | Informational | By design; document |

---

## RESEARCH COMPLETE
