# Phase 66 Research: Secret Placeholder Proxy Module

**Researched:** 2026-03-07
**Confidence:** HIGH
**Sources:** Official Anthropic docs, crates.io, existing Phase 22/33 implementation, gondolin/ironclaw project research, NixOS discourse

---

## Executive Summary

No existing tool solves this problem cleanly in NixOS. Gondolin (earendil-works) is the closest conceptual match but uses QEMU microvms and JavaScript — not bwrap/NixOS-native. IronClaw is a NEAR AI TEE runtime, irrelevant to bwrap. The existing Phase 22 Python proxy uses the correct architecture (ANTHROPIC_BASE_URL plain-HTTP approach), and the right generalization path is a Rust binary using `http-mitm-proxy` crate + a NixOS module wrapping it. Per-service ports are cleaner than shared routing for this use case. Headers-only injection via ANTHROPIC_BASE_URL is the right default; CONNECT/TLS is needed only for non-Anthropic secrets.

---

## Q1: Do Ironclaw, Gondolin, or Existing Tools Solve This?

### IronClaw (NEAR AI)
- A TEE-based (Trusted Execution Environment) Rust runtime for AI agents, deployed on NEAR AI Cloud
- Tools run in isolated WASM sandboxes (Wasmtime), credentials injected at the WASM boundary
- Tied to NEAR AI's proprietary ecosystem (session tokens, NEAR AI billing)
- Not NixOS-compatible, not bwrap-compatible — fundamentally different architecture
- **Verdict: NOT RELEVANT.** Entirely different deployment model; extracting its credential injection pattern would mean reimplementing everything from scratch

### Gondolin (earendil-works/gondolin)
- Closest conceptual match: "secret injection without guest exposure via placeholders"
- Architecture: QEMU microvms with JavaScript-implemented network stack and virtual filesystem
- The host controls egress: HTTP/TLS traffic goes through a JS-implemented proxy that does placeholder substitution before secrets reach allowed destinations
- Supports: domain allowlisting, request/response hooks, Authorization header injection
- **Key quote from their README:** "The strongest way to prevent exfiltration is: do not deliver the secret to the untrusted environment. Gondolin's placeholder substitution ensures the guest can reference a secret (to make legitimate calls) without being able to read it."
- **Verdict: NOT DIRECTLY ADOPTABLE.** It uses QEMU microvms + Node.js network stack, not Linux bwrap. But it confirms the placeholder substitution architecture is correct, and validates that domain allowlisting must happen at both request level and egress level simultaneously.

### Anthropic sandbox-runtime (@anthropic-ai/sandbox-runtime)
- npm package: uses bwrap on Linux to sandbox processes
- Has a built-in proxy for domain allowlisting
- Removes the network namespace entirely; routes traffic through Unix domain socket to host proxy
- Does NOT do secret injection — it's purely a domain filter/network control layer
- **Verdict: NOT SUFFICIENT.** Good for domain allowlisting, but doesn't handle secret injection. Also npm-based (not NixOS-native).

### mitmproxy (Python, mature)
- Mature, battle-tested TLS-terminating proxy; used by the Formal blog post pattern
- Can inject headers via addon scripts
- Not NixOS module-ready; would need a wrapper
- Heavy Python dependency; operator must write addon scripts manually
- **Verdict: VIABLE FALLBACK but NOT RECOMMENDED.** Adds Python runtime dependency; less composable than a Rust binary with a declarative NixOS module interface.

### Envoy Proxy (with credential_injector filter)
- Production-grade; Anthropic's secure deployment guide mentions it explicitly
- Has a `credential_injector` filter for adding auth headers
- Enormous binary, complex configuration, over-engineered for single-host bwrap use
- **Verdict: NOT RECOMMENDED.** Operator overhead vastly exceeds the value for single-host deployments.

### Phase 22 Python Proxy (existing)
- The current `modules/secret-proxy.nix` is single-service, single-secret, single-domain
- Uses ANTHROPIC_BASE_URL (plain HTTP from agent → proxy → HTTPS upstream)
- Python stdlib: no TLS MITM, simple header replacement, correct architecture
- **Verdict: CORRECT APPROACH. Generalize this pattern rather than replace it.**

### Conclusion
**Build it.** No existing tool is plug-and-play for the bwrap + NixOS + sops-nix use case with a declarative Nix interface. The implementation should generalize Phase 22 into a Rust binary + NixOS module.

---

## Q2: Rust Crates for MITM HTTPS Proxy with TLS Interception

### http-mitm-proxy (recommended)
- **Crate:** `http-mitm-proxy` v0.18.0 (hatoo/http-mitm-proxy)
- **What it does:** Full CONNECT tunnel + TLS MITM, signs certificates per-domain on the fly using rcgen
- **Dependencies:** hyper 1.0.1, tokio 1.44.1, tokio-rustls 0.26.1, rcgen 0.14.3, moka 0.12.8 (cert cache)
- **API:** Service-function closures for request/response modification — ergonomic for header injection
- **Certificate handling:** `Issuer` struct creates a root CA + generates per-domain certs; root CA exported as PEM for client trust
- **CONNECT flow:** Client sends `CONNECT api.anthropic.com:443` → proxy intercepts → generates `api.anthropic.com` cert signed by local CA → decrypts traffic → applies hooks → re-encrypts upstream
- **Verdict: BEST CHOICE** for the CONNECT tunnel + TLS termination use case

### hudsucker (alternative)
- Similar MITM architecture but less actively maintained
- Uses rcgen or OpenSSL for CA (multiple backend options)
- Less ergonomic API than http-mitm-proxy
- **Verdict: SECONDARY OPTION** if http-mitm-proxy proves problematic

### third_wheel
- Similar approach; less activity, smaller ecosystem
- **Verdict: NOT RECOMMENDED** over http-mitm-proxy

### For ANTHROPIC_BASE_URL (plain HTTP) approach
- Simple approach: `axum` or `hyper` server that receives plain HTTP, injects header, forwards via HTTPS to upstream
- No rcgen needed — no TLS interception on the incoming side
- This is exactly what Phase 22's Python does
- Can use `reqwest` for upstream forwarding
- **Verdict: Much simpler; sufficient for AI API use cases (see Q3)**

---

## Q3: Injection Mode — Headers-Only vs Body Rewriting

### AI API patterns (Anthropic, OpenAI)
All major AI APIs use header-based authentication exclusively:
- **Anthropic:** `x-api-key: <key>` header (NOT Authorization: Bearer — this was a Phase 22 lesson; `Bearer` returns 401)
- **OpenAI/Codex:** `Authorization: Bearer <key>` header
- **Google (Gemini):** `x-goog-api-key: <key>` header
- **Anthropic streaming:** SSE over HTTP/HTTPS — headers-only injection works perfectly with streaming
- **Request body:** Never contains credentials for standard API calls

**Finding: Headers-only injection is correct for all AI API use cases.** Body rewriting is only needed if injecting into URL query params (some older APIs) or webhook payloads — not relevant here.

### Injection Strategy Decision
**Inject by replacing placeholder in headers before forwarding.** Pattern:
1. Client sends request with placeholder in `x-api-key: sk-placeholder-claw-swap-anthropic`
2. Proxy sees placeholder string, replaces with real key from secret file
3. Proxy forwards with real key; client never sees real key

Placeholder format: human-readable prefix + service name to distinguish per-service placeholders, e.g. `sk-placeholder-{service}-{secret-name}`.

Body rewriting is explicitly NOT needed. This keeps the proxy simpler and avoids parsing JSON for edge cases (streaming responses, binary uploads).

---

## Q4: HTTP_PROXY vs BASE_URL — What SDKs Actually Support

### ANTHROPIC_BASE_URL (strongly recommended for Anthropic)
- **Claude Code CLI:** Respects `ANTHROPIC_BASE_URL` — sends all sampling requests to that URL in plain HTTP
- **Anthropic Agent SDK:** Same; routes sampling to `ANTHROPIC_BASE_URL`
- **Benefit:** Proxy receives **plain HTTP** — no TLS interception needed, no CA certificate distribution
- **Limitation:** Only intercepts Anthropic API calls, not other HTTPS services
- **Official docs:** Explicitly endorsed by Anthropic's secure deployment guide as "Option 1"

### HTTP_PROXY / HTTPS_PROXY (for multi-service coverage)
- **Claude Code CLI:** Supports `HTTPS_PROXY` and `HTTP_PROXY` env vars (docs confirmed); routes all HTTP traffic through proxy
- **Known bug:** Version 1.0.93 switched to Undici's experimental EnvHttpProxyAgent which had issues reading env vars — but current versions work
- **Node.js fetch():** Does NOT respect HTTP_PROXY by default; in Node 24+ `NODE_USE_ENV_PROXY=1` enables it
- **Codex CLI:** Partially supported; there is an open issue (#4242) to consistently use proxy env vars across all HTTP clients. `OPENAI_BASE_URL` works for base URL override. HTTP_PROXY support inconsistent across internal reqwest clients.
- **When HTTPS_PROXY is used for HTTPS:** Proxy sees encrypted CONNECT tunnel — cannot inject headers WITHOUT TLS interception
- **When HTTPS_PROXY is used for HTTP:** Proxy sees plaintext — can inject headers easily

### Decision Matrix

| Scenario | Approach | TLS Interception Needed? |
|---|---|---|
| Anthropic API (claude-code, claw-swap) | ANTHROPIC_BASE_URL → local port | NO — plain HTTP to proxy |
| OpenAI API (codex) | OPENAI_BASE_URL → local port | NO — plain HTTP to proxy |
| Generic HTTPS service (GitHub, npm) | HTTPS_PROXY + TLS MITM | YES — needs CA cert distribution |
| Multiple AI providers per service | Per-secret BASE_URL injection via env | NO (but needs env var per secret) |

**Primary recommendation:** Use ANTHROPIC_BASE_URL / OPENAI_BASE_URL approach (plain-HTTP BASE_URL override), NOT the CONNECT-tunnel approach. Rationale:
- No CA certificate distribution complexity
- Proxy simpler to implement and audit
- Sufficient for 95% of sandboxed agent use cases (AI API calls)
- The Phase 22 Python proxy already proved this works

**Secondary recommendation:** Expose a CONNECT-tunnel+TLS-MITM mode (using http-mitm-proxy crate) as an optional feature for users who need to intercept arbitrary HTTPS, with explicit documentation that this requires CA trust distribution.

**For this phase:** Implement the BASE_URL approach first. The CONNECT/TLS path can be added later.

---

## Q5: CA Trust Inside bwrap Sandboxes

This question only matters for the CONNECT/TLS-MITM mode. For the BASE_URL plain-HTTP approach, there is no CA certificate to distribute.

If/when TLS MITM is needed:

### Node.js (Claude Code, most AI CLIs)
- `NODE_EXTRA_CA_CERTS=/path/to/ca.pem` — extends the default CA store, not replaces it
- Works with `--ro-bind /path/to/ca.pem /path/to/ca.pem --setenv NODE_EXTRA_CA_CERTS /path/to/ca.pem` inside bwrap
- CA file generated by the module at activation time, stored at `/run/secret-proxy/ca.pem` (or similar tmpfs path)
- Bind-mount the CA file into the bwrap sandbox as read-only

### Go programs (some agent tooling)
- Go uses the system CA store; requires either:
  - Adding the cert to `/etc/ssl/certs/` (not sandbox-friendly), OR
  - `SSL_CERT_FILE` env var pointing to a combined CA bundle
- sandbox-runtime docs note this requires `enableWeakerNetworkIsolation` in some cases

### Python
- `REQUESTS_CA_BUNDLE` and `SSL_CERT_FILE` env vars
- Or `certifi` package location override

### Universal bwrap pattern
```bash
bwrap \
  --ro-bind /run/secret-proxy/ca.pem /run/secret-proxy/ca.pem \
  --setenv NODE_EXTRA_CA_CERTS /run/secret-proxy/ca.pem \
  --setenv SSL_CERT_FILE /run/secret-proxy/ca.pem \
  ...
```

The NixOS module should:
1. Generate the CA certificate at service startup (rcgen-based, written to `/run/secret-proxy/ca.pem`)
2. Provide a NixOS option `secretProxy.bwrapCaArgs` that returns the pre-built list of bwrap args for CA trust
3. Let users compose these args into their existing bwrap invocations

**For the BASE_URL approach (primary):** CA distribution is a non-issue. Skip this complexity in the initial implementation.

---

## Q6: Per-Service Port vs Shared Proxy with Routing

### Per-Service Port (recommended)
- Each service gets its own proxy instance on its own port (e.g., claw-swap on 9091, automaton on 9092)
- Service sets `ANTHROPIC_BASE_URL=http://127.0.0.1:9091`
- Each proxy instance only knows about its own secrets — blast radius is contained
- Simple implementation: one systemd service per secret-proxy entry in the attrset
- Simple port allocation: module assigns ports from a base port + index, or user specifies explicitly

**Security benefit:** If one service's proxy is compromised, it only has access to that service's secrets. A shared proxy has all secrets in memory simultaneously.

### Shared Proxy with Routing (simpler operationally, less secure)
- Single proxy process handles all services, routing based on placeholder prefix
- All secrets decrypted into one process
- One port, one systemd service, one user

### Decision: Per-Service Ports
Per-service is cleaner security-wise and matches the declared per-service structure (`services.secretProxy.services.<name>`). Operationally, N systemd services are manageable with a NixOS module generating them. Port conflicts are caught at eval time via assertions.

**Port allocation pattern:**
- User specifies `port` in each service config (required, explicit — avoids magic auto-assignment)
- Assert no conflicts at eval time (same pattern as `internalOnlyPorts` in networking.nix)
- Ports added to `internalOnlyPorts` automatically by the module

---

## Q7: NixOS Pattern for Secret File Injection (EnvironmentFile vs LoadCredential)

### Option A: EnvironmentFile (current Phase 22 pattern)
```nix
systemd.services.secret-proxy-claw-swap = {
  serviceConfig.EnvironmentFile = config.sops.templates."secret-proxy-claw-swap-env".path;
};
```
- sops renders the template file (owned by the service user)
- systemd reads it as root, passes to service as env vars
- **Established pattern in this codebase** (Phase 22 already uses it)
- Works with sops-nix templates: `REAL_KEY=${config.sops.placeholder."anthropic-api-key"}`
- Service reads secrets via `std::env::var("REAL_KEY")`

### Option B: LoadCredential (systemd credentials facility)
```nix
systemd.services.secret-proxy-claw-swap = {
  serviceConfig.LoadCredential = "anthropic-api-key:${config.sops.secrets."anthropic-api-key".path}";
};
```
- Secret available at `/run/credentials/secret-proxy-claw-swap.service/anthropic-api-key`
- Service reads the file directly — not an env var
- Better security model: secret file not in process environment
- DynamicUser compatible (systemd handles permissions automatically)
- Growing NixOS adoption: nextcloud module recently switched to LoadCredential

### Option C: Direct secret file path (backend-agnostic)
```nix
# Module option accepts a file path
services.secretProxy.services.claw-swap.secrets.anthropic-api-key = {
  secretFile = config.sops.secrets."anthropic-api-key".path;
  allowedDomains = [ "api.anthropic.com" ];
};
```
- Module generates `ExecStart = "secret-proxy --secret anthropic-api-key:${secretFile} ..."`
- Proxy reads the file directly at startup
- Most backend-agnostic: works with sops-nix, agenix, or any mechanism that puts secrets in files

### Recommendation: Option C (file path) as the module interface
The phase decision says "purely backend-agnostic: module takes file paths for secrets." Option C is correct. Internally, the proxy binary reads the file at startup and holds the value in memory. The file path approach is the most standard NixOS pattern for backend-agnostic secret injection.

For the generated systemd service:
- Pass file paths as CLI args to the Rust proxy binary
- Use `EnvironmentFile` for the service's own credentials (none needed if secrets are file-path-based)
- The proxy binary opens each secret file, reads the key, caches in memory
- `Restart=on-failure` handles secret rotation (sops-nix triggers service restart on secret change via `restartUnits`)

---

## Implementation Architecture (Synthesized)

### Rust Binary Design
```
secret-proxy --port 9091 \
  --secret "x-api-key:anthropic-api-key:/run/secrets/anthropic-api-key:api.anthropic.com" \
  --placeholder "sk-placeholder-claw-swap"
```

Alternatively, TOML config file generated by the module:
```toml
port = 9091
placeholder = "sk-placeholder-claw-swap"

[[secret]]
header = "x-api-key"
name = "anthropic-api-key"
file = "/run/secrets/anthropic-api-key"
allowed_domains = ["api.anthropic.com"]
```

**Request handling (BASE_URL plain-HTTP mode):**
1. Receive plain HTTP POST/GET from agent
2. Check `Host` header or request path against allowed_domains for the matched secret
3. If allowed: replace placeholder in `x-api-key` header with real key from file
4. Forward via HTTPS to upstream (reqwest with full TLS validation)
5. Stream response back

**Domain allowlisting enforcement:**
- Check `Host` header value
- For CONNECT mode (future): also validate TLS SNI from ClientHello
- Exact match only (per user decision) — no wildcards
- Reject with 403 if domain not in allowlist, log the attempt

**Crate choices:**
- `axum` or `hyper` for the proxy server (incoming plain-HTTP)
- `reqwest` for upstream forwarding (handles HTTPS correctly, streaming)
- `tokio` for async runtime
- `serde` + `toml` for config file parsing
- `http-mitm-proxy` + `rcgen` if/when TLS MITM mode is added

### NixOS Module Schema
```nix
services.secretProxy.services.<name> = {
  port = <int>;  # required, no magic auto-assignment
  placeholder = <string> | null;  # auto-generated if null: "sk-placeholder-<name>"
  secrets.<secretName> = {
    headerName = "x-api-key";  # which request header to inject into
    secretFile = <path>;  # e.g. config.sops.secrets."anthropic-api-key".path
    allowedDomains = [ "api.anthropic.com" ];  # exact match, required
  };
  environmentVars = {  # set in the sandboxed agent's env
    ANTHROPIC_BASE_URL = "http://127.0.0.1:${toString port}";
    # OR for OpenAI:
    # OPENAI_BASE_URL = "http://127.0.0.1:${toString port}";
  };
};
```

The module generates:
1. A systemd service `secret-proxy-<name>` with full hardening (copy from Phase 22 pattern)
2. A dedicated system user `secret-proxy-<name>` (or shared `secret-proxy` group)
3. An assertion adding `port` to `internalOnlyPorts` in networking.nix
4. A NixOS option output: `config.services.secretProxy.services.<name>.bwrapArgs` — a list of `--setenv` args for the sandboxed process to use (e.g., `["--setenv" "ANTHROPIC_BASE_URL" "http://127.0.0.1:9091"]`)

### Migration from Phase 22
The existing `modules/secret-proxy.nix` (hardcoded for Anthropic/claw-swap) gets replaced by:
```nix
services.secretProxy.services.claw-swap = {
  port = 9091;
  secrets.anthropic-api-key = {
    headerName = "x-api-key";
    secretFile = config.sops.secrets."anthropic-api-key".path;
    allowedDomains = [ "api.anthropic.com" ];
  };
};
```

---

## Key Protocol Findings (for Planner)

### Anthropic API facts
- Auth header: `x-api-key: <key>` (NOT `Authorization: Bearer`) — confirmed in Phase 22
- Streaming: SSE over HTTP, works fine with plain-HTTP proxy approach
- ANTHROPIC_BASE_URL is officially supported and endorsed by Anthropic for proxy use

### OpenAI/Codex facts
- Auth header: `Authorization: Bearer <key>`
- `OPENAI_BASE_URL` env var supported in codex for base URL override
- HTTP_PROXY support in codex is inconsistent (open issue); BASE_URL approach is more reliable

### Codex proxy note
- Codex issue #6060 (open): support configuring outbound HTTP proxy via config.toml — not yet implemented
- Codex issue #4242 (open): use proxy env vars across all HTTP clients
- This means for codex, `OPENAI_BASE_URL` is the reliable path; `HTTP_PROXY` may not work

### Domain bypass vectors to defend against
- **Host header spoofing:** Agent can set `Host: api.anthropic.com` while connecting to a different server — mitigated by the BASE_URL approach (proxy controls the upstream URL, not the agent)
- **SNI mismatch (for CONNECT mode):** Agent could send SNI for allowed domain but connect to different IP — must validate both SNI and URL in CONNECT mode; not an issue in BASE_URL mode
- **HTTP/2 ALPN bypasses:** Not a concern in BASE_URL plain-HTTP mode; proxy speaks HTTP/1.1

### Why BASE_URL approach is more secure than HTTPS_PROXY
In the BASE_URL approach:
- The proxy controls the upstream destination — agent cannot choose where requests go
- Agent can only make requests to what the proxy decides to forward (hardcoded per secret)
- No way for agent to bypass by manipulating Host headers — the proxy ignores them

In the HTTPS_PROXY approach:
- Agent specifies CONNECT destination — proxy must validate it matches allowlist
- More attack surface (SNI mismatch, domain fronting attacks)
- Still correct if implemented carefully, but unnecessary complexity for AI API use case

---

## Gondolin's Key Insight (adopt this)

Gondolin separates concerns cleanly: "do not deliver the secret to the untrusted environment." Their placeholder substitution architecture is:

1. Secret stays on host only
2. Agent environment contains only a placeholder string
3. Proxy holds the real key in memory
4. Proxy substitutes placeholder → real key only for allowed destinations
5. Even if agent is compromised and exfiltrates the placeholder, the placeholder is useless outside the proxy's trust boundary

This is exactly Phase 22's pattern. The Phase 66 module should make this pattern first-class.

**One Gondolin idea worth adopting:** The placeholder string format should be designed to look like a real API key (same prefix format, similar length) so it doesn't cause SDK validation errors. E.g., for Anthropic: `sk-ant-placeholder-xxxxxxxxxxxxxxxx` rather than just `placeholder`. This avoids SDK-level key format validation rejecting the placeholder before the request reaches the proxy.

---

## Existing Tools Not Worth Pursuing

- **LiteLLM:** LLM gateway, does credential injection but too heavyweight (full Python service, many dependencies)
- **Squid:** Old caching proxy, complex config, no modern NixOS module support
- **Formal:** Commercial product using mitmproxy addons; not open-source for self-hosting
- **proxychains:** Network-level redirect tool; doesn't do credential injection
- **gVisor/Firecracker:** VM isolation; useful but orthogonal to this phase

---

## Risks and Mitigations

| Risk | Mitigation |
|---|---|
| Agent sends request to wrong domain (exfiltration attempt) | 403 returned, logged; domain never receives the real key |
| Placeholder format rejected by SDK validation | Design placeholder to match real key format (e.g., `sk-ant-placeholder-...`) |
| Secret file readable by agent via filesystem | sops-nix secret file owned by proxy service user only; agent not in that group |
| Proxy process crash leaks real key | systemd Restart=on-failure; MemoryDenyWriteExecute where possible; ProtectSystem strict |
| Multiple requests with different Host headers to bypass domain check | BASE_URL mode: proxy ignores Host header; it hardcodes the upstream destination |
| Port collision between proxy services | Eval-time assertion (same pattern as internalOnlyPorts) |
| Hot-path latency from extra hop | Localhost TCP roundtrip ~0.1ms; acceptable for API calls |

---

## Summary Recommendations

1. **Build it** (existing tools don't cover this use case)
2. **BASE_URL plain-HTTP approach** (not CONNECT/TLS) — simpler, more secure, Anthropic-endorsed
3. **http-mitm-proxy crate** available if TLS MITM needed later; not needed for MVP
4. **Headers-only injection** — all AI APIs use header-based auth
5. **Per-service ports** — better blast radius containment than shared proxy
6. **File path interface** for secrets — backend-agnostic, NixOS-idiomatic
7. **Placeholder format** should mimic real key format to avoid SDK validation failures
8. **Keep the Rust binary simple**: axum + reqwest; no TLS interception in MVP
9. **NixOS module**: generates per-service systemd units + provides bwrapArgs output option
10. **Migrate Phase 22** as the first consumer — validates the abstraction immediately
