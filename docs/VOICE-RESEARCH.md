# Voice Interface Research — Phase 56

@decision VOICE-56-01: LiveKit Agents selected as primary voice interface approach
@rationale: Localhost HA tool execution removes ~200-400ms per-call internet round-trip vs Vapi; full self-hosted control aligns with neurosys philosophy; `services.livekit` exists in nixpkgs.

## Executive Summary

Phase 56 evaluated five approaches for a low-latency, voice-first Home Assistant interface usable from Android and Mac.
A key constraint was confirmed first: Anthropic has no Realtime speech API as of March 2026, so all viable pipelines are `STT -> Claude Text API -> TTS`.
The top recommendation is **LiveKit Agents + Anthropic plugin** because it keeps the critical tool path local to neurosys.
Estimated TTFB for LiveKit is ~900-1400ms, within the 1-2s UX target for push-to-talk.
Ranked alternatives are **Pipecat+Daily** (#2) and **Vapi** (#3).
Phase 57 is scoped as two plans: infrastructure first, then application/frontend/testing.
Estimated implementation effort is ~4-6 days with no GPU requirement.

## Target UX

- Persona: "Jarvis" push-to-talk assistant
- Interaction: Multi-turn session with context continuity
- Latency target: 1-2s TTFB ceiling
- MVP domain: HA lights + sensor queries only
- Platforms: Android + Mac via browser-based UI (no custom mobile app required)

## Approach Evaluation

### 1. LiveKit Agents + Anthropic Plugin

**What it is**: Self-hosted WebRTC transport (LiveKit Server) + Python voice agent pipeline.

**Architecture**:

```text
User (Browser/Android/Mac) -> WebRTC -> LiveKit Server (self-hosted)
  -> LiveKit Agent (Python): Silero VAD -> Deepgram STT -> Claude Sonnet (tools) -> Cartesia TTS
  -> WebRTC -> User
Tools: direct HA localhost API calls or MCP
```

**HA integration depth**: Excellent (direct HA API or MCP)

**Latency profile**:

| Component | Latency |
|---|---:|
| VAD end-of-speech detection | 200-400ms |
| Deepgram STT (streaming) | 200-300ms |
| Claude Sonnet TTFT (streaming) | 400-600ms |
| Cartesia TTS TTFA | 40-90ms |
| WebRTC transport | <50ms |
| **Estimated total TTFB** | **~900-1400ms** |

**Android + Mac story**: Strong; LiveKit Web SDK works in browser on both.

**Complexity score**: Medium-High

**Verdict**: **Rank 1**. Best latency/control tradeoff for neurosys because tool execution stays local.

### 2. Pipecat + Daily

**What it is**: Self-hosted Python voice agent (Pipecat) with Daily as SaaS WebRTC transport.

**Architecture**:

```text
User (Browser/Android/Mac) -> Daily Room (cloud WebRTC)
  -> Pipecat Agent (Python): VAD -> Deepgram STT -> Claude Sonnet (tools) -> Cartesia TTS
  -> Daily Room -> User
```

**HA integration depth**: Excellent (direct HA API or MCP)

**Latency profile**:

| Component | Latency |
|---|---:|
| VAD + turn handling | 200-400ms |
| Deepgram STT | 200-300ms |
| Claude Sonnet TTFT | 400-600ms |
| Cartesia TTS TTFA | 40-90ms |
| Daily WebRTC transport | comparable to LiveKit |
| **Estimated total TTFB** | **~900-1400ms** |

**Android + Mac story**: Strong; browser + native SDKs.

**Complexity score**: Medium

**Verdict**: **Rank 2**. Similar quality to LiveKit, but transport is vendor-managed.

### 3. Vapi

**What it is**: Fully managed SaaS voice orchestration platform with MCP/custom tool options.

**Architecture**:

```text
User (Browser/Phone) -> Vapi Cloud (STT -> Claude -> TTS)
  -> MCP over internet -> neurosys-mcp -> HA -> back to Vapi -> User
```

**HA integration depth**: Good (MCP integration is indirect/internet-routed)

**Latency profile**:

| Component | Latency |
|---|---:|
| Base voice turn (no tool call) | ~800-1500ms |
| Internet-routed MCP tool call overhead | +200-400ms per call |
| **Estimated TTFB with tool use** | **~1000-2000ms** |

**Android + Mac story**: Excellent (browser + SDKs).

**Complexity score**: Low

**Verdict**: **Rank 3**. Fastest to ship, but internet tool hops penalize responsiveness for HA-heavy turns.

### 4. ClawdTalk/Telnyx

**What it is**: PSTN/phone-call interface routing through Telnyx/ClawdTalk into OpenClaw gateway.

**Architecture**:

```text
User phone -> PSTN/Telnyx voice loop -> ClawdTalk Server -> OpenClaw Gateway -> Claude/tools -> TTS
```

**HA integration depth**: Indirect (requires OpenClaw tool wiring to HA/MCP)

**Latency profile**:

| Component | Latency |
|---|---:|
| Telnyx voice loop | sub-200ms (claimed) |
| LLM + tool execution dominates | variable |
| **Estimated total TTFB** | **~800-1500ms** |

**Android + Mac story**: Universal via phone, but weaker for desktop-native workflow.

**Complexity score**: Low-Medium

**Verdict**: Supplementary channel candidate, not primary Jarvis UX.

### 5. Claude App Voice + MCP

**What it is**: Native Claude voice mode combined with remote MCP connectors.

**Architecture**:

```text
User -> Claude app voice mode -> Claude -> MCP connector -> neurosys-mcp -> HA
```

**HA integration depth**: Excellent if enabled

**Latency profile**:

| Component | Latency |
|---|---:|
| Voice + tools end-to-end | unknown |

**Android + Mac story**: Strong app coverage.

**Complexity score**: Zero implementation effort

**Verdict**: **Blocked** as of March 2026 for voice+MCP integration; monitor Anthropic updates.

## Comparison Matrix

| Criterion | LiveKit Agents | Pipecat+Daily | Vapi | ClawdTalk/Telnyx | Claude App+MCP |
|---|---|---|---|---|---|
| HA integration depth | Excellent (direct API/MCP) | Excellent (direct API/MCP) | Good (MCP via internet) | Indirect (via OpenClaw) | Excellent (MCP) |
| Estimated TTFB | 900-1400ms | 900-1400ms | 1000-2000ms | 800-1500ms | Unknown |
| Android support | Browser + native SDK | Browser + native SDK | Browser + phone | Phone only | Native app |
| Mac support | Browser + native SDK | Browser + native SDK | Browser | Phone/app only | Native app |
| Multi-turn context | Yes (WebRTC session) | Yes (WebRTC session) | Yes (call session) | Yes (OpenClaw session) | Yes (conversation) |
| Self-hosted control | Full (server+agent) | Partial (agent only) | None (cloud orchestration) | Partial (client+OpenClaw) | None (Anthropic app) |
| NixOS packaging | Medium (`services.livekit` exists) | Medium (no native module) | Low (API only) | Low (npm client) | N/A |
| Monthly cost (est.) | ~$5-15 (STT+TTS API) | ~$5-15 + Daily fees | ~$20-50 (per-min) | ~$0-30 | $0 (Claude subscription) |
| New sops secrets | 3 | 3 | 1 | 1 | 0 |
| Complexity | Medium-High | Medium | Low | Low-Medium | Zero (blocked) |
| Currently working | Yes | Yes | Yes | Yes | No (blocked) |

## Ranked Top 3

1. **LiveKit Agents (Rank 1)**: Best end-to-end fit for neurosys constraints: self-hosted WebRTC, localhost tool calls, predictable latency envelope, and nixpkgs module availability.
Risk: plugin/packaging integration details (including known Opus 4.6 plugin issue; Sonnet path remains viable).

2. **Pipecat+Daily (Rank 2)**: Comparable pipeline quality with lower infra burden because Daily handles transport.
Risk: transport vendor dependency and async tool-calling complexity for tool-heavy turns.

3. **Vapi (Rank 3)**: Lowest implementation complexity and quick path to MVP.
Risk: internet-routed tool calls add 200-400ms each, plus higher per-minute spend and orchestration lock-in.

## STT/TTS Provider Recommendations

All viable options still depend on `STT -> Claude -> TTS`, so provider choice is cross-cutting.

### STT

- **Recommended**: Deepgram Nova-3 (streaming, ~200-300ms, ~$0.0077/min)
- Why: low latency, mature ecosystem, first-party plugin support in LiveKit/Pipecat

### TTS

- **Recommended**: Cartesia Sonic-3 (TTFA ~40-90ms, ~$0.03/min)
- Why: best time-to-first-audio in this evaluation, strong plugin support

### Personal-use Cost Estimate

Assuming 30 min/day:
- Deepgram STT: ~$7/mo
- Cartesia TTS: ~$27/mo
- Claude Sonnet usage: ~$5-15/mo
- Total: roughly ~$40-50/mo

## Infrastructure Delta for LiveKit Agents

### New NixOS Services

| Service | Port(s) | Access | Notes |
|---|---|---|---|
| `livekit-server` | 7880, 7881, UDP 50000-60000 | Tailnet/Funnel signaling | `services.livekit` in nixpkgs |
| `neurosys-voice-agent` | N/A | Internal only | Python systemd service |
| Voice web frontend | static | Tailnet/nginx | LiveKit Web SDK UI |

### New Ports (`networking.nix`)

- `7880` (`livekit-server-signaling`)
- `7881` (`livekit-server-rtc-tcp`)
- UDP `50000-60000` for WebRTC media (tailnet/TURN strategy required)

### New sops Secrets

| Secret | Purpose |
|---|---|
| `livekit-api-key` | LiveKit auth |
| `livekit-api-secret` | LiveKit auth |
| `deepgram-api-key` | STT API auth |
| `cartesia-api-key` | TTS API auth |

Reused secrets/infrastructure: `anthropic-api-key`, `ha-token`, existing Tailscale/TLS patterns.

### New NixOS Modules

| Module | Responsibility |
|---|---|
| `modules/livekit.nix` | LiveKit Server config + service |
| `modules/voice-agent.nix` | Voice agent service + env wiring |

### New Python Package

- `packages/neurosys-voice-agent.nix`
- Dependencies: `livekit-agents`, `livekit-plugins-anthropic`, `livekit-plugins-silero`, `livekit-plugins-deepgram`, `livekit-plugins-cartesia`

### SSL/TLS Approach

- Preferred for anywhere access: Tailscale Funnel-backed signaling endpoint
- Simpler first-step: tailnet-only Tailscale Serve
- Existing private nginx TLS path remains an alternative

### Existing Infrastructure Reused

- Home Assistant local API (`127.0.0.1:8123`)
- Existing sops key flow
- Existing deploy/test patterns from neurosys-mcp packaging

## Voice-Optimized Tool Set

Suggested Phase 57 tool wrappers for spoken UX:

- `control_light(room, action, brightness?, color_temp?)`
- `get_sensor(name)`
- `set_scene(scene_name)`
- `list_rooms()`
- `get_room_status(room)`

Rationale: concise spoken responses and direct HA call paths outperform raw MCP JSON tool surfaces for voice interaction.

## Phase 57 Skeleton

### Plan 57-01: Infrastructure

Scope:
- Add `modules/livekit.nix`
- Add `packages/neurosys-voice-agent.nix`
- Add `modules/voice-agent.nix`
- Add new secrets and port declarations
- Stand up TLS/signaling path for LiveKit

Verification:
- `nix flake check`
- LiveKit server starts
- Agent joins room

### Plan 57-02: Application + Frontend + Testing

Scope:
- Implement `src/neurosys-voice-agent/agent.py`
- Implement voice-optimized HA tools
- Add static web frontend (push-to-talk)
- Add end-to-end voice test path

Verification:
- Voice command like "turn on the bedroom lights" executes and confirms by voice
- Measure and document real TTFB

### Effort / File Impact / Risks

- Effort: ~4-6 days total
- Expected new files: ~8-10
- Main risks: PyPI packaging details, WebRTC TLS/networking setup, plugin compatibility edges

## Open Questions

1. LiveKit Cloud vs self-hosted: self-hosted is preferred for neurosys control and architecture alignment.
2. Tailnet-only vs public access: start tailnet-only, add Funnel when needed.
3. Public vs private overlay placement: likely public module/package + private secrets, same as MCP pattern.
4. WebRTC UDP range handling: confirm chosen transport path (direct tailnet UDP vs TURN/Funnel posture).

## Sources

- [LiveKit Agents Framework](https://github.com/livekit/agents)
- [LiveKit Anthropic Plugin](https://docs.livekit.io/agents/integrations/llm/anthropic/)
- [LiveKit Self-Hosting](https://docs.livekit.io/transport/self-hosting/deployment/)
- [LiveKit MCP Integration Example](https://github.com/livekit-examples/basic-mcp)
- [LiveKit Agent Frontends](https://docs.livekit.io/frontends/)
- [LiveKit Anthropic Plugin PyPI](https://pypi.org/project/livekit-plugins-anthropic/)
- [LiveKit Claude Opus 4.6 Issue](https://github.com/livekit/agents/issues/4907)
- [Pipecat Framework](https://github.com/pipecat-ai/pipecat)
- [Pipecat Anthropic Integration](https://docs.pipecat.ai/server/services/llm/anthropic)
- [Daily + Anthropic Partnership](https://www.dailybots.ai/partners/anthropic/)
- [Pipecat RTVI Protocol](https://docs.pipecat.ai/server/frameworks/rtvi/introduction)
- [Vapi MCP Integration](https://docs.vapi.ai/tools/mcp)
- [Vapi Custom Tools](https://docs.vapi.ai/tools/custom-tools)
- [Vapi Pricing](https://vapi.ai/pricing)
- [Vapi Latency Optimization](https://www.assemblyai.com/blog/how-to-build-lowest-latency-voice-agent-vapi)
- [ClawdTalk Client](https://github.com/team-telnyx/clawdtalk-client)
- [ClawdTalk Product Page](https://clawdtalk.com/)
- [Telnyx ClawdTalk Announcement](https://www.globenewswire.com/news-release/2026/02/09/3234651/0/en/Telnyx-Introduces-ClawdTalk-Giving-AI-Agents-a-Voice.html)
- [Claude Voice Mode Documentation](https://support.claude.com/en/articles/11101966-using-voice-mode)
- [Claude Voice Features Analysis](https://www.datastudios.org/post/claude-voice-features-explained-current-status-and-upcoming-real-time-updates)
- [Anthropic Advanced Tool Use](https://www.anthropic.com/engineering/advanced-tool-use)
- [Claude MCP Connectors](https://support.claude.com/en/articles/11503834-building-custom-connectors-via-remote-mcp-servers)
- [Deepgram STT Pricing](https://deepgram.com/pricing)
- [Deepgram vs OpenAI vs Google STT](https://deepgram.com/learn/deepgram-vs-openai-vs-google-stt-accuracy-latency-price-compared)
- [Cartesia Sonic-3 TTS](https://cartesia.ai/product/python-text-to-speech-api-tts)
- [Cartesia Pricing](https://cartesia.ai/pricing)
- [Best TTS APIs 2026 Benchmarks](https://inworld.ai/resources/best-voice-ai-tts-apis-for-real-time-voice-agents-2026-benchmarks)
- [Self-Hosted vs Vapi Cost Analysis](https://blog.dograh.com/self-hosted-voice-agents-vs-vapi-real-cost-analysis-tco-break-even/)
- [Claude Uses ElevenLabs for TTS](https://the-decoder.com/anthropics-claude-uses-elevenlabs-technology-for-speech-features-rather-than-an-in-house-model/)
- [VoiceMode MCP for Claude Code](https://getvoicemode.com/)
- [Hume AI + Anthropic](https://www.hume.ai/blog/hume-anthropic-claude-voice-interactions)
- [Twilio + Anthropic ConversationRelay](https://www.twilio.com/en-us/blog/integrate-anthropic-twilio-voice-using-conversationrelay)
- [NixOS LiveKit Service](https://mynixos.com/nixpkgs/option/services.livekit.keyFile)
