# src/neurosys-mcp/auth.py
# @decision MCP-08: Embedded OAuthProvider with static single-user credentials.
# @rationale: Self-contained OAuth server. No external IdP dependency.
#   Single user with password in sops. In-memory token store (stateless restart).
#
# @decision MCP-09: In-memory client registration + auth code store.
# @rationale: Single-instance server. Clients re-register on restart.
#   Auth codes are short-lived (5 min). Tokens stored in-memory dict.
#
# @decision MCP-10: Login form on /authorize, password checked before issuing code.
# @rationale: The MCP SDK's AuthorizationHandler calls provider.authorize() which
#   can return any redirect URL. We redirect to /login first, then complete the
#   OAuth flow after password verification.

from __future__ import annotations

import secrets
import time
from typing import Any
from mcp.server.auth.provider import (
    AuthorizationParams,
    construct_redirect_uri,
)
from mcp.server.auth.settings import ClientRegistrationOptions
from mcp.shared.auth import OAuthClientInformationFull
from starlette.requests import Request
from starlette.responses import HTMLResponse, RedirectResponse, Response
from starlette.routing import Route

from fastmcp.server.auth.providers.in_memory import InMemoryOAuthProvider


# Pending authorization sessions awaiting password verification
_PendingAuth = dict[str, dict[str, Any]]

LOGIN_HTML = """\
<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>neurosys — sign in</title>
<style>
  body {{ font-family: system-ui, sans-serif; background: #0d1117; color: #c9d1d9;
         display: flex; justify-content: center; align-items: center; min-height: 100vh; margin: 0; }}
  .card {{ background: #161b22; border: 1px solid #30363d; border-radius: 8px;
           padding: 2rem; max-width: 360px; width: 100%; }}
  h1 {{ font-size: 1.25rem; margin: 0 0 1.5rem; text-align: center; }}
  label {{ display: block; margin-bottom: 0.5rem; font-size: 0.875rem; }}
  input[type=password] {{ width: 100%; padding: 0.5rem; border: 1px solid #30363d;
                          border-radius: 4px; background: #0d1117; color: #c9d1d9;
                          font-size: 1rem; box-sizing: border-box; }}
  button {{ width: 100%; padding: 0.5rem; margin-top: 1rem; border: none;
            border-radius: 4px; background: #238636; color: #fff; font-size: 1rem;
            cursor: pointer; }}
  button:hover {{ background: #2ea043; }}
  .error {{ color: #f85149; font-size: 0.875rem; margin-top: 0.5rem; text-align: center; }}
</style>
</head>
<body>
<div class="card">
  <h1>neurosys MCP</h1>
  <form method="post">
    <input type="hidden" name="session" value="{session}">
    <label for="password">Password</label>
    <input type="password" id="password" name="password" autofocus required>
    <button type="submit">Sign in</button>
    {error_html}
  </form>
</div>
</body>
</html>
"""


class NeurosysOAuthProvider(InMemoryOAuthProvider):
    """OAuth 2.1 provider with single-user password gate on /authorize."""

    def __init__(
        self,
        base_url: str,
        password: str,
    ):
        super().__init__(
            base_url=base_url,
            client_registration_options=ClientRegistrationOptions(enabled=True),
            revocation_options=None,
        )
        self._password = password
        self._pending: _PendingAuth = {}

    async def authorize(
        self, client: OAuthClientInformationFull, params: AuthorizationParams
    ) -> str:
        """Redirect to /login instead of auto-approving."""
        session_id = secrets.token_urlsafe(32)
        self._pending[session_id] = {
            "client": client,
            "params": params,
            "created": time.time(),
        }
        # Prune sessions older than 10 minutes
        cutoff = time.time() - 600
        self._pending = {
            k: v for k, v in self._pending.items() if v["created"] > cutoff
        }
        return f"{self.base_url}/login?session={session_id}"

    async def _complete_authorize(
        self, client: OAuthClientInformationFull, params: AuthorizationParams
    ) -> str:
        """Generate auth code and redirect URI (the real authorization step)."""
        return await super().authorize(client, params)

    async def _handle_login(self, request: Request) -> Response:
        """GET/POST handler for the login form."""
        if request.method == "GET":
            session = request.query_params.get("session", "")
            if session not in self._pending:
                return HTMLResponse("Invalid or expired session.", status_code=400)
            html = LOGIN_HTML.format(session=session, error_html="")
            return HTMLResponse(html)

        # POST: check password
        form = await request.form()
        session = str(form.get("session", ""))
        password = str(form.get("password", ""))

        pending = self._pending.get(session)
        if not pending:
            return HTMLResponse("Session expired. Please try again.", status_code=400)

        if not secrets.compare_digest(password, self._password):
            html = LOGIN_HTML.format(
                session=session,
                error_html='<p class="error">Incorrect password.</p>',
            )
            return HTMLResponse(html, status_code=401)

        # Password correct — complete the OAuth flow
        del self._pending[session]
        redirect_url = await self._complete_authorize(
            pending["client"], pending["params"]
        )
        return RedirectResponse(url=redirect_url, status_code=302)

    def get_routes(
        self,
        mcp_path: str | None = None,
        mcp_endpoint: Any | None = None,
    ) -> list[Route]:
        """Add /login route to the standard OAuth routes."""
        routes = super().get_routes(mcp_path, mcp_endpoint)
        routes.append(
            Route("/login", endpoint=self._handle_login, methods=["GET", "POST"])
        )
        return routes


def create_oauth_provider(
    password: str,
    public_url: str,
) -> NeurosysOAuthProvider:
    """Create the OAuth provider for the neurosys MCP server."""
    return NeurosysOAuthProvider(base_url=public_url, password=password)
