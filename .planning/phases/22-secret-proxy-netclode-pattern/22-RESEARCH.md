# Phase 22: Secret Proxy (Netclode Pattern) — Research

**Researched:** 2026-02-24
**Domain:** HTTP proxy, TLS interception, secret injection, bubblewrap networking, NixOS systemd service
**Confidence:** HIGH overall; MEDIUM on Codex proxy support (open upstream issue); MEDIUM on MITM vs CONNECT trade-off (needs user decision)

---

## Summary

The goal is a two-tier proxy where real API keys never enter agent sandboxes. The sandbox sees `ANTHROPIC_API_KEY=PLACEHOLDER` and routes all API traffic through an HTTP proxy running on the host. The proxy holds the real keys, validates the request is going to an allowed upstream host, injects the real key into the HTTP header, and forwards the request.

The core implementation challenge is **HTTPS**: Claude Code and Codex send their API calls over HTTPS. The proxy must either (a) perform MITM TLS interception to rewrite `Authorization` headers, or (b) use a different secret-injection channel that works without TLS termination.

This research covers: the current agent-spawn setup, reference implementations (Netclode, Fly Tokenizer, Matchlock, Claude srt), the HTTPS problem and its two solutions, bubblewrap network bridging, agent proxy support, and the minimal viable design.

---

## 1. Current Agent-Spawn Setup (What Phase 22 Replaces)

From `modules/agent-compute.nix` (the authoritative current implementation):

**Current flow** (lines 104–199):
1. `agent-spawn` runs **outside** the sandbox, reads sops secrets from `/run/secrets/`:
   ```bash
   ANTHROPIC_KEY="$(cat /run/secrets/anthropic-api-key 2>/dev/null || true)"
   OPENAI_KEY="$(cat /run/secrets/openai-api-key 2>/dev/null || true)"
   GITHUB_TOKEN="$(cat /run/secrets/github-pat 2>/dev/null || true)"
   ```
2. Keys are injected directly as env vars into the sandbox via `bwrap --setenv`:
   ```bash
   BWRAP_ARGS+=( --setenv ANTHROPIC_API_KEY "$ANTHROPIC_KEY" )
   BWRAP_ARGS+=( --setenv OPENAI_API_KEY "$OPENAI_KEY" )
   ```
3. The sandbox process inherits real API keys in its environment.

**The problem Phase 22 solves:** A compromised agent process can `env | grep ANTHROPIC` and exfiltrate the real key. The key exists in the process environment for the entire agent session.

**What Phase 22 changes:** Instead of step 2, inject `ANTHROPIC_API_KEY=PLACEHOLDER` and `HTTP_PROXY=http://localhost:<port>` (or a Unix socket path). The real key stays in the proxy process outside the sandbox.

**Current network policy:** The sandbox does NOT use `--unshare-net`. Phase 11 decision locked: "Unrestricted internet access, no network namespace isolation." This is relevant — see Section 5.

---

## 2. Reference Implementations

### 2.1 Netclode (angristan/netclode)

**Architecture:** Kubernetes-based self-hosted cloud agent runner. Uses Kata Containers (microVM) with a separate `secret-proxy` service written in Go. The agent never receives real credentials.

**Secret injection mechanism:** HTTPS MITM. The `secret-proxy` terminates TLS on behalf of the sandbox agent, modifies `Authorization` headers to replace `PLACEHOLDER` with the real key, then establishes a new TLS connection to the upstream API. A custom CA certificate is mounted in the sandbox so the agent trusts the proxy's generated certificates.

**Per-session allowlisting:** Validates requests against session type (which SDK is active) + target hostname. Claude agents can only reach `api.anthropic.com`; Codex agents only `api.openai.com`.

**Agent identity:** Kubernetes ServiceAccount tokens. The sandbox's local `auth-proxy` adds the pod's SA token to all requests. The `secret-proxy` validates this token with the k8s API server.

**Reflection attack prevention:** The allowlist is the defense. Only requests to approved hosts get key injection; requests to arbitrary hosts pass through with the placeholder. The placeholder never leaks to upstream — if an attacker redirects an API call to `evil.com`, the proxy sees the destination is not on the allowlist and injects nothing (placeholder reaches `evil.com`, not the real key).

**Applicability to this project:** The MITM pattern is directly applicable. The k8s identity mechanism is not — we need a simpler identity approach for a single-host setup.

### 2.2 Fly Tokenizer (superfly/tokenizer)

**Architecture:** Stateless Go HTTP proxy. Clients encrypt secrets to the proxy's Curve25519 public key and include the encrypted payload in a `Proxy-Tokenizer` header. The proxy decrypts, validates, and injects.

**Key difference from Netclode:** No MITM. The Fly Tokenizer assumes a VPN (Fly's WireGuard) protects client-to-proxy traffic, so the proxy operates on plaintext HTTP from the client. The proxy then forwards to upstream over HTTPS. The client speaks **plain HTTP** to the proxy (relying on VPN for transport security), and the proxy handles TLS to upstream.

**Secret injection:** The `inject_processor` takes the decrypted secret and injects it as `Authorization: Bearer <real_key>` in the outbound request to the upstream API.

**Allowed hosts:** Secrets carry an `allowed_hosts` list. The proxy refuses to inject if the target host doesn't match. This prevents a compromised client from extracting the encrypted secret blob and replaying it to an attacker-controlled endpoint.

**Reflection attack:** The allowed_hosts list in the encrypted secret payload is the mitigation. Since the secret is encrypted with the proxy's public key, the client cannot forge a different allowed_hosts list.

**Client identity:** Via `bearer_auth` digest in the encrypted secret — the proxy verifies a client-supplied token matches the digest before injecting. Not a strong identity mechanism (client could share tokens).

**Applicability:** The plaintext-HTTP-to-proxy model requires the client not to wrap the call in HTTPS before the proxy sees it. This is the key insight for our implementation: if the agent SDK is configured with `HTTPS_PROXY`, it sends the request to the proxy over HTTP (CONNECT for HTTPS targets or plain HTTP for CONNECT). The Tokenizer pattern uses this. However, for HTTPS API calls, the proxy would use CONNECT tunneling — which means no header modification unless MITM is applied.

**NixOS module:** None exists. Go binary only, must be packaged.

### 2.3 Claude Code's Sandbox Runtime (srt) — Most Relevant

**Architecture:** Uses `bwrap --unshare-net` to fully isolate the sandbox network namespace. External access is mediated by two proxies running on the host:
- HTTP/HTTPS proxy on `localhost:44889`
- SOCKS5 proxy on `127.0.0.1:44311`

**Bridging mechanism:** `socat` creates Unix domain socket bridges between the isolated network namespace and the host proxies:
```bash
socat UNIX-LISTEN:/tmp/claude-http-[ID].sock,fork,reuseaddr TCP:localhost:44889,...
socat UNIX-LISTEN:/tmp/claude-socks-[ID].sock,fork,reuseaddr TCP:localhost:44311,...
```
The Unix sockets are bind-mounted into the sandbox. The sandbox sees `HTTP_PROXY=localhost:PORT` (actually via the Unix socket path).

**Filtering:** The host proxy enforces domain allowlisting. Requests to non-allowlisted domains are blocked with a clear error.

**HTTPS handling:** The srt documentation mentions MITM support is possible via a configuration option related to custom CAs, but the default appears to be CONNECT tunneling for HTTPS.

**Key insight for this project:** The current `agent-spawn` does NOT use `--unshare-net`. The phase description says the proxy "integrates with sandbox HTTP_PROXY." This can work WITHOUT network namespace isolation — the agent sets `HTTP_PROXY=http://localhost:PORT`, and all HTTP/HTTPS traffic routes to the proxy. The proxy runs on localhost outside the sandbox. Since bwrap shares the host network namespace (no `--unshare-net`), `localhost` inside the sandbox IS the host's localhost. No socat bridging needed unless network isolation is added simultaneously.

### 2.4 Matchlock

Written in Go. Uses transparent MITM proxy with nftables DNAT rules on ports 80/443 for fully transparent interception (no proxy env var needed). More complex than needed for our use case. The DNAT approach requires root and is harder to make per-session.

---

## 3. The HTTPS Problem: Two Approaches

This is the core architectural decision for Phase 22.

### Approach A: MITM Proxy (like Netclode)

**How it works:**
1. Proxy generates a local CA and self-signed certificate.
2. CA cert is added to the sandbox's trusted CA store via `NODE_EXTRA_CA_CERTS=/path/to/ca.pem` env var.
3. Agent connects to `HTTPS_PROXY=http://localhost:PORT`.
4. When agent sends `CONNECT api.anthropic.com:443`, the proxy performs TLS termination — generates a cert for `api.anthropic.com` signed by the local CA, terminates the TLS from the agent, reads the plaintext HTTP request, rewrites the `Authorization: Bearer PLACEHOLDER` header to the real key, then establishes a new TLS connection to the real `api.anthropic.com`.
5. Agent sees a valid TLS cert (trusted because of the injected CA), proxy sees and modifies the request.

**Pros:**
- Can inspect and modify any HTTPS request header.
- True secret never in sandbox env.
- Allows body inspection if needed (we explicitly don't want this — header-only injection).
- Allowlisting works at the HTTP header level, not just TCP host level.

**Cons:**
- Requires CA generation and injection. Claude Code (Bun runtime) needs `NODE_EXTRA_CA_CERTS` to trust the custom CA, and also `NODE_USE_SYSTEM_CA=1` if relying on system store.
- Bun CA handling is reported buggy (issues #4053, #25977, #25084) — WebFetch tool may not inherit the patched CA store.
- MITM is a significant trust boundary change. Even though the CA is generated locally and never leaves the machine, it's still MITM infrastructure.
- Every session needs fresh proxy certs (or a stable long-lived CA).

**Claude Code CA support:** `NODE_EXTRA_CA_CERTS=/path/to/ca.pem` is the documented way. Known Bun issues with CA cert loading in some tool contexts. This is a **medium risk** — may require workarounds for WebFetch-based tools.

### Approach B: CONNECT Tunnel + Plaintext Injection (like Fly Tokenizer)

**How it works:**
1. Agent sends `ANTHROPIC_API_KEY=PLACEHOLDER` (a sentinel value, not a valid key).
2. Agent is configured with `HTTP_PROXY=http://localhost:PORT`.
3. For API calls to `https://api.anthropic.com`, the agent sends `CONNECT api.anthropic.com:443` to the proxy.
4. The proxy can see the target host before tunneling starts. It checks the allowlist.
5. BUT: once the CONNECT tunnel is established, all subsequent traffic is TLS-encrypted end-to-end between agent and `api.anthropic.com`. The proxy cannot see or modify HTTP headers.
6. The agent's SDK sends `Authorization: Bearer PLACEHOLDER` inside the encrypted tunnel — unreachable by the proxy.

**Problem:** CONNECT tunneling gives no opportunity to replace headers. This approach does NOT work for the Authorization header injection goal.

**Possible workaround (Tokenizer pattern):** Configure the agent SDK to send requests over plain HTTP (no HTTPS) to the proxy. The proxy then handles TLS to the upstream. But Claude Code and Codex always use HTTPS for their API clients (enforced by the SDK). You cannot configure them to speak plain HTTP to `api.anthropic.com`.

**Alternative workaround — placeholder in proxy-level token:** Configure the proxy to recognize `PLACEHOLDER` in the `Proxy-Authorization` header or a custom `X-Secret-Token` header sent by the agent. But the agent SDKs send `Authorization: Bearer <api_key>` in the TLS tunnel body, not in the CONNECT request headers. The proxy cannot inject here without MITM.

**Conclusion:** CONNECT tunneling alone cannot satisfy the success criteria. MITM is required for header replacement.

### Recommendation: MITM Proxy (Approach A)

This is what Netclode, Matchlock, and the Claude srt's `enableWeakerNetworkIsolation` mode all use. It is the standard pattern for this use case.

**Key mitigations for CA risks:**
- Generate CA once at service startup, store private key in `/run/secrets/` (sops-nix, inaccessible to sandbox).
- CA is never leaked to the sandbox — only the CA cert (public) is injected via env var.
- The CA cert injected into the sandbox is only trusted by agent processes (targeted via env var, not system-wide).
- CA is local to the VPS — does not apply outside the machine.
- The CA private key lives in the proxy process's memory/sops secret, invisible to the sandbox.

---

## 4. Agent Proxy Support Status

### Claude Code

**Supported proxy env vars:** `HTTPS_PROXY`, `HTTP_PROXY`, `NO_PROXY` (official docs).
**SOCKS:** Not supported.
**Custom CA:** `NODE_EXTRA_CA_CERTS=/path/to/ca.pem` (documented). Also `NODE_USE_SYSTEM_CA=1` for Bun system store.
**Known issues:**
- Bun runtime (which Claude Code uses) has inconsistent CA cert loading — some contexts (WebFetch tool) may not inherit `NODE_EXTRA_CA_CERTS` in all tool invocations. See issues #4053, #25977.
- `HTTPS_PROXY` set via env var works; setting it in `settings.json` has inconsistent behavior for API POST requests (issue #11660).

**Verdict:** Claude Code supports `HTTPS_PROXY` and custom CAs. There are Bun-specific edge cases with CA loading in WebFetch. For Anthropic API calls (which are the primary target), the `Authorization` header injection path should work. WebFetch tool (used for browsing external sites) is a secondary concern — if it doesn't trust the proxy CA, it may fail on HTTPS sites. This is acceptable risk for the initial implementation (only `api.anthropic.com` needs to be in the MITM path; other hosts can be tunneled transparently or given NO_PROXY treatment).

### Codex CLI

**Supported proxy env vars:** Open GitHub issues (#4242, #6060) indicate proxy support is incomplete as of mid-2025. Codex may not fully honor `HTTP_PROXY`/`HTTPS_PROXY` across all HTTP clients.
**Custom CA:** Unknown/untested.

**Verdict:** Codex proxy support is uncertain. Phase 22 should target Claude Code first as the primary use case. Codex integration may require a workaround or be deferred pending upstream improvements. **This is the primary risk item for the phase.**

---

## 5. Bubblewrap Network Bridging — Key Insight

**Current network setup:** `agent-spawn` does NOT use `--unshare-net`. The sandbox shares the host network namespace. This means:

- `localhost` inside the sandbox IS the host's localhost.
- A proxy running on `127.0.0.1:PORT` on the host is directly reachable from the sandbox at `http://localhost:PORT`.
- No socat bridging, no Unix socket relay, no network namespace plumbing needed.

**What to inject in the sandbox:**
```bash
--setenv HTTP_PROXY  "http://localhost:PORT"
--setenv HTTPS_PROXY "http://localhost:PORT"
--setenv NO_PROXY    "localhost,127.0.0.1"  # Don't proxy nix daemon, etc.
--setenv NODE_EXTRA_CA_CERTS "/run/secret-proxy-ca/ca.crt"  # bind-mounted into sandbox
--setenv ANTHROPIC_API_KEY "PLACEHOLDER_ANTHROPIC"
--setenv OPENAI_API_KEY    "PLACEHOLDER_OPENAI"
```

**CA cert bind-mount:** The proxy service generates a CA cert. The cert (not the key) is made available at a predictable path, bind-mounted read-only into the sandbox. The sandbox trusts this cert via `NODE_EXTRA_CA_CERTS`.

**If network isolation is desired later (optional enhancement):** Add `--unshare-net` to bwrap, use `slirp4netns` or `socat` bridging. Phase 22 explicitly does not require this — the current unrestricted network policy from Phase 11 is preserved.

---

## 6. Agent Identity Validation

**The problem:** How does the proxy know the request came from a legitimate agent session vs. an attacker who guessed the proxy port?

**Options:**

| Approach | Complexity | Security | Notes |
|----------|-----------|---------|-------|
| Shared secret (token in `Proxy-Authorization`) | Low | Medium | Token injected as env var alongside `ANTHROPIC_API_KEY=PLACEHOLDER`. Proxy validates before injecting. Token per-session or shared. |
| Session ID from spawn | Low | Medium | `SANDBOX_NAME` is already set as env var. Proxy checks session is registered. |
| Localhost-only binding | Low | Low | Proxy listens on `127.0.0.1` only. Attacker must already have local code execution — in which case they have bigger problems. |
| Unix socket | Medium | Medium | Only processes with filesystem access to the socket path can connect. Bind-mount into sandbox, hide from non-sandbox. |
| Kubernetes SA token (Netclode approach) | High | High | Not applicable — no Kubernetes here. |

**Recommendation:** Localhost-only binding + per-session `Proxy-Authorization` token. The proxy is already limited to localhost; the token adds a layer so that arbitrary processes on the host cannot use it. The token is a randomly generated per-session secret, injected alongside `ANTHROPIC_API_KEY=PLACEHOLDER`. Not stored in the sandbox's filesystem, only in the process environment.

**Simpler option for MVP:** Just bind to localhost with no extra auth. The threat model on this VPS is: the sandbox is bubblewrap-isolated, and the proxy port isn't exposed publicly (firewall). The risk of a sandbox escape bypassing localhost-only binding is low enough for a first implementation. Can add session tokens in a follow-up.

---

## 7. Reflection Attack Prevention

**The concern:** If the real key is injected into the `Authorization` header, can an agent exfiltrate it by making the proxy inject it into a request to `evil.com`?

**Mitigation — host-based allowlisting:**
- Claude agents: only inject if target host == `api.anthropic.com`
- Codex agents: only inject if target host == `api.openai.com`
- All other hosts: CONNECT tunnel passthrough (no injection, no interception)

The PLACEHOLDER value is never sent to the upstream if the host is not allowlisted — the proxy either rejects the request or passes it through unmodified with the placeholder.

**Why header-only injection (not body) prevents reflection:**
The proxy reads the `Authorization: Bearer PLACEHOLDER` header, replaces only that header value, and forwards the modified request. It does not reflect the real key back in the response body. Even if a compromised agent makes the API return an echo of its request headers, the real key was already consumed by the network layer — the agent process never saw it.

---

## 8. Existing and Off-the-Shelf Options

| Option | Language | NixOS Module | HTTPS MITM | Per-host allowlist | Notes |
|--------|----------|-------------|-----------|-------------------|-------|
| **mitmproxy** (Python) | Python | Package only (no service module) | Yes | Via addon script | Heavy, Python, NixOS Discourse shows no service module exists |
| **goproxy** (elazarl) | Go | None | Yes (MITM mode) | Via handler | Good library for building on |
| **Fly Tokenizer** | Go | None | No (CONNECT only for HTTPS) | Yes (allowed_hosts in encrypted token) | Not suitable as-is — CONNECT can't modify headers |
| **Custom Go binary** | Go | Build with Nix | Yes (via CA gen) | Yes | 200-300 line proxy; most control |
| **mitmproxy with addon** | Python | No service module | Yes | Via Python addon | Works but heavyweight dependency |
| squid | C | Yes (`services.squid`) | Via ssl_bump + CA | Via ACL | Complex config, heavyweight |
| Envoy | C++ | None | Yes | Via filter | Way overkill |

**No existing NixOS module** fits the requirement out of the box.

**Recommended implementation: Custom Go binary.** Reasons:
1. The Go standard library has everything needed: `net/http`, `crypto/tls`, `crypto/x509`.
2. A MITM HTTPS proxy in Go is ~250-400 lines (CA cert generation, CONNECT handling, header replacement, host allowlisting).
3. Packages easily as a Nix derivation (`pkgs.buildGoModule`).
4. No runtime dependencies — single static binary.
5. goproxy (elazarl/goproxy) is a well-tested library that handles the MITM complexity; the addon is ~50 lines.
6. Alternative: use `github.com/AdguardTeam/gomitmproxy` which provides a clean interface.

**mitmproxy addon alternative:** Viable but Python + mitmproxy is a heavier dependency (~80MB). Addon would be ~20 lines. No NixOS service module means writing one anyway. Go is preferred.

---

## 9. TLS/HTTPS CA Certificate Flow

```
Proxy starts
  |
  +-> Generate CA keypair (or load from sops secret if persistent)
  |    CA private key -> stays in proxy memory (or /run/secrets/)
  |    CA cert (public) -> written to /run/secret-proxy-ca/ca.crt
  |
agent-spawn invoked
  |
  +-> Bind-mount /run/secret-proxy-ca/ca.crt into sandbox (read-only)
  |
  +-> Set NODE_EXTRA_CA_CERTS=/run/secret-proxy-ca/ca.crt in sandbox env
  +-> Set ANTHROPIC_API_KEY=PLACEHOLDER_ANTHROPIC
  +-> Set HTTPS_PROXY=http://127.0.0.1:PORT
  |
Agent makes API call
  |
  +-> SDK sends: CONNECT api.anthropic.com:443 HTTP/1.1 [to proxy]
  |
Proxy receives CONNECT
  |
  +-> Check: is api.anthropic.com in allowlist for ANTHROPIC? YES.
  +-> Generate cert for api.anthropic.com signed by CA
  +-> Respond: 200 Connection Established
  +-> Terminate TLS from agent using generated cert
  |    Agent trusts it (CA cert in NODE_EXTRA_CA_CERTS)
  |
Proxy reads plaintext HTTP request
  |
  +-> Find: Authorization: Bearer PLACEHOLDER_ANTHROPIC
  +-> Replace: Authorization: Bearer <real_anthropic_key>
  |
Proxy forwards to upstream api.anthropic.com:443 over new TLS connection
  |
  +-> Real key used, never seen by agent process
```

---

## 10. Minimal Implementation Design

### Proxy Binary (Go, ~300 lines)

```
secret-proxy
  - Listens on 127.0.0.1:PORT (configurable, e.g., 7979)
  - On startup: generate ephemeral CA keypair or load from sops-nix secret path
  - Writes CA cert to /run/secret-proxy-ca/ca.crt (readable by agent-spawn)
  - Handles HTTP CONNECT:
      1. Parse target host
      2. If target in allowlist: MITM, replace Authorization header
      3. If target not in allowlist: transparent CONNECT tunnel (no injection)
  - Allowlist config: loaded from a config file or env vars, e.g.:
      PLACEHOLDER_ANTHROPIC -> api.anthropic.com -> /run/secrets/anthropic-api-key
      PLACEHOLDER_OPENAI    -> api.openai.com    -> /run/secrets/openai-api-key
  - Session token: optional Proxy-Authorization check (phase 2 hardening)
```

### NixOS Module (`modules/secret-proxy.nix`, ~80 lines)

```nix
# New module
systemd.services.secret-proxy = {
  description = "Secret injection proxy for agent sandboxes";
  wantedBy = [ "multi-user.target" ];
  after = [ "network.target" "sops-nix.service" ];
  serviceConfig = {
    ExecStart = "${secret-proxy-binary}/bin/secret-proxy --port 7979 --config /etc/secret-proxy/config.json";
    # Run as dangirsh (needs to read /run/secrets/ — sops-nix must grant access)
    User = "dangirsh";
    RuntimeDirectory = "secret-proxy-ca";  # creates /run/secret-proxy-ca/
    RuntimeDirectoryMode = "0755";
    ...
  };
};
```

### agent-spawn Changes

Replace key injection (lines 188-198 of `modules/agent-compute.nix`):

**Before:**
```bash
if [ -n "$ANTHROPIC_KEY" ]; then
  BWRAP_ARGS+=( --setenv ANTHROPIC_API_KEY "$ANTHROPIC_KEY" )
fi
```

**After:**
```bash
BWRAP_ARGS+=( --setenv ANTHROPIC_API_KEY "PLACEHOLDER_ANTHROPIC" )
BWRAP_ARGS+=( --setenv OPENAI_API_KEY    "PLACEHOLDER_OPENAI" )
BWRAP_ARGS+=( --setenv HTTP_PROXY        "http://127.0.0.1:7979" )
BWRAP_ARGS+=( --setenv HTTPS_PROXY       "http://127.0.0.1:7979" )
BWRAP_ARGS+=( --setenv NO_PROXY          "localhost,127.0.0.1" )
# CA cert for MITM TLS verification
if [ -f /run/secret-proxy-ca/ca.crt ]; then
  BWRAP_ARGS+=( --ro-bind /run/secret-proxy-ca/ca.crt /run/secret-proxy-ca/ca.crt )
  BWRAP_ARGS+=( --setenv NODE_EXTRA_CA_CERTS "/run/secret-proxy-ca/ca.crt" )
fi
```

Note: Remove the pre-sandbox `cat /run/secrets/anthropic-api-key` lines entirely. The proxy reads secrets, not agent-spawn.

---

## 11. Port and Security Configuration

**Port:** 7979 (arbitrary, localhost-only). Must be added to `internalOnlyPorts` in `networking.nix` per Module Change Checklist. The port is localhost-only (127.0.0.1 bind), so nftables firewall does not need to open it.

**Secrets access for proxy service:** The proxy service needs to read `/run/secrets/anthropic-api-key` and `/run/secrets/openai-api-key`. The sops-nix `owner` for these secrets must include `dangirsh` (or whichever user runs the proxy service). Currently in `secrets.nix`, check that these secrets have `owner = "dangirsh"` (they should, since agent-spawn runs as dangirsh).

**CA private key storage options:**
1. **Ephemeral (simplest):** Generate CA at service startup, CA lives only in memory + `/run/secret-proxy-ca/`. Rotates every restart. No persistence needed.
2. **Persistent (sops-nix):** Generate CA once, store encrypted in `secrets/neurosys.yaml`. Survives restarts. Required if sandbox trust needs to persist across proxy restarts (usually not needed).

Recommendation: **Ephemeral CA** for simplicity. Generate at startup, write cert to `/run/` (tmpfs). If the proxy restarts, agent-spawn picks up the new CA cert on next sandbox launch.

---

## 12. Codex Proxy Support Risk

As noted in Section 4, Codex CLI proxy support is incomplete (GitHub issues #4242, #6060 from 2025 are open). The proxy env vars may not be honored for all Codex HTTP clients.

**Mitigation options:**
1. **Claude-first implementation:** Phase 22 targets Claude Code only. Codex continues using direct key injection until upstream fixes.
2. **DNAT-based transparent proxy (like Matchlock):** Use nftables DNAT to redirect all TCP traffic on port 443 to the proxy, without requiring the SDK to honor `HTTPS_PROXY`. More complex, requires network namespace (`--unshare-net`), and would need socat bridging. Major scope increase.
3. **Wait for upstream Codex fix:** Track issues #4242 and #6060; add Codex support when proxy env var handling is confirmed working.

**Recommendation for Phase 22:** Claude-first. Keep Codex on direct key injection (note this in code with `# TODO: migrate to proxy when Codex honors HTTPS_PROXY`). The phase goal is satisfied for the primary agent (Claude Code).

---

## 13. Files to Create/Modify

| File | Action | What Changes |
|------|--------|-------------|
| `modules/secret-proxy.nix` | Create new | New Go proxy binary, systemd service, RuntimeDirectory |
| `modules/agent-compute.nix` | Modify | Remove direct key injection, add PLACEHOLDER + HTTPS_PROXY + CA cert bind-mount |
| `modules/networking.nix` | Modify | Add 7979 to `internalOnlyPorts` |
| `modules/default.nix` | Modify | Import `./secret-proxy.nix` |
| `packages/secret-proxy.nix` | Create new | Go binary derivation (`buildGoModule`) |
| Go source (`packages/secret-proxy/`)  | Create new | The proxy binary source (~300 lines) |
| `modules/secrets.nix` | Possibly | Verify `anthropic-api-key` and `openai-api-key` owner = dangirsh |

**Module size check:** `secret-proxy.nix` will be ~80 lines (NixOS module + service config). `packages/secret-proxy.nix` is the build derivation. Go source is separate. This justifies a new module (>20 lines rule in CLAUDE.md).

---

## 14. Don't Hand-Roll vs Use Off-the-Shelf

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| HTTPS MITM | Full proxy from scratch | goproxy (elazarl/goproxy) library | Battle-tested MITM handling; CONNECT + cert gen already implemented |
| CA cert generation | Manual X.509 code | `crypto/x509` + `crypto/rand` stdlib | Standard library is sufficient; Go makes this ~30 lines |
| Header replacement | Complex regex | Simple `req.Header.Set("Authorization", "Bearer "+realKey)` | HTTP headers in Go are a simple map |
| Per-session allowlist | Complex session tracking | Simple hostname comparison at CONNECT time | MVP: map of placeholder → (upstream host, secret path) |
| systemd service | Custom init script | `systemd.services` NixOS option | Already the pattern for all other services |
| NixOS service | OCI container | NixOS module + `buildGoModule` | Consistent with project conventions; no Docker for host services |

---

## 15. Implementation Effort Assessment

The phase description says "Medium — small Go/Rust proxy service + NixOS module + agent-spawn integration."

Based on research, this is accurate:

| Component | Estimated Effort |
|-----------|----------------|
| Go proxy binary (~300 lines) | 2-3 hours |
| Nix `buildGoModule` derivation | 30 min |
| NixOS service module | 1 hour |
| agent-spawn changes | 30 min |
| Integration testing (deploy + verify) | 1-2 hours |

**Total: ~5-7 hours.** Medium is correct. The main complexity is the Go MITM proxy — everything else is plumbing.

**Go vs Rust:** Go is preferred here. The NixOS/nixpkgs ecosystem has better Go packaging support (`buildGoModule`), and the standard library's `net/http` + `crypto/tls` + `crypto/x509` makes MITM proxy implementation straightforward. Rust is also feasible (`rustls` + `hyper`), but adds compile-time complexity.

---

## 16. Open Questions for PLAN Phase

1. **CA ephemeral vs persistent?** Decision needed. Ephemeral (generate at service start) is simpler; persistent (sops-nix) survives restarts but adds a new secret. **Recommend: ephemeral.** The impact of regeneration is negligible — just re-run agent-spawn after proxy restarts, which picks up the new CA.

2. **Session-level proxy token (Proxy-Authorization)?** Phase success criteria says "Agent identity validated before token injection." Is localhost-only binding sufficient, or does a per-session `Proxy-Authorization` token satisfy this? **Recommend:** Include a `SANDBOX_PROXY_TOKEN` per-session random token as a `Proxy-Authorization` header. Adds ~30 lines to proxy and agent-spawn. Satisfies criteria 6.

3. **GITHUB_TOKEN handling?** The current agent-spawn also injects `GITHUB_TOKEN`. GitHub API is at `api.github.com`. Should it be proxied too? **Recommend:** Include `api.github.com` in the proxy allowlist with `PLACEHOLDER_GITHUB`. Same pattern as Anthropic/OpenAI. Satisfies symmetry.

4. **Codex scope?** As discussed — Claude-first with a TODO for Codex. **Confirm with user if desired.**

5. **--no-sandbox behavior?** When `--no-sandbox` is used, should the proxy still be involved? Probably not — `--no-sandbox` mode gets direct key injection as before. Simplicity.

6. **Network isolation (--unshare-net)?** Phase 22 does not require it (Phase 11 locked: no network namespace). Should Phase 22 add it as part of the network isolation story? **Recommend: out of scope** — adding `--unshare-net` requires socat bridging, a major scope increase. Note it as a future enhancement.

---

## Sources

- [angristan/netclode GitHub](https://github.com/angristan/netclode)
- [Netclode blog post (stanislas.blog, Feb 2026)](https://stanislas.blog/2026/02/netclode-self-hosted-cloud-coding-agent/)
- [superfly/tokenizer GitHub](https://github.com/superfly/tokenizer)
- [Fly Tokenizer blog: "Tokenized Tokens"](https://fly.io/blog/tokenized-tokens/)
- [anthropic-experimental/sandbox-runtime](https://github.com/anthropic-experimental/sandbox-runtime)
- [Claude Code's srt bubblewrap analysis (sambaiz.net)](https://www.sambaiz.net/en/article/547/)
- [jingkaihe/matchlock](https://github.com/jingkaihe/matchlock)
- [Claude Code enterprise proxy docs](https://code.claude.com/docs/en/corporate-proxy)
- [Claude Code proxy bug: HTTPS_PROXY ignored in settings.json #11660](https://github.com/anthropics/claude-code/issues/11660)
- [Claude Code Bun CA cert bug #25977](https://github.com/anthropics/claude-code/issues/25977)
- [Codex proxy support issue #4242](https://github.com/openai/codex/issues/4242)
- [Codex http_proxy config issue #6060](https://github.com/openai/codex/issues/6060)
- [Go and Proxy Servers Part 2: HTTPS (eli.thegreenplace.net)](https://eli.thegreenplace.net/2022/go-and-proxy-servers-part-2-https-proxies/)
- [elazarl/goproxy](https://github.com/elazarl/goproxy)
- [AdguardTeam/gomitmproxy](https://github.com/AdguardTeam/gomitmproxy)
- [mitmproxy NixOS module discussion](https://discourse.nixos.org/t/mitmproxy-nixos-module/48675)
- Project: `modules/agent-compute.nix` (authoritative current implementation)
- Project: `modules/networking.nix` (internalOnlyPorts pattern)
- Project: `.planning/phases/11-agent-sandboxing-default-on-bubblewrap-srt-isolation-for-all-coding-agents/11-RESEARCH.md`

---

## Metadata

**Confidence breakdown:**
- Current agent-spawn setup: HIGH (read from source)
- Netclode architecture: HIGH (from blog post and source)
- Fly Tokenizer architecture: HIGH (from source and blog)
- Claude srt proxy bridging: HIGH (from sambaiz.net analysis)
- MITM necessity: HIGH (CONNECT cannot modify headers — HTTPS only choice)
- Claude Code proxy support: MEDIUM-HIGH (documented, with known Bun edge cases)
- Codex proxy support: LOW-MEDIUM (open issues, not confirmed working)
- Go implementation feasibility: HIGH (standard library + well-tested libraries)
- NixOS module pattern: HIGH (follows existing module conventions)

**Research date:** 2026-02-24
**Valid until:** 2026-03-24 (Codex proxy status may change)
