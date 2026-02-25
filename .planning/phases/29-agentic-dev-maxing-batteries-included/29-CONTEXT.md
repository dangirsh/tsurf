# Phase 29: Agentic Dev Maxing — Batteries Included - Context

**Gathered:** 2026-02-25
**Status:** Ready for planning

<domain>
## Phase Boundary

Install the next tier of CLI coding agents (opencode, gemini-cli, pi), add API keys for three new providers (Google, xAI, OpenRouter), integrate all new agents with agent-spawn/bubblewrap sandbox, extend the secret proxy to cover new provider keys, and add two agent-optimized tooling pieces: session transcript search and a fast Rust beads CLI. Agent management UI (vibe-kanban and alternatives) is deferred to a new research phase.

</domain>

<decisions>
## Implementation Decisions

### Agent selection
- Include: **opencode** (nixpkgs), **gemini-cli** (nixpkgs), **pi** (Mario Zechner's `@mariozechner/pi-coding-agent` — NOT in nixpkgs, needs `buildNpmPackage`)
- **codex stays** — opencode does not replace it, both coexist
- Exclude this phase: goose-cli, aider-chat (not selected)

### Sandbox integration
- All three new agents (opencode, gemini-cli, pi) must be launchable via `agent-spawn` with full bubblewrap isolation — same treatment as claude-code and codex
- Extend the secret proxy pattern to new providers: gemini-cli gets `GEMINI_BASE_URL` pointing at proxy, opencode gets equivalent for its configured providers
- Claude decides which projects scope into proxy vs plain key injection (per-project, same pattern as claw-swap for Anthropic)

### API keys
- Add to sops-nix + bash.nix: `GOOGLE_API_KEY`, `XAI_API_KEY`, `OPENROUTER_API_KEY`
- Skip: `GROQ_API_KEY`, `MISTRAL_API_KEY` (covered by OpenRouter if needed)

### Session search
- Agents need to search past agent session transcripts (not code — CASS already covers code)
- Claude decides where sessions are logged and which search tool fits
- Optimize for agents calling it from the terminal; fast startup matters
- No MCP servers — CLI only

### Rust beads CLI
- Replace/complement current Python-based beads with a fast Rust CLI
- Must output clean JSON (`beads list --json`) for agent consumption
- No MCP — agents call the binary directly
- Claude evaluates rust-beads and alternatives; picks the most agent-ergonomic option

### No MCPs
- **Hard rule: avoid MCPs for all tooling in this phase** — CLI binaries only, agents parse JSON output

### Claude's Discretion
- Exact module file placement (likely `agent-compute.nix` for packages, new entries in `secrets.nix` and `bash.nix`)
- pi packaging details (buildNpmPackage derivation, hash, version pinning)
- Session transcript storage location and search tool choice
- Rust beads tool selection (rust-beads, write custom, or other)
- Proxy extension: which project patterns route through proxy for new provider keys

</decisions>

<specifics>
## Specific Ideas

- User mentioned `rust-beads` by name as a candidate for the Rust beads CLI — start there when evaluating
- Search tool must work for agents: fast, no startup overhead, clean output
- CASS already handles code indexing — session search is a separate, complementary concern

</specifics>

<deferred>
## Deferred Ideas

- **Agent management UI research** → new phase (Phase 30): browser + mobile interface for monitoring, commanding, and managing remote agents. Evaluate vibe-kanban (BloopAI) and alternatives. User wants: view agent status, send commands, mobile-accessible, ideally no additional infra complexity.
- **goose-cli** — in nixpkgs, good MCP support; defer to a later tooling pass
- **aider-chat** — in nixpkgs, good git integration; defer to a later tooling pass
- **Proxy expansion to all projects** — current proxy is scoped to claw-swap; full rollout is a separate concern (Phase 22 follow-up)

</deferred>

---

*Phase: 29-agentic-dev-maxing-batteries-included*
*Context gathered: 2026-02-25*
