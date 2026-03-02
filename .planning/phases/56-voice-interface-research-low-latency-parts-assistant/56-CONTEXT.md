# Phase 56: Voice Interface Research — Low-Latency Parts Assistant - Context

**Gathered:** 2026-03-02
**Status:** Ready for planning

<domain>
## Phase Boundary

Research and compare approaches for a voice-controlled interface to neurosys, focused on HA control (lights, sensors) as the MVP. Evaluate all major candidates (Claude Android+MCP, ClawdTalk/Telnyx, WebRTC pipelines, SaaS voice platforms). Produce a ranked top-3 with justification, high-level neurosys infrastructure delta, and a Phase 57 approach+complexity sketch.

Creating voice commands, implementing anything, or building agent management tools is out of scope — this phase produces a research document only.

</domain>

<decisions>
## Implementation Decisions

### Evaluation priority
- Parts/HA integration depth is the primary filter — approaches that can't expose HA tools cleanly are disqualified
- Latency is secondary: 1-2 seconds TTFB is acceptable; above 2 seconds feels broken
- Simplicity is a tiebreaker, not a primary criterion

### Target UX — Jarvis, not a chatbot
- Push-to-talk activation (not always-on wake word)
- Full multi-turn sessions with persistent context — "deploy this... actually check logs first" must work
- The north star is commanding neurosys entirely by voice; MVP is HA control only
- 1-2 second TTFB is the latency ceiling for "feels natural"

### MVP scope — HA tools only
- Day-one must-have: lights control and sensor queries (CO2, temperature) via HA
- Existing neurosys-mcp tools (Phase 45: 5 HA tools + 5 Matrix tools) are the tool surface for MVP
- Agent management by voice is explicitly deferred to a future phase
- System operations (deploy, run tests) are explicitly deferred
- No custom Android app — existing apps (Claude, browser, phone dialer) only

### Platform
- Android and Mac equally important — winning approach must work on both
- No custom Android app development in scope

### Research scope
- Claude Android voice+MCP: **known blocked** (Anthropic-side issue prevents MCP connection) — document the blocker, evaluate what would unblock it, do not treat as a working baseline
- ClawdTalk/Telnyx PSTN pipeline: include — phone-call UX is interesting to evaluate even with push-to-talk targets
- SaaS voice platforms (Vapi, Bland AI): include and evaluate fairly — acceptable to recommend if they win on simplicity+integration
- WebRTC approaches: medium-depth evaluation of both LiveKit Agents and Daily RTVI
- Hardware constraint: neurosys host has no dedicated GPU — rules out local heavy STT/TTS models (Whisper large, local TTS); CPU-only or cloud STT/TTS required

### Research deliverable shape
- **Ranked top 3** approaches (not single winner) with clear justification
- Each approach: what it is, how it connects to HA/Parts, latency profile, complexity score, Android+Mac story, neurosys infra requirements
- High-level neurosys infrastructure delta for the top-ranked approach: new ports, sops secrets, NixOS modules needed (not full module specs)
- Phase 57 skeleton: approach + key components + estimated complexity (not a full task breakdown)

### Claude's Discretion
- Tool inventory detail for Phase 57 (which tools to add and how to structure them)
- Complexity scoring methodology for approach comparison
- Whether to test Claude Android voice mode empirically or document theoretically (blocked anyway)
- How to handle the PSTN vs app-native latency comparison (apples-to-oranges)

</decisions>

<specifics>
## Specific Ideas

- "Jarvis" is the UX reference — commanding neurosys entirely by voice, not just querying it
- The Phase 45 MCP server (FastMCP, Streamable HTTP, OAuth 2.1, Tailscale Funnel port 8443) is the existing tool surface; Phase 56 research should identify whether it needs extension or replacement
- ClawdTalk pattern from context: Phone → Telnyx STT → ClawdTalk Server → WebSocket → OpenClaw Gateway → Agent → TTS → Phone

</specifics>

<deferred>
## Deferred Ideas

- Agent management by voice ("spin up an agent to fix X", "what's agent Y working on?") — future phase after MVP voice works
- System operations by voice (deploy, run tests, service health checks) — future phase
- Always-on wake word activation — deferred; push-to-talk is MVP
- Custom Android app development — out of scope; existing apps only for Phase 57
- Full Jarvis agent delegation (multi-step coding tasks via voice) — longer-term vision, not Phase 57

</deferred>

---

*Phase: 56-voice-interface-research-low-latency-parts-assistant*
*Context gathered: 2026-03-02*
