# Phase 63 Deploy: Google OAuth + Gmail MCP

This runbook enables Google OAuth credentials for the public `neurosys-mcp` service and completes one-time authorization.

## 1) Add SOPS secrets (private overlay)

In `private-neurosys/modules/secrets.nix`, add two new secret entries:
- `google-oauth-client-id`
- `google-oauth-client-secret`

These should map to environment variables consumed by the service:
- `GOOGLE_OAUTH_CLIENT_ID`
- `GOOGLE_OAUTH_CLIENT_SECRET`

## 2) Wire env vars into neurosys-mcp service (private overlay)

In `private-neurosys/modules/neurosys-mcp.nix`, ensure the service `EnvironmentFile` exports:
- `GOOGLE_OAUTH_CLIENT_ID`
- `GOOGLE_OAUTH_CLIENT_SECRET`

Optional override:
- `GOOGLE_OAUTH_REDIRECT_URI` (defaults to `${MCP_PUBLIC_URL}/google/callback` when unset)

## 3) Encrypt/update secrets with sops

Update the encrypted SOPS secrets with your Google OAuth client id/secret values and commit private overlay changes.

## 4) Deploy and perform one-time OAuth authorization

After deployment, complete the OAuth flow:
1. Open `https://<mcp-public-host>/google/auth`
2. Sign in to the intended Google account
3. Approve requested scopes
4. Confirm callback success at `/google/callback`

Tokens are persisted to `/var/lib/neurosys-mcp/google-tokens.json` for automatic refresh.

## Credential Reuse Note

Existing Google Cloud Console OAuth credentials can be reused. No new OAuth app is required; provide the current client ID and client secret via sops.
