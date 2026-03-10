# Phase 72 Research — Secret Proxy Issue Resolution & Hardening

## Source files reviewed

- `/data/projects/nix-secret-proxy/src/main.rs` (95 lines)
- `/data/projects/nix-secret-proxy/src/proxy.rs` (203 lines)
- `/data/projects/nix-secret-proxy/src/config.rs` (23 lines)
- `/data/projects/nix-secret-proxy/module.nix` (165 lines)
- `/data/projects/nix-secret-proxy/Cargo.toml`
- `/data/projects/nix-secret-proxy/Cargo.lock`
- `/data/projects/nix-secret-proxy/docs/known-issues.md`
- `/data/projects/nix-secret-proxy/.planning/ROADMAP.md` (Phase 72 section)
- axum-0.8.8 source (serve/mod.rs, extract/mod.rs, axum-core-0.5.6 default_body_limit.rs)

---

## 1. Current code state for each fix

### BLOCK-01: Bind address hardcoded to 127.0.0.1

**Exact location:** `src/main.rs`, line 90:
```rust
let addr = SocketAddr::from(([127, 0, 0, 1], config.port));
```

`[127, 0, 0, 1]` is an inline IPv4 literal. There is no intermediate variable. The config struct (`src/config.rs`) has no `bind` field — only `port`, `placeholder`, and `secret`.

The NixOS module description for `port` says "(127.0.0.1 only)" — this is now incorrect after the fix and must be updated. The `bwrapArgs` config value (`http://127.0.0.1:<port>`) is generated from the port only; it does not need to change (loopback is always correct for the NixOS deployment case).

### BLOCK-02: Placeholder format rejected by Anthropic SDK

**Exact location:** `module.nix`, line 44:
```nix
default = "sk-placeholder-${name}";
```

The Anthropic SDK validates API keys client-side; the key must have the prefix `sk-ant-api03-`. The current default `sk-placeholder-${name}` fails this check. The fix is purely a default value change — no logic change needed.

The `deployment-docker.md` doc already uses the correct format (`sk-ant-api03-placeholder`) in its example config, so it is ahead of the module. After fixing the module default, the docs remain consistent.

The known-issues.md entry currently says `Status: Document only` rather than `Fix planned`. This should be updated to `Fixed` after the module default is changed.

### DEG-01: No upstream timeout

**Exact location:** `src/main.rs`, line 86:
```rust
client: reqwest::Client::new(),
```

`reqwest::Client::new()` uses default settings. The `reqwest` dependency is declared in `Cargo.toml` as:
```toml
reqwest = { version = "0.12", features = ["stream"] }
```

`reqwest` 0.12.x exposes `ClientBuilder::timeout(Duration)`. This sets a total request timeout (from send to response completion). No additional feature flag is needed — timeout support is always compiled in.

The config struct needs a new `timeout_secs` field. The ROADMAP says "default 10 min for extended thinking" — this maps to `timeout_secs = 600` (u64).

The reqwest client is built once at startup and stored in `ProxyState`. The `ClientBuilder` API is:
```rust
reqwest::Client::builder()
    .timeout(Duration::from_secs(cfg.timeout_secs))
    .build()
    .expect("failed to build HTTP client")
```

### DEG-02: Axum 2MB body limit blocks large multimodal prompts

**CRITICAL FINDING: This issue as described in known-issues.md does NOT exist in the current implementation.**

The `DefaultBodyLimit` middleware in axum-core-0.5.6 applies only to `FromRequest` extractors that explicitly call `with_limited_body` or `into_limited_body` on the request. From `default_body_limit.rs`:
> "Note that if an extractor consumes the body directly with `Body::poll_frame`, or similar, the default limit is _not_ applied."

The proxy handler in `proxy.rs` does:
```rust
async fn proxy_handler(State(state): State<Arc<ProxyState>>, request: Request) -> Response {
    let (parts, body) = request.into_parts();
    // ...
    .body(reqwest::Body::wrap_stream(body.into_data_stream()))
```

`request.into_parts()` returns the raw `Body` without going through any `FromRequest` extractor. `body.into_data_stream()` consumes the body as a stream. The 2MB `DefaultBodyLimit` is never triggered because `Bytes::from_request` (or any limit-aware extractor) is never called.

The Phase 71 research document (`71-RESEARCH.md`) confirms this: "The proxy is fully streaming in both directions. It does NOT call `body::to_bytes` anywhere."

**Consequence:** No code change is needed for DEG-02. The fix is a documentation correction: update `known-issues.md` to change DEG-02 from "Fix planned (Phase 72)" to "Accepted / Not applicable" with an explanation that the handler bypasses the extractor-level limit. The ROADMAP's instruction to "raise Axum body limit to 100 MB" and "add `max_body_bytes` config field" is based on an incorrect premise. **The implementor should verify this empirically with a >2MB test request before closing DEG-02.** If confirmed not an issue, document it; if somehow it is an issue, add `DefaultBodyLimit::disable()` via `.layer()`.

**If a `max_body_bytes` config field is added anyway** (per the ROADMAP's "add configurable limit"), the correct approach would be to use `tower_http::limit::RequestBodyLimitLayer` (a global middleware that applies before the handler, regardless of how the body is consumed), not `DefaultBodyLimit`. `tower-http` is already a transitive dependency (version 0.6.8 in Cargo.lock) but is NOT in `Cargo.toml`'s `[dependencies]`. Adding it would require a new direct dependency.

The simplest action: document that DEG-02 is not applicable, add an empirical test case in 72-03 that sends a 5MB body and confirms it passes through.

### DEG-03: Plain-text 502 on upstream failure

**Exact location:** `src/proxy.rs`, line 144:
```rust
return simple_response(StatusCode::BAD_GATEWAY, "Upstream request failed\n");
```

`simple_response` is defined at line 187:
```rust
fn simple_response(status: StatusCode, body: &'static str) -> Response {
    let mut response = Response::new(Body::from(body));
    *response.status_mut() = status;
    response
}
```

No `Content-Type` header is set. The body is a bare static string.

`serde_json` is a transitive dependency (version 1.0.149 in Cargo.lock via reqwest/axum). It is NOT in `Cargo.toml`'s `[dependencies]`. Adding `serde_json = "1"` as a direct dependency is the right approach. The `format!` macro could also generate the JSON string without serde_json, but using serde_json is idiomatic and type-safe.

The Anthropic error format is:
```json
{"type":"error","error":{"type":"api_error","message":"Proxy upstream request failed"}}
```

The `simple_response` function cannot be reused as-is because it takes `&'static str`. Two approaches:
1. Add a separate `json_error_response(status, msg)` function that constructs the JSON body and sets `Content-Type: application/json`.
2. Generalize `simple_response` to accept `String` — but this changes the API for the existing callers (403 forbidden).

The cleanest approach: add a new `json_502(message: &str) -> Response` helper alongside `simple_response`. The other error paths (misconfiguration → 500, forbidden → 403) are client/config errors, not upstream failures, so returning plain text there is acceptable (they will never be seen by the Anthropic SDK in a correctly configured deployment). Only the 502 path needs JSON formatting.

Also note: there are two `return simple_response(StatusCode::INTERNAL_SERVER_ERROR, ...)` calls in `proxy_handler` (lines 77-80, 110-113) for misconfiguration errors. These could optionally also be JSON-formatted, but it is lower priority than the 502 path.

### DEG-04: No graceful shutdown

**Exact location:** `src/main.rs`, line 94:
```rust
axum::serve(listener, app).await.unwrap();
```

No signal handler. No graceful shutdown.

**Axum 0.8 API (confirmed from source):** `axum::serve()` returns a `Serve<L, M, S>` struct that implements `IntoFuture`. It has a `with_graceful_shutdown(signal: F)` method that takes a `Future<Output = ()>`. When the future resolves, axum stops accepting new connections and waits for all active connections/tasks to close before returning.

**Tokio signal API:** `tokio::signal::unix::signal(SignalKind::terminate())` creates an async stream that yields when SIGTERM arrives. `tokio::signal::ctrl_c()` waits for SIGINT. The `tokio` crate is already in `Cargo.toml` with `features = ["full"]`, which includes the `signal` feature. No new dependency needed.

The graceful shutdown future needs to handle both SIGTERM and SIGINT. Pattern:
```rust
async fn shutdown_signal() {
    let sigterm = tokio::signal::unix::signal(SignalKind::terminate())
        .expect("failed to install SIGTERM handler");
    tokio::select! {
        _ = sigterm.recv() => {},
        _ = tokio::signal::ctrl_c() => {},
    }
    tracing::info!("shutdown signal received, draining in-flight requests");
}
```

The ROADMAP mentions a `shutdown_timeout_secs` config field (default 30). However, axum's `with_graceful_shutdown` drains until all connections close — it has no built-in drain timeout. Implementing a timeout requires wrapping the drain with `tokio::time::timeout`. This adds complexity. The simplest correct implementation is:

1. Register the SIGTERM/SIGINT handler.
2. Chain it with `axum::serve(...).with_graceful_shutdown(shutdown_signal())`.
3. Do NOT add a `shutdown_timeout_secs` config field in phase 72 — it is not needed for correctness and adds implementation complexity. Document in known-issues if this becomes relevant.

The config.rs change needed: none (no new field for the minimal correct implementation).

---

## 2. Config struct changes summary

All new fields go into `src/config.rs` `Config` struct:

| Field | Type | Serde default | Config.rs change |
|-------|------|---------------|------------------|
| `bind` | `String` | `"127.0.0.1"` | `#[serde(default = "default_bind")]` |
| `timeout_secs` | `u64` | `600` | `#[serde(default = "default_timeout_secs")]` |

No other config fields are required for the fixes in scope. DEG-02 does not need `max_body_bytes` (the issue is not real). DEG-04 does not need `shutdown_timeout_secs` (drain is unbounded).

Serde default functions are idiomatic for TOML/serde — add private `fn default_bind() -> String { "127.0.0.1".to_string() }` and `fn default_timeout_secs() -> u64 { 600 }` in `config.rs`.

### How `bind` is used in main.rs

Replace line 90:
```rust
// Before:
let addr = SocketAddr::from(([127, 0, 0, 1], config.port));

// After:
let addr: SocketAddr = format!("{}:{}", config.bind, config.port)
    .parse()
    .unwrap_or_else(|err| {
        eprintln!("Invalid bind address '{}': {}", config.bind, err);
        std::process::exit(1);
    });
```

`SocketAddr::from_str` (via `.parse()`) handles both `127.0.0.1:9091` and `[::1]:9091` (IPv6). Combining `bind` and `port` via `format!` and then parsing is the correct approach rather than `SocketAddr::from(([...], port))`.

### NixOS module changes for `bind`

The `module.nix` `serviceOpts` currently has no `bind` option. After the config.rs change, no NixOS module change is strictly required (the default `127.0.0.1` will be used if `bind` is absent from the TOML). However, to expose the option to NixOS consumers:

```nix
bind = lib.mkOption {
  type = lib.types.str;
  default = "127.0.0.1";
  description = "Address to bind the proxy to. Use 0.0.0.0 for Docker bridge deployments.";
};
```

And in `mkToml`:
```nix
bind = "${svcCfg.bind}"
```

The `bwrapArgs` derivation (`http://127.0.0.1:<port>`) should remain hardcoded to loopback regardless of the `bind` setting — the NixOS deployment always reaches the proxy via loopback even when it binds to `0.0.0.0`. No change needed to `bwrapArgs`.

---

## 3. Cargo.toml additions needed

| Crate | Reason | Already in Cargo.lock? |
|-------|--------|----------------------|
| `serde_json` | DEG-03: JSON error response | Yes (transitive) |

Add to `[dependencies]`:
```toml
serde_json = "1"
```

No other new crates are needed:
- `tokio` already has `features = ["full"]` which includes `signal`.
- `tower-http` is transitive but not needed directly (DEG-02 is a non-issue).
- `axum`'s `DefaultBodyLimit` is already re-exported from `axum::extract` — no new import path needed.

---

## 4. Dependencies between fixes (build order)

The config struct changes (BLOCK-01, DEG-01) must be done first because main.rs changes depend on them. The correct order within 72-01:

1. **config.rs**: Add `bind: String` and `timeout_secs: u64` with serde defaults.
2. **main.rs BLOCK-01**: Replace hardcoded bind with `format!("{}", config.bind, config.port).parse()`.
3. **main.rs DEG-01**: Replace `reqwest::Client::new()` with `ClientBuilder::timeout(Duration::from_secs(config.timeout_secs)).build()`.
4. **main.rs DEG-04**: Add `shutdown_signal()` async fn; chain `axum::serve(...).with_graceful_shutdown(shutdown_signal())`.
5. **proxy.rs DEG-03**: Add `serde_json` import; add `json_502(message: &str) -> Response` helper; replace the 502 `simple_response` call.
6. **Cargo.toml**: Add `serde_json = "1"`.
7. **module.nix BLOCK-01**: Add `bind` option.
8. **module.nix BLOCK-02**: Change placeholder default.

DEG-02 requires only a documentation update in `known-issues.md` — no code change. This belongs in 72-02 (documentation plan).

All 8 steps above can go in a single 72-01 plan. They are independent enough to implement sequentially in one pass — none blocks another except the config.rs prerequisite for steps 2 and 3.

---

## 5. Integration test recommendations

### Framework choice

**Recommended: `axum::test_helpers::TestClient` (built-in) + a minimal mock upstream server.**

Axum 0.8's `src/test_helpers/` directory provides `TestClient` which can issue requests to a `Router` in-process without binding a real port. This is confirmed in the axum source at `axum-0.8.8/src/test_helpers/`.

However, for this proxy we need to test the full end-to-end flow including the upstream reqwest call. This requires a real TCP listener for the mock upstream. The standard approach is `tokio::net::TcpListener::bind("127.0.0.1:0")` in the test to get a random port, serve a simple response, and then configure the proxy to point at it.

**Alternative: `wiremock` or `httpmock`** — neither is in the cargo registry. Starting from scratch with `tokio`/`axum`/`reqwest` in `[dev-dependencies]` is simpler than adding a third-party mock crate.

**Recommended test structure:**
```
tests/
  proxy_integration.rs   — integration tests using real TCP
```

Use `#[tokio::test]` on each test, bind a mock upstream server with `axum` on a random port, start the proxy server on another random port, issue requests via `reqwest::Client`, assert responses.

### Required dev-dependencies

```toml
[dev-dependencies]
tokio = { version = "1", features = ["full"] }  # already in [dependencies]
reqwest = { version = "0.12", features = ["stream"] }  # already in [dependencies]
axum = "0.8"  # already in [dependencies]
```

No new crates needed for tests — all required crates are already in `[dependencies]`.

### Test cases (72-03)

| Test name | Purpose | Setup | Assert |
|-----------|---------|-------|--------|
| `test_placeholder_substitution` | Real key is injected, placeholder is stripped | Mock upstream echoes request headers; send request with `x-api-key: sk-ant-api03-placeholder` | Upstream receives `x-api-key: <real_key>`, NOT the placeholder |
| `test_host_allowlist_deny` | Unlisted host returns 403 | Proxy configured with `allowed_domains = ["api.anthropic.com"]`; send `Host: evil.com` | Response is 403 |
| `test_host_allowlist_allow` | Listed host passes through | Send `Host: api.anthropic.com` | Upstream receives request; response 200 |
| `test_streaming_sse_passthrough` | SSE body is not buffered | Mock upstream streams 10 SSE events; proxy forwards | Client receives all 10 events in order, no buffering delay |
| `test_large_body_passthrough` | 5MB body passes through | Mock upstream echoes body; send 5MB POST | Response body matches; no 413 |
| `test_structured_502` | Upstream unreachable returns JSON error | Point proxy at a closed port | Response is 502 with `Content-Type: application/json` and body `{"type":"error","error":{...}}` |
| `test_graceful_shutdown_drains` | In-flight request completes after SIGTERM | Start request to slow upstream; send shutdown signal; assert request completes | Request completes with valid response; server exits cleanly |
| `test_bind_0_0_0_0` | Configurable bind works | Bind to `0.0.0.0:<port>`; connect via `127.0.0.1:<port>` | Connection succeeds |
| `test_timeout_fires` | Upstream timeout triggers 502 | Mock upstream delays 5s; proxy `timeout_secs = 1` | Response is 502 within ~1s |
| `test_health_endpoint` | If added: health returns 200 | GET `/health` | 200 with `{"status":"ok"}` |

The graceful shutdown test is the hardest to write correctly in-process. The simplest approach: use `tokio::time::timeout` to assert the proxy exits within a bound after the shutdown signal is sent via a `tokio::sync::watch` channel or a one-shot channel. This is more complex than the other tests and should be a stretch goal for 72-03.

### Test file location

Rust convention is `tests/<name>.rs` for integration tests (not in `src/`). The proxy's `make_router` and `ProxyState` are defined in `proxy.rs` — `make_router` is `pub`, so it is accessible from integration tests. `ProxyState` and `LoadedSecret` are also `pub`. No refactoring of `pub` visibility is needed.

---

## 6. Plan boundary recommendation

The 3-plan split in the ROADMAP is correct and clean:

### 72-01: Implementation fixes (code changes only)

All changes to `src/config.rs`, `src/main.rs`, `src/proxy.rs`, `Cargo.toml`, and `module.nix`. Specifically:
- BLOCK-01: configurable bind in config.rs + main.rs + module.nix
- BLOCK-02: placeholder default in module.nix
- DEG-01: timeout_secs in config.rs + main.rs
- DEG-02: documentation-only correction (move to 72-02 if no code change needed, or add an empirical verification comment)
- DEG-03: serde_json in Cargo.toml + json_502 helper in proxy.rs
- DEG-04: shutdown_signal() in main.rs + with_graceful_shutdown

The ROADMAP also mentions a "health endpoint" (`GET /health` → 200 with `{"status":"ok"}`). This is NOT in the known-issues.md blocking/degraded lists (INFO-01, status: Accepted). The ROADMAP includes it as an implementation fix. Since INFO-01 says "Accepted", the health endpoint should be discussed — it is useful for Docker Compose `healthcheck:` tests and for 72-03. Adding it is low-risk (<10 lines) and makes the test suite cleaner. Recommend adding it in 72-01 with a note updating INFO-01 status in 72-02.

Additional items from ROADMAP not in known-issues.md:
- **Header injection validation** (strip whitespace, reject CRLF): already done in main.rs (`key.trim().to_string()`). CRLF in the key value would be caught by `HeaderValue::from_str` at runtime when building `forward_headers` (line 106-115 in proxy.rs). No additional validation needed — document this in 72-02.
- **Retry-after passthrough**: already handled. The only headers filtered from the response are `transfer-encoding` and `connection` (line 26 in proxy.rs). `retry-after` and `x-ratelimit-*` are passed through verbatim. No code change needed — document in 72-02.

### 72-02: Documentation updates

Update `known-issues.md`:
- BLOCK-01: change status to "Fixed (Phase 72)"
- BLOCK-02: change status to "Fixed (Phase 72)" (module default updated)
- DEG-01: change status to "Fixed (Phase 72)"
- DEG-02: change status to "Not applicable — handler bypasses extractor-level limit" with explanation
- DEG-03: change status to "Fixed (Phase 72)"
- DEG-04: change status to "Fixed (Phase 72)"
- INFO-01: update if health endpoint is added
- INFO-06: note that IPv6 is now possible by setting `bind = "::1"` or `bind = "::"`

Update `deployment-docker.md`:
- Replace `network_mode: host` workaround with the `bind = "0.0.0.0"` config approach now that BLOCK-01 is fixed
- Update limitation section header

Update `deployment-nixos.md` and `deployment-systemd.md` if they mention placeholder format.

Update README:
- Note Phase 72 hardening; link to known-issues for limitations not fixed

### 72-03: Integration test suite

Implement `tests/proxy_integration.rs` with the 7-9 test cases described above. Add `[dev-dependencies]` section to `Cargo.toml` if needed (likely empty since all deps are shared with `[dependencies]`). Update `flake.nix` checks to run `cargo test` (currently only runs `build`).

---

## 7. Additional findings

### DEG-02 verification note

The axum `DefaultBodyLimit` documentation says it applies to `FromRequest` extractors that call `with_limited_body`/`into_limited_body`. The proxy handler uses `request.into_parts()` which returns the raw body without going through any limit check. The Phase 71 researcher independently confirmed streaming works end-to-end. The 5MB body test in 72-03 should empirically confirm this. If the test fails with a 413, add `DefaultBodyLimit::disable()` as a router layer; if it passes, close DEG-02 as "Not applicable."

### Axum `with_graceful_shutdown` behavior (DEG-04)

Confirmed from `axum-0.8.8/src/serve/mod.rs`: `with_graceful_shutdown` stops the accept loop when the signal future resolves, then calls `conn.graceful_shutdown()` on each active connection, and waits for all `close_rx` clones to be dropped (i.e., all spawned connection tasks to finish). This is a true drain: the process will not exit until all in-flight SSE streams complete or the client disconnects. No additional shutdown timeout is needed for correctness (systemd's `TimeoutStopSec` provides the outer bound).

### tokio::signal on Linux

`tokio::signal::unix` requires `tokio` with `features = ["signal"]` or `["full"]`. The project already uses `features = ["full"]`, so this is available with zero config change.

### serde_json already in the lock file

`serde_json 1.0.149` is already in `Cargo.lock` (transitive via reqwest). Adding it to `Cargo.toml` `[dependencies]` will reuse the existing lock entry without version change.

### BLOCK-02 is "Document only" in known-issues.md but "Fix planned" in the issue title

The status says "Document only" but the title says BLOCKING. In Phase 72, the fix is to change the module default. This requires updating the `known-issues.md` status to "Fixed (Phase 72)" — the mismatch between title severity and status text should also be corrected in 72-02.

---

## RESEARCH COMPLETE
