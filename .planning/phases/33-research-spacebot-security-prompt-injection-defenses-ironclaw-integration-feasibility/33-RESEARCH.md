# Phase 33 Research: Spacebot Security + Ironclaw Integration Feasibility

**Researched:** 2026-02-26
**Sources:** `/data/projects/spacebot` (source code), `/data/projects/others/ironclaw` (source code), `/data/projects/parts-awig/.planning/research/02-ironclaw-security-patterns.md` (prior analysis)
**Confidence:** HIGH (direct source code analysis of both projects)

---

## Part 1: Spacebot Prompt Injection Defenses

### 1.1 Architecture Overview

Spacebot uses a **process isolation model** with five LLM process types (Channel, Branch, Worker, Compactor, Cortex), each with distinct tool access and context boundaries. Security is enforced through multiple layers rather than a single defense.

### 1.2 Existing Defense Layers

#### Layer 1: Process Isolation (Strong)

Each process type gets a different `ToolServer` with restricted tools:

| Process | Available Tools | Cannot Access |
|---------|----------------|---------------|
| Channel | reply, branch, spawn_worker, route, cancel, skip, react | shell, file, exec, memory_* |
| Branch | memory_save, memory_recall, memory_delete, channel_recall, worker_inspect | shell, file, exec, reply |
| Worker | shell, file, exec, set_status, browser, web_search | memory_*, reply, spawn_worker |
| Cortex | memory_save | Everything else |

**Key finding:** The channel (user-facing) process CANNOT execute shell commands, read/write files, or interact with the filesystem directly. All task execution must go through worker delegation. This is structural isolation -- even a fully compromised channel prompt cannot execute arbitrary commands because the tools simply don't exist in its `ToolServer`.

#### Layer 2: Filesystem Sandbox (Strong)

Workers execute shell/exec commands inside a bubblewrap (bwrap) sandbox on Linux:

- **Read-only root filesystem** via `--ro-bind / /`
- **Workspace-only writes** via `--bind <workspace> <workspace>`
- **Private /tmp** per invocation via `--tmpfs /tmp`
- **Read-only agent data dir** explicitly re-protected via `--ro-bind <data_dir> <data_dir>`
- **PID namespace isolation** via `--unshare-pid`
- **Session isolation** via `--new-session` (prevents TTY injection)
- **Die-with-parent** ensures child processes don't outlive the sandbox

On macOS: sandbox-exec with generated SBPL profile (deny-default, allow-read-all, allow-write-workspace).

Fallback: If neither backend is available, processes run unsandboxed with a logged warning.

**Source:** `/data/projects/spacebot/src/sandbox.rs`, `/data/projects/spacebot/docs/design-docs/sandbox.md`

#### Layer 3: Tool-Level Path Validation (Medium)

- **FileTool:** `resolve_path()` canonicalizes paths, checks `starts_with(workspace)`, and **rejects symlinks** component-by-component to prevent TOCTOU attacks. Protected identity files (SOUL.md, IDENTITY.md, USER.md) are write-blocked.
- **ShellTool/ExecTool:** Working directory validated to be within workspace before execution.
- **ExecTool:** `DANGEROUS_ENV_VARS` blocklist prevents library injection via `LD_PRELOAD`, `DYLD_INSERT_LIBRARIES`, `NODE_OPTIONS`, etc. (12 blocked env vars).

**Source:** `/data/projects/spacebot/src/tools/file.rs`, `/data/projects/spacebot/src/tools/shell.rs`, `/data/projects/spacebot/src/tools/exec.rs`

#### Layer 4: Secret Leak Detection (Medium)

`SpacebotHook` scans **all tool arguments before execution** and **all tool results after execution**:

- **11 regex patterns** for API key formats (OpenAI `sk-*`, Anthropic `sk-ant-*`, OpenRouter `sk-or-*`, PEM private keys, GitHub `ghp_*`, Google `AIza*`, Discord bot tokens, Slack `xoxb-*`/`xapp-*`, Telegram bot tokens, Brave `BSA*`)
- **Multi-encoding detection:** Raw plaintext, URL-decoded (`sk%2Dant%2D...`), base64-decoded (standard + URL-safe), hex-decoded
- **Pre-execution:** Leak in tool args -> `ToolCallHookAction::Skip` (tool call blocked)
- **Post-execution:** Leak in tool output -> `HookAction::Terminate` (agent killed to prevent exfiltration via subsequent calls)

**Source:** `/data/projects/spacebot/src/hooks/spacebot.rs`

#### Layer 5: Output Filtering (Weak)

`should_block_user_visible_text()` blocks tool-call-like syntax, JSON payloads, and `<system-reminder>` tags from being sent as visible text to users. This prevents the LLM from accidentally echoing internal control structures.

**Source:** `/data/projects/spacebot/src/tools.rs` (lines 186-219)

#### Layer 6: Browser SSRF Protection (Medium)

`validate_url()` blocks cloud metadata endpoints (169.254.169.254, etc.), private/loopback/link-local IPs, and non-HTTP schemes.

**Source:** `/data/projects/spacebot/src/tools/browser.rs`

### 1.3 What Spacebot Does NOT Have

| Defense | Status | Risk Level (for neurosys) |
|---------|--------|--------------------------|
| **Input sanitization for prompt injection patterns** | NOT PRESENT | Low (see 1.4) |
| **Content filtering on tool output before LLM sees it** | NOT PRESENT (leak detection only) | Medium |
| **Network isolation for workers** | NOT PRESENT (acknowledged in sandbox.md) | Low (Tailscale-only) |
| **Rate limiting on tool calls** | NOT PRESENT | Low |
| **User authentication on webchat API** | Bearer token auth on API routes, but no per-user isolation on webchat | Medium |
| **Prompt injection detection (a la ironclaw Sanitizer)** | NOT PRESENT | Low-Medium |
| **Tool output wrapping/tagging** | NOT PRESENT (ironclaw wraps in `<tool_output>` tags) | Low |

### 1.4 Neurosys-Specific Threat Model

The neurosys deployment has a substantially reduced attack surface compared to a public-facing spacebot deployment:

**Network isolation:**
- Port 19898 is NOT on the public firewall (nftables `internalOnlyPorts` assertion in `networking.nix`)
- Accessible ONLY via Tailscale (`trustedInterfaces = ["tailscale0"]`)
- All Tailscale peers are authenticated -- no anonymous access

**Container isolation:**
- Runs as Docker OCI container (`ghcr.io/spacedriveapp/spacebot:slim`)
- Volume mount limited to `/var/lib/spacebot:/data`
- No Docker socket mounted
- No messaging channels configured (no Discord, no Telegram -- only webchat via Tailscale)

**Secret injection:**
- API key via sops-nix template (`spacebot-env`), never in config.toml or Nix store
- `mode = "0400"` on the rendered env file

**Effective attack vectors on neurosys:**
1. **Authenticated Tailscale peer sends malicious messages via webchat** -- requires Tailscale authentication, then could attempt prompt injection via the webchat API
2. **Compromised worker exfiltrates data via network** -- sandbox doesn't isolate network; a malicious worker could `curl` data out. Mitigated by: Tailscale network (no public-facing services to exfiltrate TO from the worker's perspective), plus leak detection would catch API keys
3. **Skills supply chain** -- if malicious skills are installed, they execute with full worker permissions. Currently no skills installed.

**Verdict:** The current spacebot security posture is ADEQUATE for the neurosys deployment, where the primary threat is an authenticated Tailscale peer attempting prompt injection. The process isolation (channel cannot execute commands) and sandbox (workers filesystem-contained) provide strong structural defenses. The missing input sanitization layer is a gap worth monitoring but not critical given the trusted-network deployment.

### 1.5 Recommendations

**No action needed now:**
- Spacebot's structural process isolation + bubblewrap sandbox is stronger than pattern-based input sanitization for preventing actual damage from prompt injection
- The neurosys deployment's Tailscale-only access makes external prompt injection impractical

**Worth monitoring:**
- If messaging channels (Discord, Telegram) are added, the attack surface increases significantly -- any user in those channels could attempt injection
- The `send_file` tool on the channel process was noted in the sandbox design doc as lacking workspace path validation -- check if this has been fixed in the deployed version

**Optional hardening (low priority, follow-up phase):**
- Switch from Docker container to native NixOS service using `spacebot.nixosModules.default` (enables systemd hardening: `NoNewPrivileges`, `ProtectSystem`, `ProtectHome`, etc.)
- Add `bubblewrap` to the system packages for the sandbox to use (currently the Docker image includes it, but a native service would need it installed)

---

## Part 2: Ironclaw Integration Feasibility

### 2.1 What Is Ironclaw

Ironclaw is a "secure personal AI assistant" built in Rust by NEAR AI. Key characteristics:

- **Single-user focused** (user_id scoped, personal assistant model)
- **NEAR AI as LLM provider** (proprietary session token auth, proxied model access)
- **PostgreSQL or libSQL/Turso** for persistence
- **WASM sandbox for tools** (Wasmtime-based, capability model)
- **Docker sandbox for code execution** (orchestrator/worker pattern)
- **Claude Code bridge** for delegating to Claude CLI inside containers
- **Safety module** with prompt injection sanitizer, leak detector, policy engine

**Repository:** `github:nearai/ironclaw` (cloned at `/data/projects/others/ironclaw`)

### 2.2 Architecture Comparison

| Dimension | Spacebot | Ironclaw |
|-----------|----------|----------|
| **LLM loop** | Rig framework (`Agent<SpacebotModel, SpacebotHook>`) | Custom agent loop with `LlmProvider` trait |
| **Process model** | 5 specialized processes (Channel/Branch/Worker/Compactor/Cortex) | Single agent with parallel job scheduler |
| **Tool execution** | In-process tool calls via Rig `ToolServer` | `Tool` trait with `JobContext` |
| **Sandbox** | bubblewrap (Linux) / sandbox-exec (macOS) per shell/exec call | WASM (Wasmtime) for tools + Docker for code execution |
| **Memory** | SQLite + LanceDB (embedded), typed memories with cortex synthesis | PostgreSQL/libSQL workspace with hybrid search |
| **Messaging** | Multi-adapter (Discord, Telegram, Slack, Webchat, Twitch) | Multi-channel (REPL, HTTP webhook, WASM channels, web gateway) |
| **UI** | Embedded Vite/React SPA | Embedded web dashboard + TUI (Ratatui) |
| **LLM providers** | Multi-provider (Anthropic, OpenAI, OpenRouter, etc.) via `LlmManager` | NEAR AI only (with Rig adapter for local models) |
| **Identity** | SOUL.md, IDENTITY.md, USER.md per agent | AGENTS.md, SOUL.md, USER.md, IDENTITY.md per workspace |
| **Secrets** | Config-based credentials, sops for deployment | AES-256-GCM encrypted at rest, OS keychain for master key |
| **Deployment** | Single binary, NixOS module, Docker image | Single binary, Docker compose, systemd service file |

### 2.3 The Integration Question

**"Can ironclaw replace spacebot's LLM backend without breaking the UI/UX layer?"**

**Short answer: No. The architectures are fundamentally incompatible at the LLM loop level.**

### 2.4 Detailed Analysis

#### Why a backend swap is not feasible

1. **Different LLM abstraction layers.** Spacebot uses Rig's `CompletionModel` trait and `Agent` framework with custom `PromptHook`. Ironclaw uses its own `LlmProvider` trait with a different message/tool-call model. The Rig adapter in ironclaw (`src/llm/rig_adapter.rs`) goes the opposite direction -- it wraps Rig models to implement ironclaw's `LlmProvider` trait.

2. **Spacebot's multi-process model is core to its architecture.** The Channel/Branch/Worker separation is structural -- it determines which tools are available, how context flows, how delegation works. Ironclaw has no equivalent; it uses a single-agent job scheduler. Replacing the "backend" would mean replacing the entire agent execution model.

3. **Tight coupling between UI and agent processes.** Spacebot's embedded React SPA communicates via SSE events that are directly tied to `ProcessEvent` types (worker status, branch results, tool calls). The UI is built around the multi-process model. Ironclaw's web gateway has a completely different API and event model.

4. **Memory systems are incompatible.** Spacebot uses typed memories (fact, preference, decision, goal, todo, observation) with cortex synthesis into a bulletin. Ironclaw uses a filesystem-metaphor workspace with chunked documents and hybrid search. These are fundamentally different approaches to agent memory.

5. **Messaging adapters would need rewriting.** Spacebot has native Discord/Telegram/Slack adapters with rich message support (cards, blocks, reactions). Ironclaw implements Slack/Telegram as WASM channel plugins. The abstraction layers are incompatible.

#### What COULD be extracted from ironclaw

Ironclaw's **safety module** is the most portable component and the most relevant to neurosys's needs:

| Component | Source | Portability to Spacebot |
|-----------|--------|------------------------|
| **Sanitizer** (prompt injection pattern detection) | `src/safety/sanitizer.rs` | MEDIUM -- Aho-Corasick + regex patterns could be ported as a pre-processing step on inbound messages |
| **Policy engine** (configurable rules with actions) | `src/safety/policy.rs` | MEDIUM -- useful abstraction, but spacebot's `SpacebotHook` already provides pre/post tool-call interception |
| **Leak detector** (16 API key patterns, two-tier detection) | `src/safety/leak_detector.rs` | LOW -- spacebot already has equivalent leak detection in `SpacebotHook` (11 patterns + multi-encoding) |
| **Credential injector** (WASM-boundary secret injection) | `src/tools/wasm/credential_injector.rs` | NOT APPLICABLE -- spacebot doesn't use WASM tools |
| **Endpoint allowlisting** (URL validation with userinfo bypass protection) | `src/tools/wasm/allowlist.rs` | LOW -- relevant only if network isolation is added to spacebot workers |
| **Tool output wrapping** (`<tool_output>` XML tags) | `src/safety/mod.rs` | LOW -- simple pattern, could be added to spacebot's tool result pipeline |

#### Ironclaw's unique security features vs spacebot

| Feature | Ironclaw | Spacebot |
|---------|----------|----------|
| **WASM tool sandbox** | Wasmtime with capability model, fuel metering, memory limits | N/A (tools are in-process Rust) |
| **Credential injection at boundary** | WASM tools never see actual secrets | Workers inherit env vars (leak detection is post-hoc) |
| **Input sanitization pipeline** | Sanitizer -> Validator -> Policy -> Leak scan | None (relies on LLM alignment + structural isolation) |
| **Tool output wrapping** | `<tool_output name="X" sanitized="true">` | None |
| **Encrypted secrets at rest** | AES-256-GCM with HKDF, zeroing-on-drop | Plain config + sops-nix at deployment level |
| **Endpoint allowlisting** | Per-tool URL allowlist with HTTPS enforcement | Browser SSRF protection only |

### 2.5 Go/No-Go Recommendation

**GO: NO -- do not attempt to wire ironclaw as spacebot's backend.**

**Rationale:**
- The architectures are fundamentally different at every layer (LLM loop, process model, memory, UI, messaging)
- The effort would be equivalent to rewriting spacebot from scratch using ironclaw's patterns -- months of work with no clear benefit
- Spacebot is actively maintained by Spacedrive (regular releases, design docs, comprehensive test suite)
- Ironclaw is tied to NEAR AI's ecosystem (session tokens, proprietary auth, NEAR AI billing)
- The security features worth having from ironclaw (input sanitization) can be extracted as standalone components far more cheaply than a full integration

**If you want ironclaw's security features in spacebot, the path is:**
1. Port the `Sanitizer` pattern set as a pre-processing filter on `InboundMessage` content (estimated effort: 1-2 days)
2. Add `<tool_output>` wrapping to worker tool results before they enter branch/channel context (estimated effort: 0.5 days)
3. Consider adding a `PolicyRule` engine as a configurable layer on top of `SpacebotHook` (estimated effort: 2-3 days)

Total estimated effort for extracting useful security patterns: **~1 week**
Total estimated effort for full ironclaw integration: **3-6 months** (and it wouldn't work well)

---

## Summary for Planning

### Spacebot Security Posture (for neurosys)
- **Adequate** for current Tailscale-only deployment
- Strong structural defenses (process isolation, bubblewrap sandbox, leak detection)
- Missing input sanitization layer (low risk given trusted-network access)
- No immediate action needed; monitor if messaging channels are added

### Ironclaw Integration
- **Not feasible** as a backend replacement -- architectures are fundamentally incompatible
- **Selective extraction** of safety patterns is viable and worthwhile (~1 week effort)
- **No follow-up integration phase recommended**

### Potential Follow-Up Phases
1. **Port ironclaw safety patterns to spacebot** (if messaging channels are planned): Extract Sanitizer + PolicyRule patterns as a spacebot contribution or local patch. Low effort, high value if the attack surface expands.
2. **Switch to native NixOS service** (if Docker overhead is a concern): Use `spacebot.nixosModules.default` with systemd hardening. Medium effort, enables bubblewrap sandbox natively.
3. **Network isolation for workers** (if sensitive data is processed): Add `--unshare-net` to bubblewrap config for workers that don't need network access. Low effort, defense-in-depth.
