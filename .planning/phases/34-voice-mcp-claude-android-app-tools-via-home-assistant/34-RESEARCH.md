# Phase 34: Voice MCP — Research

**Question:** What do I need to know to PLAN this phase well?

---

## 1. Existing Codebase State

### Home Assistant Module (`modules/home-assistant.nix`)
- HA runs as a native NixOS service (not Docker) on port 8123, bound to `0.0.0.0`.
- Access is Tailscale-only via `trustedInterfaces = ["tailscale0"]` in `networking.nix`.
- `extraComponents` currently: `["hue" "esphome"]`.
- ESPHome also running on port 6052 (Tailscale-only).
- Config uses `default_config = {};` which loads 23 default integrations (MCP server is NOT one of them).
- Automations loaded via `!include config-repo/automations.yaml`.

### HA Version
- nixpkgs nixos-25.11 ships **Home Assistant 2025.11.3**.
- The `mcp_server` component is available in nixpkgs (`availableComponents` confirms both `mcp_server` and `mcp` exist).
- MCP Server integration was introduced in **HA 2025.2**, so 2025.11.3 is well past the requirement.

### Secrets
- `ha-token` already exists in `secrets/neurosys.yaml` (sops-encrypted).
- It is already declared in the sops secrets config (confirmed via `nix eval`).
- Recent commits (81efc66, e511614) updated this token to a fresh long-lived access token.
- **No new secret creation needed** -- the `ha-token` already exists and is current.

### Tailscale
- Tailscale is configured declaratively in `networking.nix` with `authKeyFile` from sops.
- `/var/lib/tailscale` is persisted via impermanence (state survives reboots).
- `trustedInterfaces = ["tailscale0"]` grants full access to all services binding `0.0.0.0`.
- No existing `tailscale serve` configuration anywhere in the codebase.

### Networking/Ports
- `internalOnlyPorts` in `networking.nix` already includes `"8123" = "home-assistant"`.
- Port 8123 is NOT in `allowedTCPPorts` (build-time assertion enforces this).
- Tailscale Serve on port 443 uses Tailscale's own TLS cert management -- no new ports are opened on the public firewall.

### Module Organization
- `modules/default.nix` imports all modules. Currently no tailscale-serve module.
- Module naming pattern: one file per concern (e.g., `spacebot.nix`, `secret-proxy.nix`).
- Systemd service patterns in the codebase: see `automaton.nix` for a full example with `after`, `wants`, `wantedBy`, sops template, and hardening.

### CO2 Sensor Status
- No CO2 sensor configuration exists in the codebase (no references to co2, scd, air quality sensors in any NixOS module).
- The CONTEXT.md correctly flags this: "If the CO2 sensor is not yet paired in HA, that's a prerequisite to document."
- ESPHome is running, so an ESPHome-based CO2 sensor (e.g., SCD30, SCD40, MH-Z19) can be paired via the ESPHome dashboard.
- **This is a human-interactive prerequisite**: the CO2 device must be physically connected, configured in ESPHome, and appear as a HA entity before MCP can expose it.

---

## 2. HA MCP Server Integration

### How It Works
- **Endpoint**: `/api/mcp` on the HA HTTP server (port 8123).
- **Transport**: Streamable HTTP (stateless). This is the modern MCP transport protocol.
- **Authentication**: Supports both OAuth (IndieAuth) and long-lived access tokens.
  - Long-lived tokens use `Authorization: Bearer <token>` header.
  - OAuth: Client ID = base URL of redirect URI; client secret ignored by HA.
- **Capabilities**: Exposes Tools and Prompts. Does NOT support Resources, Sampling, or Notifications.

### Setup Steps (UI-only -- NOT YAML-configurable)
The MCP Server integration is a **config flow integration** (UI-only). It CANNOT be enabled via `configuration.yaml` or the NixOS `services.home-assistant.config` attribute. The setup steps are:
1. Navigate to **Settings > Devices & Services** in the HA web UI.
2. Click **Add Integration**.
3. Search for **"Model Context Protocol Server"**.
4. Follow the on-screen prompts.

**Implication for the plan**: This is a human-interactive step that must be documented as a checkpoint. The NixOS config can add `mcp_server` to `extraComponents` (ensures the Python package is available), but the integration must be activated through the HA UI after deploy.

### Entity Filtering
- The MCP server exposes **only entities that are explicitly exposed** via HA's "Exposed Entities" page.
- This is the **same exposure mechanism** used by Assist, Google Assistant, and Alexa.
- Path: **Settings > Voice Assistants > Expose tab**.
- Entities are exposed/unexposed individually (no bulk domain filter in the UI currently).
- For Phase 34 scope (lights + CO2 sensor): expose only `light.*` entities and the specific CO2 sensor entity.

**Implication for the plan**: Entity filtering is UI-based, not YAML-based. The plan must document another human-interactive step: go to the expose page, expose only the lights and CO2 sensor entity, and verify they appear in the MCP server's tool list.

### NixOS `extraComponents` Addition
- Add `"mcp_server"` to the `extraComponents` list in `home-assistant.nix`.
- This ensures the Python package for the MCP server integration is included in the HA derivation.
- Without this, the integration won't appear in the HA UI's "Add Integration" search.

---

## 3. Tailscale Serve Configuration

### How `tailscale serve` Works
- **Command**: `tailscale serve --bg --https=443 http://127.0.0.1:8123`
- This creates a TLS-terminated HTTPS reverse proxy from `https://neurosys.<tailnet>.ts.net:443` to `http://127.0.0.1:8123`.
- Tailscale Serve auto-provisions Let's Encrypt TLS certificates (no manual cert management).
- The `--bg` flag makes the serve config persistent -- it survives reboots and `tailscale down/up` cycles.
- The config is stored in Tailscale's state directory (`/var/lib/tailscale`), which is already persisted via impermanence.
- **Only `http://127.0.0.1` is supported** as a proxy backend (no other IPs).

### Persistence Behavior
- With `--bg`: runs persistently until explicitly disabled with `tailscale serve off` or `tailscale serve reset`.
- Survives reboots automatically (config stored in Tailscale state / control plane).
- This means a one-time `tailscale serve --bg` command is technically sufficient.

### NixOS Declarative Approach
Despite `--bg` persistence, a **declarative systemd wrapper** is the right pattern for NixOS:
- Ensures the serve config is always applied on every deploy (not just the first time).
- Idempotent: running `tailscale serve --bg` when the same config is already active is a no-op.
- Service ordering: must start **after** `tailscaled.service` and after Tailscale is authenticated.
- Recommended service type: `oneshot` with `RemainAfterExit=true`.

**Recommended systemd service definition:**
```nix
systemd.services.tailscale-serve-ha = {
  description = "Tailscale Serve: HTTPS proxy to Home Assistant";
  after = [ "tailscaled.service" ];
  wants = [ "tailscaled.service" ];
  wantedBy = [ "multi-user.target" ];

  serviceConfig = {
    Type = "oneshot";
    RemainAfterExit = true;
    ExecStart = "${pkgs.tailscale}/bin/tailscale serve --bg --https=443 http://127.0.0.1:8123";
    ExecStop = "${pkgs.tailscale}/bin/tailscale serve off";
  };
};
```

**Key design considerations:**
- Service name: `tailscale-serve-ha` (descriptive, scoped to HA).
- The `ExecStop` with `tailscale serve off` ensures clean teardown if the service is stopped (though in practice this service should always be running).
- **Race condition risk**: `tailscaled.service` may report as started before Tailscale is fully authenticated. A retry/wait mechanism (or `ExecStartPre` with a `tailscale status --json` check) may be needed.
- **Alternative**: `tailscale serve --bg` without systemd wrapping works because `--bg` persists. But declarative NixOS convention strongly favors systemd management.

### Tailscale Serve vs. Tailscale Funnel
- **Serve** = accessible only to Tailscale peers (tailnet-only). This is what we want.
- **Funnel** = accessible from the public internet. NOT what we want.
- The CONTEXT.md correctly specifies Serve, not Funnel.

### Where to Put This in the NixOS Config
Two options:
1. **Add to `home-assistant.nix`**: keeps the serve config co-located with the HA service it proxies. This is the simpler choice since the serve config is specifically for HA.
2. **New `tailscale-serve.nix` module**: more extensible if future services need Tailscale Serve too. But YAGNI per project conventions.

**Recommendation**: Add to `home-assistant.nix` (no new module needed for <20 lines of config).

---

## 4. HA `trusted_proxies` Configuration

### Why It's Needed
When Tailscale Serve proxies requests to HA, the requests come from `127.0.0.1` (localhost). HA needs to trust this proxy to correctly parse `X-Forwarded-For` headers and avoid 400 Bad Request errors.

### NixOS Config Change
Add to the existing `http` block in `home-assistant.nix`:
```nix
http = {
  server_host = "0.0.0.0";
  server_port = 8123;
  use_x_forwarded_for = true;
  trusted_proxies = [ "127.0.0.1" ];
};
```

**Risk**: This is a declarative config change that takes effect on the next `nixos-rebuild switch`. It should not break existing Tailscale-direct access (which doesn't go through a proxy).

---

## 5. Claude Android App MCP Connector Setup

### How Remote MCP Works on Claude Mobile
- Remote MCP servers are configured via **claude.ai** (web), NOT directly from the Android app.
- Path: **Settings > Connectors > Add Custom Connector**.
- Enter connector name and URL.
- Connectors configured on claude.ai **automatically sync** to the Claude Android and iOS apps.
- Users cannot add or modify connectors from mobile.

### Authentication Options
Claude supports:
1. **Authless** -- no auth required (not applicable here).
2. **OAuth** -- Claude supports Dynamic Client Registration (DCR) and custom client ID/secret. HA supports OAuth via IndieAuth. Claude's OAuth callback URL: `https://claude.ai/api/mcp/auth_callback`.
3. **Bearer token** -- Claude can pass `authorization_token` in the server config.

### Recommended Auth Approach
Two viable paths:

**Option A: OAuth (HA's built-in IndieAuth)**
- Claude.ai initiates OAuth flow with HA.
- HA presents its login page, user authenticates.
- Claude receives an access token.
- Pro: No manual token management. Token refresh handled automatically.
- Con: Requires the HA instance to be reachable from claude.ai's servers at connector setup time. Since HA is only on Tailscale (no public internet), OAuth flow may not work unless the user's browser can reach HA (which it can if the user's browser is on the tailnet).
- **Critical question**: Does the OAuth flow happen in the user's browser (which IS on the tailnet via Tailscale on the phone/laptop) or server-side from claude.ai (which is NOT on the tailnet)?

**Option B: Long-lived access token (Bearer)**
- Create a long-lived token in HA UI.
- Add it as Bearer token when configuring the connector on claude.ai.
- Pro: Simple, no OAuth flow needed. Works regardless of connectivity between claude.ai servers and HA.
- Con: Token must be manually rotated. Token is stored by Anthropic's connector infrastructure.

**Recommendation**: Start with **Option B (Bearer token)** because:
1. The HA instance is Tailscale-only -- OAuth's redirect flow may fail if claude.ai's servers need to reach HA directly.
2. The `ha-token` already exists in sops.
3. Simpler for Phase 34 scope.

### MCP URL Format
The connector URL will be:
```
https://neurosys.<tailnet>.ts.net/api/mcp
```
- Tailscale Serve provides the `https://neurosys.<tailnet>.ts.net` endpoint on port 443.
- HA's MCP server integration serves at `/api/mcp`.
- The user must replace `<tailnet>` with their actual tailnet name.

### Transport Protocol
- Claude supports both **Streamable HTTP** and **SSE** transports.
- HA's MCP server uses **Streamable HTTP** (stateless).
- These are compatible. SSE support may be deprecated in Claude soon; Streamable HTTP is the future.

### Key Limitation for Mobile
- The Claude Android app must be on the Tailscale network (Tailscale app installed and connected) to reach the MCP endpoint.
- If Tailscale is disconnected on the phone, MCP calls will fail (expected behavior for tailnet-only services).

---

## 6. End-to-End Data Flow

```
Claude Android App (voice: "turn off the lights")
  |
  | HTTPS (Streamable HTTP + Bearer token)
  v
Tailscale Serve (port 443, TLS terminated)
  |
  | HTTP (X-Forwarded-For: <phone tailscale IP>)
  v
Home Assistant (127.0.0.1:8123, /api/mcp)
  |
  | Internal: exposed entity lookup
  v
Hue Bridge / ESPHome CO2 Sensor
  |
  v
Response -> Claude -> Voice output to user
```

---

## 7. Implementation Steps (Ordered)

### Prerequisites (human-interactive)
1. **CO2 sensor**: Verify the CO2 sensor exists as a HA entity. If not, pair it via ESPHome dashboard or Hue bridge. This is a physical device + HA integration step.
2. **HA MCP Server integration**: Enable via HA web UI (Settings > Devices & Services > Add Integration > Model Context Protocol Server). This cannot be automated via NixOS config.
3. **Expose entities**: Go to Settings > Voice Assistants > Expose tab. Expose only the light entities and CO2 sensor entity.

### NixOS Config Changes
4. **`modules/home-assistant.nix`**:
   - Add `"mcp_server"` to `extraComponents`.
   - Add `use_x_forwarded_for = true` and `trusted_proxies = ["127.0.0.1"]` to the `http` block.
   - Add a systemd `tailscale-serve-ha` oneshot service.
5. **`modules/networking.nix`**: No changes needed. Port 443 is already in `allowedTCPPorts` (for nginx). Tailscale Serve uses Tailscale's own port, not the public port 443. No new `internalOnlyPorts` entry needed because Tailscale Serve doesn't open a new listening port on the host network stack -- it's handled by the Tailscale daemon.

### Manual Post-Deploy Steps
6. **Deploy**: `scripts/deploy.sh` to neurosys.
7. **Verify Tailscale Serve**: `ssh root@neurosys tailscale serve status` -- should show HTTPS 443 -> 127.0.0.1:8123.
8. **Enable MCP Server integration** in HA UI (if not already done in prerequisites).
9. **Expose entities** in HA UI (if not already done in prerequisites).
10. **Configure Claude connector**: On claude.ai, Settings > Connectors > Add Custom Connector. Name: "Home Assistant". URL: `https://neurosys.<tailnet>.ts.net/api/mcp`. Auth: Bearer token (paste the HA long-lived access token).
11. **Test from Android**: Open Claude app, voice mode. Say "turn off the lights" and "what's the CO2 level?"

---

## 8. Risks and Unknowns

### Risk 1: Tailscale Serve startup race condition
- `tailscaled.service` may report ready before Tailscale is fully authenticated to the tailnet.
- The `tailscale serve --bg` command may fail if called before authentication completes.
- **Mitigation**: Add `ExecStartPre` with a wait loop (`tailscale status --json` until state is "Running") or use `Restart=on-failure` with a short `RestartSec`.

### Risk 2: OAuth vs Bearer token for Claude connector
- If Claude's connector setup requires an OAuth flow that goes server-side (not browser-side), it won't work with a Tailscale-only HA instance.
- **Mitigation**: Use Bearer token auth (Option B). The `ha-token` already exists.

### Risk 3: MCP integration is UI-only
- The MCP Server integration cannot be declaratively enabled in NixOS config.
- If HA's state is lost (e.g., reinstall without restoring `/var/lib/hass`), the MCP integration must be manually re-enabled.
- **Mitigation**: Document this clearly. `/var/lib/hass` is already persisted via impermanence and backed up via restic.

### Risk 4: CO2 sensor may not exist yet
- No CO2 sensor entity exists in the current HA configuration.
- MCP can only expose entities that exist.
- **Mitigation**: Document as a prerequisite checkpoint. The plan should handle this gracefully -- lights work immediately, CO2 requires the sensor to be paired first.

### Risk 5: Claude connector + Tailscale-only endpoint
- When configuring the connector on claude.ai, the user's browser must be on the tailnet to reach the HA MCP endpoint (for the OAuth flow). For Bearer token auth, the browser may not need to reach HA during setup.
- At runtime on the phone, Tailscale must be connected for MCP calls to work.
- **Mitigation**: Document that Tailscale must be active on the phone. This is already stated in the CONTEXT.md.

### Unknown 1: Does `tailscale serve` on port 443 conflict with nginx?
- nginx is already listening on port 443 on the public interface (for dangirsh.org, claw-swap.com).
- Tailscale Serve listens on the Tailscale interface only (the `tailscale0` virtual NIC), not on `0.0.0.0:443`.
- **Expected**: No conflict. Tailscale Serve and nginx operate on different network interfaces.
- **Verify**: Test after deploy that both nginx HTTPS and Tailscale Serve HTTPS work simultaneously.

### Unknown 2: Exact tailnet domain name
- The MCP URL needs the actual tailnet domain: `neurosys.<tailnet-name>.ts.net`.
- The tailnet name is user-specific and not stored in the NixOS config.
- **Verify**: Run `tailscale status` on neurosys to get the full FQDN.

---

## 9. Files to Modify

| File | Change |
|------|--------|
| `modules/home-assistant.nix` | Add `"mcp_server"` to `extraComponents`; add `trusted_proxies` and `use_x_forwarded_for` to `http` block; add `tailscale-serve-ha` systemd service |
| `secrets/neurosys.yaml` | No change needed (`ha-token` already exists) |
| `modules/networking.nix` | No change needed (no new ports exposed) |
| `modules/default.nix` | No change needed (no new module file) |

---

## 10. Validation Criteria

1. `nix flake check` passes after config changes.
2. `tailscale serve status` on neurosys shows HTTPS 443 proxying to 127.0.0.1:8123.
3. `curl -s -H "Authorization: Bearer <token>" https://neurosys.<tailnet>.ts.net/api/mcp` returns a valid MCP response (not 401 or 404).
4. Claude Android app can toggle a light via voice.
5. Claude Android app can read the CO2 sensor value via voice (contingent on sensor being paired).

---

## Sources

- [Home Assistant MCP Server Integration](https://www.home-assistant.io/integrations/mcp_server/)
- [Home Assistant MCP Client Integration](https://www.home-assistant.io/integrations/mcp/)
- [Tailscale Serve CLI Reference](https://tailscale.com/docs/reference/tailscale-cli/serve)
- [Tailscale Serve Examples](https://tailscale.com/kb/1313/serve-examples)
- [Building Custom Connectors via Remote MCP Servers (Claude)](https://support.claude.com/en/articles/11503834-building-custom-connectors-via-remote-mcp-servers)
- [Remote MCP on Claude iOS/Android](https://dev.to/zhizhiarv/how-to-set-up-remote-mcp-on-claude-iosandroid-mobile-apps-3ce3)
- [Home Assistant Default Config](https://www.home-assistant.io/integrations/default_config/)
- [NixOS Tailscale Wiki](https://wiki.nixos.org/wiki/Tailscale)
- [Exposing Entities to Assist](https://www.home-assistant.io/voice_control/voice_remote_expose_devices/)
- [Remotely Access Home Assistant with Tailscale](https://tailscale.com/blog/remotely-access-home-assistant)
