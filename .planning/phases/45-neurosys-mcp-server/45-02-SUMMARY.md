---
phase: 45-neurosys-mcp-server
plan: 02
subsystem: infra
tags: [mcp, oauth, matrix, tailscale-funnel, nixos, private-overlay]
requires: [45-01]
provides:
  - OAuth 2.1 password-protected authorization for Claude.ai connector
  - 5 Matrix/Conduit tools (list_rooms, get_messages, search_rooms, get_dm_messages, send_message)
  - NixOS module in private overlay (systemd service + Tailscale Funnel + sops template)
affects: []
tech-stack:
  added: [oauth2.1, tailscale-funnel]
  patterns: [InMemoryOAuthProvider subclass, sops.templates env rendering]
key-files:
  created: [src/neurosys-mcp/auth.py, private:modules/neurosys-mcp.nix]
  modified: [src/neurosys-mcp/server.py, src/neurosys-mcp/pyproject.toml, private:flake.nix, private:modules/secrets.nix, private:secrets/neurosys.yaml, private:flake.lock]
key-decisions:
  - "MCP-05: Localhost-only binding; public access via Tailscale Funnel on port 8443"
  - "MCP-06: DynamicUser + ProtectSystem=strict + PrivateTmp systemd hardening"
  - "MCP-07: All secrets via sops EnvironmentFile, not CLI args"
  - "MCP-11: Tailscale Funnel on port 8443 (HA stays on serve:443)"
  - "OAuth subclasses InMemoryOAuthProvider with HTML login form redirect"
completed: 2026-03-01
---

# Phase 45 Plan 02 Summary

Added OAuth 2.1 authentication, Matrix/Conduit tools, and private overlay NixOS module for the neurosys MCP server.

## Accomplishments

- **auth.py**: `NeurosysOAuthProvider` subclasses FastMCP's `InMemoryOAuthProvider` to inject a password-protected HTML login form before completing the OAuth authorization code flow. Uses `secrets.compare_digest` for password comparison, session expiry (10min), and standard OAuth 2.1 (DCR + PKCE S256).

- **server.py**: Added 5 Matrix tools (`matrix_list_rooms`, `matrix_get_messages`, `matrix_search_rooms`, `matrix_get_dm_messages`, `matrix_send_message`) that gracefully degrade when `MATRIX_URL`/`MATRIX_TOKEN` are unset. OAuth conditionally enabled when `MCP_OAUTH_PASSWORD` + `MCP_PUBLIC_URL` are set.

- **Private overlay NixOS module** (`modules/neurosys-mcp.nix`):
  - `systemd.services.neurosys-mcp`: DynamicUser, ProtectSystem=strict, PrivateTmp, NoNewPrivileges
  - `systemd.services.tailscale-funnel-mcp`: oneshot Funnel on port 8443 → localhost:8400
  - `sops.templates."neurosys-mcp-env"`: renders HA_TOKEN, MATRIX_TOKEN, MCP_JWT_SIGNING_KEY, MCP_OAUTH_PASSWORD

- **sops secrets**: Added `matrix-bot-token`, `mcp-jwt-key` (auto-generated), `mcp-oauth-password` to `secrets/neurosys.yaml`

- **Private flake**: Module added to `contaboModules`, flake.lock updated to public neurosys commit `078e6f6`

## Verification

- `python3 -c "import ast; ast.parse(open('server.py').read())"` — pass
- `python3 -c "import ast; ast.parse(open('auth.py').read())"` — pass
- `nix build .#neurosys-mcp` — pass (public repo)
- `nix flake check` — pass (public repo)
- `nix flake check` — pass (private overlay, both neurosys + ovh hosts)
- sops secrets decrypted and verified (`matrix-bot-token`, `mcp-jwt-key`, `mcp-oauth-password` present)

## Deployment Checkpoint (Human Action Required)

Before Claude.ai can connect, the following manual steps are needed:

1. **Deploy to Contabo**: `./scripts/deploy.sh` from private-neurosys
2. **Enable Tailscale Funnel ACL**: Add `"neurosys:8443"` to Tailscale admin Funnel policy
3. **Create Matrix bot user** on Conduit and update `matrix-bot-token` in sops
4. **Set real MCP OAuth password** in sops: `sops secrets/neurosys.yaml` → update `mcp-oauth-password`
5. **Re-deploy** after sops secret updates
6. **Connect Claude.ai**: Add MCP connector URL `https://neurosys.taildb9d4d.ts.net:8443/mcp`
