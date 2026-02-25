# Phase 29 Research: Agentic Dev Maxing — Batteries Included

**Date:** 2026-02-25
**Status:** Complete — ready for PLAN.md

---

## 1. Package Sourcing Strategy

### 1.1 llm-agents.nix Already Has All Three Agents

The `llm-agents.nix` overlay (already a flake input) provides `pkgs.opencode`, `pkgs.gemini-cli`, and `pkgs.pi` directly. No new flake inputs are needed. The overlay exposes packages flat in `pkgs`, the same way `pkgs.claude-code` and `pkgs.codex` are already accessed.

**Binary cache:** Numtide binary cache at `https://cache.numtide.com` is already configured in `agent-compute.nix`, so these packages arrive pre-built.

### 1.2 Package Details

#### opencode (`pkgs.opencode`)
- **Version:** 1.1.25 (in llm-agents.nix; also available in nixpkgs unstable)
- **Build method:** llm-agents.nix uses a **pre-built binary** fetched from GitHub releases (`.tar.gz`), patched with `wrapBuddy` on Linux and wrapped to include `fzf` + `ripgrep` runtime deps. This is the correct approach — the nixpkgs version builds from source and has a history of hash-mismatch failures as upstream npm deps change.
- **Binary name:** `opencode`
- **Provider config:** Auto-detects `ANTHROPIC_API_KEY`, `OPENAI_API_KEY`, `GEMINI_API_KEY`, `XAI_API_KEY`, `OPENROUTER_API_KEY`, `GROQ_API_KEY`, `GITHUB_TOKEN` from environment.
- **Proxy/baseURL:** Configured via `~/.config/opencode/opencode.json` with `{ "provider": { "anthropic": { "options": { "baseURL": "http://127.0.0.1:9091" } } } }`. Also supports `{env:VARIABLE_NAME}` substitution in config files. No single env var override for baseURL — must use config file or `OPENCODE_CONFIG_CONTENT` env var.
- **Session storage:** `.opencode/` directories in project roots (SQLite). CASS already indexes these.
- **Config dir:** `~/.config/opencode/` (global), or per-project `opencode.json`.

#### gemini-cli (`pkgs.gemini-cli`)
- **Version:** 0.25.2 (llm-agents.nix); also in nixpkgs main
- **Build method:** llm-agents.nix builds from source via `buildNpmPackage` with `nodejs_22`. Patches out `node-pty`, hardcodes `ripgrep` path, disables auto-update.
- **Binary name:** `gemini`
- **API key env vars:**
  - `GEMINI_API_KEY` — primary (Google AI Studio key)
  - `GOOGLE_API_KEY` — also accepted
- **Proxy/baseURL:** `GOOGLE_GEMINI_BASE_URL` — supported via a merged PR (PR #6380), redirects API calls to a custom endpoint. This is the env var to inject when routing through a proxy.
- **Session storage:** `~/.gemini/tmp/` — CASS already indexes these (scans for `*_*.jsonl` pattern).
- **Note:** gemini-cli requires `--no-sandbox` flag internally for its own sandboxing, which conflicts with bwrap's `--disable-userns`. Must verify this in sandbox testing. The nixpkgs package removes `node-pty` which could cause pseudo-terminal issues — pre-test needed.

#### pi (`pkgs.pi`)
- **Version:** from `@mariozechner/pi-coding-agent` npm package, latest ~0.52.6
- **Build method:** llm-agents.nix uses `buildNpmPackage` with `dontNpmBuild = true` (package arrives pre-built from npm). Wraps binary with `fd` and `ripgrep` in PATH, sets `PI_SKIP_VERSION_CHECK=1`.
- **Binary name:** `pi`
- **API key env vars:** Standard names — `ANTHROPIC_API_KEY`, `OPENAI_API_KEY`, `GEMINI_API_KEY`, `XAI_API_KEY`, `GROQ_API_KEY`, `OPENROUTER_API_KEY`. Also supports `~/.pi/agent/auth.json` (auth file takes priority over env vars).
- **Proxy/baseURL:** No standard env var for Anthropic base URL override in pi. Custom providers can be registered with a `baseUrl` field via TypeScript extensions. Injecting the real key directly is the only clean option for the default Anthropic provider (same pattern as non-claw-swap projects already do in agent-spawn).
- **Session storage:** `~/.pi/agent/sessions/` in JSONL format, organized by working directory. CASS already indexes pi sessions as of cass v0.1.53+.

---

## 2. Agent Dispatch Changes (agent-spawn)

### 2.1 Current State

`agent-spawn` parses a positional agent arg: `claude|codex`. The script needs to be extended to accept `opencode|gemini|pi` and map them to the right command and env vars.

### 2.2 Changes Required in agent-spawn

**Agent-to-command mapping additions:**
```
opencode  → CMD="opencode"
gemini    → CMD="gemini"
pi        → CMD="pi"
```

**Env var injection per agent (inside bwrap):**
```bash
# All agents get OPENAI_KEY if set:
BWRAP_ARGS+=( --setenv OPENAI_API_KEY "$OPENAI_KEY" )

# New keys to read before sandbox entry:
GOOGLE_KEY="$(cat /run/secrets/google-api-key 2>/dev/null || true)"
XAI_KEY="$(cat /run/secrets/xai-api-key 2>/dev/null || true)"
OPENROUTER_KEY="$(cat /run/secrets/openrouter-api-key 2>/dev/null || true)"

# gemini: inject GEMINI_API_KEY + GOOGLE_GEMINI_BASE_URL for proxy routing
if [ -n "$GOOGLE_KEY" ]; then
  BWRAP_ARGS+=( --setenv GEMINI_API_KEY "$GOOGLE_KEY" )
  BWRAP_ARGS+=( --setenv GOOGLE_API_KEY "$GOOGLE_KEY" )
  # No proxy for gemini by default (Google key routes directly)
fi

# pi: inject real key (no proxy support for Anthropic in pi's default provider)
# ANTHROPIC_KEY already read; inject directly (not through proxy)
# (pi is not claw-swap, so real key is used same as other projects)

# opencode: ANTHROPIC_API_KEY + others auto-detected; baseURL must come from config
# Inject all keys; proxy for opencode done via global opencode.json at ~/.config/opencode/
if [ -n "$XAI_KEY" ]; then
  BWRAP_ARGS+=( --setenv XAI_API_KEY "$XAI_KEY" )
fi
if [ -n "$OPENROUTER_KEY" ]; then
  BWRAP_ARGS+=( --setenv OPENROUTER_API_KEY "$OPENROUTER_KEY" )
fi
```

**Usage string update:**
```
Usage: agent-spawn <name> <project-dir> [claude|codex|opencode|gemini|pi] [--no-sandbox] [--show-policy]
```

### 2.3 Sandbox Bind Mounts for New Agents

New config directories to expose read-only inside bwrap:
- `~/.config/opencode` → opencode global config (where baseURL is configured)
- `~/.local/share/opencode` → opencode auth.json and state
- `~/.pi/agent` → pi config and session storage (write needed for session persistence)
- `~/.gemini` → gemini state

```bash
--ro-bind-try /home/dangirsh/.config/opencode /home/dangirsh/.config/opencode
--bind-try /home/dangirsh/.local/share/opencode /home/dangirsh/.local/share/opencode
--bind-try /home/dangirsh/.pi/agent /home/dangirsh/.pi/agent
--bind-try /home/dangirsh/.gemini /home/dangirsh/.gemini
```

Note: `.local/share/opencode` and `.pi/agent` need `--bind` (writable) so agents can save session state. `.config/opencode` is read-only config — `--ro-bind-try` is correct.

### 2.4 Packages to Add to environment.systemPackages

In `agent-compute.nix`:
```nix
environment.systemPackages = [
  pkgs.claude-code
  pkgs.codex
  pkgs.opencode
  pkgs.gemini-cli
  pkgs.pi
  zmx
  agent-spawn
];
```

---

## 3. Secret Proxy Extension

### 3.1 Current Proxy Pattern (Phase 22)

The existing proxy is in `modules/secret-proxy.nix`, runs on `127.0.0.1:9091`, and rewrites Anthropic API calls — injecting the real key, stripping the placeholder, and forwarding to `api.anthropic.com`.

The proxy is claw-swap-scoped: in `agent-spawn`, only `PROJECT_DIR == /data/projects/claw-swap*` gets the placeholder key + proxy URL.

### 3.2 Proxy Extension Decision

**Gemini proxy:** `GOOGLE_GEMINI_BASE_URL` is supported in gemini-cli. However, the Google API is not proxied by the existing secret-proxy — that would require a second proxy service for a different protocol/auth header format. Decision: **inject GOOGLE_API_KEY directly** (same as OPENAI_KEY pattern). The key is never logged or visible inside the sandbox, which is acceptable risk. The proxy pattern is reserved for scenarios where a key must never enter the sandbox (the claw-swap use case, where agents write config files).

**opencode proxy for Anthropic:** opencode auto-detects `ANTHROPIC_API_KEY`. For claw-swap projects, the existing proxy placeholder works. For other projects, inject the real key directly (current behavior). No new proxy instance needed.

**No new proxy services in this phase.** The accepted risk is the same as for `OPENAI_API_KEY` already in the codebase.

### 3.3 Networking — New Port Entries

No new proxy ports needed. No `internalOnlyPorts` additions required for this phase.

---

## 4. Secrets

### 4.1 New sops Secrets Required

Three new secrets need declaring in `modules/secrets.nix` and encrypting in `secrets/neurosys.yaml`:

| Secret Name | sops key | Usage |
|---|---|---|
| `google-api-key` | `google-api-key` | GEMINI_API_KEY + GOOGLE_API_KEY for gemini-cli, opencode, pi |
| `xai-api-key` | `xai-api-key` | XAI_API_KEY for opencode, pi |
| `openrouter-api-key` | `openrouter-api-key` | OPENROUTER_API_KEY for opencode, pi |

**secrets.nix additions:**
```nix
sops.secrets."google-api-key" = { owner = "dangirsh"; };
sops.secrets."xai-api-key" = { owner = "dangirsh"; };
sops.secrets."openrouter-api-key" = { owner = "dangirsh"; };
```

**secrets/neurosys.yaml:** Add the three plaintext values, then re-encrypt with `sops --encrypt --in-place secrets/neurosys.yaml`.

### 4.2 bash.nix Additions

`home/bash.nix` exports API keys at shell startup from `/run/secrets`. Add:
```bash
export GOOGLE_API_KEY="$(cat /run/secrets/google-api-key 2>/dev/null)"
export GEMINI_API_KEY="$(cat /run/secrets/google-api-key 2>/dev/null)"
export XAI_API_KEY="$(cat /run/secrets/xai-api-key 2>/dev/null)"
export OPENROUTER_API_KEY="$(cat /run/secrets/openrouter-api-key 2>/dev/null)"
```

Note: `GEMINI_API_KEY` and `GOOGLE_API_KEY` both point to the same secret — gemini-cli accepts either, and opencode checks both.

---

## 5. Session Search (CASS)

### 5.1 Current State

CASS is already deployed (v0.1.64) as a systemd user timer (`cass-indexer.timer`, every 30 min). It indexes `~/.claude/projects` and `~/.codex/sessions`.

### 5.2 CASS Already Supports New Agents

CASS v0.1.53+ indexes all three new agents:
- **opencode:** scans `.opencode/` directories recursively from home (SQLite format)
- **gemini-cli:** scans `~/.gemini/tmp/` for `*_*.jsonl` files
- **pi:** scans `~/.pi/agent/sessions/` for JSONL files

**No CASS version update is needed** unless v0.1.64 is outdated. The existing `cass index --full` command will automatically pick up new session data as the new agents are used.

**Action item:** Verify the current CASS version (0.1.64) includes the pi and opencode connectors. If a newer version exists with additional fixes, update `packages/cass.nix` hash.

### 5.3 No Search Tool Change Required

The decision states "fast startup, CLI only, no MCP." CASS already satisfies this: `cass search <query> --json --limit 20` returns structured JSON with sub-60ms latency after indexing. No alternative search tool is needed.

---

## 6. Rust Beads CLI (beads_rust / br)

### 6.1 Current State

`packages/beads.nix` and `home/beads.nix` already declare beads_rust v0.1.19 as `br`. This was added in a recent phase. The package is pre-built (static musl binary), uses `autoPatchelfHook`, and installs as `br`.

**beads_rust is already done.** The phase decision to "add a Rust beads CLI" has already been completed. There is nothing to implement here.

### 6.2 Verification Needed

Confirm `br list --json` works correctly on the live system. The binary is v0.1.19 (latest as of 2026-02-23).

---

## 7. opencode Configuration File

### 7.1 Global opencode.json

To configure opencode's Anthropic base URL for proxy routing (for claw-swap and similar projects), a global `~/.config/opencode/opencode.json` must be deployed. This cannot be done per-launch via a simple env var (unlike `ANTHROPIC_BASE_URL` for claude-code).

**Two approaches:**

**Option A — home-manager file:** Declare the file in a new `home/opencode.nix`:
```nix
home.file.".config/opencode/opencode.json".text = builtins.toJSON {
  provider = {
    anthropic.options.baseURL = "http://127.0.0.1:9091";
  };
};
```
This makes **all** opencode invocations use the proxy for Anthropic, not just claw-swap ones.

**Option B — per-project opencode.json in claw-swap repo:** Place `opencode.json` in the claw-swap project root with the proxy baseURL. Non-claw-swap projects don't get the proxy config, so the real key is used directly.

**Recommendation: Option B** (per-project config in claw-swap). Consistent with the existing claw-swap-scoped proxy pattern. The global config should not force all projects through the proxy. The claw-swap repo is managed separately.

**For this phase:** No global opencode.json needed. The real `ANTHROPIC_API_KEY` injected by agent-spawn is sufficient for opencode in non-claw-swap projects. claw-swap gets its own opencode.json in the claw-swap repo (out of scope for neurosys config).

### 7.2 Pi Auth

Pi reads credentials from `~/.pi/agent/auth.json` (priority) OR env vars. Since we inject `ANTHROPIC_API_KEY` via agent-spawn, no auth.json configuration is required. Pi will use the env var automatically.

---

## 8. Module Placement

All additions fit cleanly into existing files — no new modules needed:

| What | Where |
|---|---|
| New agent packages | `modules/agent-compute.nix` — `environment.systemPackages` |
| agent-spawn script | `modules/agent-compute.nix` — extend agent arg parsing |
| New API keys (sops) | `modules/secrets.nix` + `secrets/neurosys.yaml` |
| New API key exports | `home/bash.nix` |
| New bwrap bind mounts | `modules/agent-compute.nix` — inside agent-spawn script |

The `home/beads.nix` and `packages/beads.nix` already exist and are complete. No changes needed there.

---

## 9. Risks and Gotchas

### 9.1 gemini-cli + bwrap Compatibility

gemini-cli has a known issue: it uses its own internal sandboxing (via `--sandbox` flag for its own subprocess execution). Inside bwrap, nested user namespaces are blocked (`--disable-userns`). gemini-cli may fail to spawn its sandboxed subprocesses.

**Mitigation:** Test `gemini` in sandboxed mode first. If it fails, the `--no-sandbox` flag in `agent-spawn` is the documented opt-out path (sandboxed at bwrap level is still more isolation than nothing).

**Also check:** gemini-cli's nixpkgs package removes `node-pty`, which means it won't have a proper PTY for interactive use. The llm-agents.nix version may or may not have this patch. Need to verify which package source is used.

### 9.2 opencode TUI in bwrap

opencode is a TUI (terminal UI). It requires a proper `TERM` and PTY. The agent-spawn bwrap command runs via `zmx run ... bash -c "$CMD"`, which zmx manages as a multiplexed session. This should provide a PTY. Verify opencode launches correctly with `zmx attach`.

### 9.3 pi Version Churn

`@mariozechner/pi-coding-agent` is actively developed. The npm hash in llm-agents.nix auto-updates daily. Since neurosys pins `llm-agents.nix` via flake.lock, it won't auto-update — but the hash in llm-agents.nix at lock time must be the current one. Run `nix flake update llm-agents` to pick up latest pi version.

### 9.4 CASS Indexer Scope

The CASS systemd service runs as `dangirsh` with `HOME=/home/dangirsh`. opencode stores sessions in `.opencode/` project subdirectories under `/data/projects/`. CASS scans recursively from home, but `/data/projects/` is not under `/home/dangirsh/`. CASS may miss opencode sessions.

**Mitigation:** Check whether CASS's opencode connector follows symlinks or scans only the home tree. If needed, set `CASS_OPENCODE_SEARCH_PATHS` or equivalent env var in the cass-indexer service. Alternatively, set opencode session dir to a location under `~` via config.

### 9.5 sops Secret Encoding

The three new API keys use sops with the existing `.sops.yaml` rules. To add: write plaintext values to `secrets/neurosys.yaml`, then `sops --encrypt --in-place`. The file must not be committed in plaintext — use the standard sops workflow.

---

## 10. Implementation Work Breakdown

1. **Secrets** — Add 3 sops declarations in `secrets.nix`, encrypt 3 new keys in `secrets/neurosys.yaml`
2. **bash.nix** — Export 4 new env vars (GOOGLE_API_KEY, GEMINI_API_KEY, XAI_API_KEY, OPENROUTER_API_KEY)
3. **agent-compute.nix (packages)** — Add `pkgs.opencode`, `pkgs.gemini-cli`, `pkgs.pi` to `environment.systemPackages`
4. **agent-compute.nix (agent-spawn)** — Extend argument parsing for 3 new agents, add new key reads before sandbox entry, inject new env vars in bwrap, add new bind mounts for agent config dirs, update usage/show-policy output
5. **Verify beads_rust** — `br list --json` works; no changes needed (already deployed)
6. **Verify CASS** — Confirm new agent session paths are indexed; check opencode path issue
7. **`nix flake check`** + build validation

**Estimated effort:** Medium. The agent-spawn script changes are the most involved (careful bash). Secrets setup is straightforward but requires actual API keys from the user.

---

## Sources

- [opencode package — MyNixOS](https://mynixos.com/nixpkgs/package/opencode)
- [gemini-cli package — MyNixOS](https://mynixos.com/nixpkgs/package/gemini-cli)
- [gemini-cli nixpkgs package.nix (nixos-25.11)](https://github.com/NixOS/nixpkgs/blob/nixos-25.11/pkgs/by-name/ge/gemini-cli/package.nix)
- [pi coding agent providers doc](https://github.com/badlogic/pi-mono/blob/main/packages/coding-agent/docs/providers.md)
- [pi-mono coding agent](https://github.com/badlogic/pi-mono/tree/main/packages/coding-agent)
- [llm-agents.nix README](https://github.com/numtide/llm-agents.nix/blob/main/README.md)
- [llm-agents.nix packages listing](https://github.com/numtide/llm-agents.nix/tree/main/packages)
- [opencode providers docs](https://opencode.ai/docs/providers/)
- [opencode config docs](https://opencode.ai/docs/config/)
- [GOOGLE_GEMINI_BASE_URL support PR](https://github.com/google-gemini/gemini-cli/pull/6380)
- [gemini-cli authentication docs](https://google-gemini.github.io/gemini-cli/docs/get-started/authentication.html)
- [CASS session search](https://github.com/Dicklesworthstone/coding_agent_session_search)
- [beads_rust releases](https://github.com/Dicklesworthstone/beads_rust/releases)
- [opencode build failure nixpkgs issue](https://github.com/NixOS/nixpkgs/issues/451228)
