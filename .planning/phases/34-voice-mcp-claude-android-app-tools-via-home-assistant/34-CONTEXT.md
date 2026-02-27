# Phase 34: Voice MCP — Claude Android app tools via Home Assistant - Context

**Gathered:** 2026-02-27
**Status:** Ready for planning

<domain>
## Phase Boundary

Configure HA's built-in MCP integration and expose it securely via Tailscale Serve HTTPS so the Claude Android app (voice mode) can control lights and query the CO2 sensor. Scope is limited to these two entity types for now. No new services, no public exposure.

</domain>

<decisions>
## Implementation Decisions

### Phone connectivity
- Tailscale is on the Android phone — Tailscale Serve is the right access model
- MCP endpoint at `https://neurosys.<tailnet>.ts.net` (Tailscale Serve HTTPS)
- No public internet exposure required

### Entity scope
- **Lights only** + **CO2 sensor only** — filtered, not all HA entities
- HA MCP `filter` config (by domain or entity ID) to restrict what's exposed
- If the CO2 sensor is not yet paired in HA, that's a prerequisite to document; MCP cannot surface it until it exists as a HA entity

### Tailscale Serve setup
- **Declarative NixOS** — a systemd service wraps `tailscale serve` persistently
- Survives reboots and deploys; not a one-time manual command
- Service must start after tailscaled and depend on Tailscale being authenticated

### HA token workflow
- **Manual UI → sops**: user creates a Long-Lived Access Token in HA Settings → Profile → Long-lived tokens
- Token then added via `sops secrets/neurosys.yaml`
- Plan should document this as a human-interactive step (checkpoint)

### Claude's Discretion
- Exact systemd service name and unit ordering for tailscale-serve wrapper
- Whether to use `tailscale serve` or `tailscale serve --bg` mode
- Exact HA MCP filter syntax (entity_id list vs domain filter)

</decisions>

<specifics>
## Specific Ideas

- CO2 prerequisite: if sensor isn't in HA yet, document it clearly as a pre-step in the plan (pair the device, verify it appears in HA entities, then proceed)
- The Claude Android app connects to a remote MCP server via Settings → MCP → Add remote server → paste the Tailscale Serve URL

</specifics>

<deferred>
## Deferred Ideas

- Expanding to other entity types (thermostats, switches, presence sensors) — Phase 34 is lights + CO2 only; add more via config change later
- Phase 35 (Unified Messaging Bridge) already queued separately

</deferred>

---

*Phase: 34-voice-mcp-claude-android-app-tools-via-home-assistant*
*Context gathered: 2026-02-27*
