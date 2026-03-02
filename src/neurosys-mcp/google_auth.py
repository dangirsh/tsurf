"""
Google OAuth 2.0 helpers for neurosys MCP Gmail/Calendar access.

@decision MCP-63-01: Use google-auth + httpx only (no google-api-python-client).
@rationale Keep dependency footprint small and consistent with Nix packaging.

@decision MCP-63-02: Persist OAuth tokens under NEUROSYS_MCP_STATE_DIR.
@rationale Refresh tokens must survive service restarts for unattended operation.

@decision MCP-63-03: Expose one-time browser routes on the MCP process.
@rationale Reuse the existing public MCP endpoint for interactive authorization.
"""

from __future__ import annotations

import json
import logging
import os
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Any
from urllib.parse import urlencode

import httpx
from google.auth.transport.requests import Request as GoogleRequest
from google.oauth2.credentials import Credentials
from starlette.requests import Request
from starlette.responses import HTMLResponse, PlainTextResponse, RedirectResponse, Response
from starlette.routing import Route

LOGGER = logging.getLogger(__name__)

GOOGLE_TOKEN_URI = "https://oauth2.googleapis.com/token"
GOOGLE_AUTH_URI = "https://accounts.google.com/o/oauth2/v2/auth"
SCOPES = [
    "https://www.googleapis.com/auth/gmail.modify",
    "https://www.googleapis.com/auth/gmail.send",
    "https://www.googleapis.com/auth/calendar",
]


def _state_dir() -> Path:
    return Path(os.environ.get("NEUROSYS_MCP_STATE_DIR", "/var/lib/neurosys-mcp"))


def _tokens_path() -> Path:
    return _state_dir() / "google-tokens.json"


def _client_id() -> str:
    return os.environ.get("GOOGLE_OAUTH_CLIENT_ID", "").strip()


def _client_secret() -> str:
    return os.environ.get("GOOGLE_OAUTH_CLIENT_SECRET", "").strip()


def _redirect_uri() -> str:
    configured = os.environ.get("GOOGLE_OAUTH_REDIRECT_URI", "").strip()
    if configured:
        return configured
    public_url = os.environ.get("MCP_PUBLIC_URL", "").rstrip("/")
    if not public_url:
        return ""
    return f"{public_url}/google/callback"


def _google_configured() -> bool:
    return bool(_client_id() and _client_secret())


def get_auth_url() -> str:
    if not _google_configured():
        return ""

    redirect_uri = _redirect_uri()
    if not redirect_uri:
        return ""

    query = urlencode(
        {
            "client_id": _client_id(),
            "redirect_uri": redirect_uri,
            "response_type": "code",
            "scope": " ".join(SCOPES),
            "access_type": "offline",
            "prompt": "consent",
            "include_granted_scopes": "true",
        }
    )
    return f"{GOOGLE_AUTH_URI}?{query}"


async def handle_callback(code: str) -> dict[str, Any]:
    if not _google_configured():
        return {"ok": False, "error": "google_auth_required"}

    if not code:
        return {"ok": False, "error": "missing_code"}

    redirect_uri = _redirect_uri()
    if not redirect_uri:
        return {"ok": False, "error": "google_redirect_uri_not_configured"}

    old_tokens = _load_tokens() or {}

    payload = {
        "code": code,
        "client_id": _client_id(),
        "client_secret": _client_secret(),
        "redirect_uri": redirect_uri,
        "grant_type": "authorization_code",
    }

    try:
        async with httpx.AsyncClient(timeout=20.0) as client:
            response = await client.post(GOOGLE_TOKEN_URI, data=payload)
            response.raise_for_status()
            data = response.json()
    except httpx.HTTPError as exc:
        LOGGER.exception("Google token exchange failed: %s", exc)
        return {"ok": False, "error": "google_token_exchange_failed"}

    access_token = data.get("access_token")
    if not access_token:
        return {"ok": False, "error": "missing_access_token"}

    expires_in = int(data.get("expires_in", 3600))
    expires_at = int(time.time()) + expires_in
    refresh_token = data.get("refresh_token") or old_tokens.get("refresh_token")

    scope_text = str(data.get("scope", "")).strip()
    scopes = scope_text.split() if scope_text else SCOPES

    tokens = {
        "access_token": access_token,
        "refresh_token": refresh_token,
        "expires_at": expires_at,
        "token_uri": GOOGLE_TOKEN_URI,
        "scopes": scopes,
    }
    _save_tokens(tokens)

    return {
        "ok": True,
        "expires_at": expires_at,
        "scopes": scopes,
        "has_refresh_token": bool(refresh_token),
    }


def _load_tokens() -> dict[str, Any] | None:
    path = _tokens_path()
    if not path.exists():
        return None

    try:
        with path.open("r", encoding="utf-8") as f:
            data = json.load(f)
            if isinstance(data, dict):
                return data
    except (json.JSONDecodeError, OSError) as exc:
        LOGGER.warning("Failed to load Google token file %s: %s", path, exc)

    return None


def _save_tokens(tokens: dict[str, Any]) -> None:
    path = _tokens_path()
    path.parent.mkdir(parents=True, exist_ok=True)

    with path.open("w", encoding="utf-8") as f:
        json.dump(tokens, f, indent=2, sort_keys=True)


def _credentials_to_tokens(creds: Credentials, old_tokens: dict[str, Any]) -> dict[str, Any]:
    expires_at: int | None = None
    if creds.expiry is not None:
        expires_at = int(creds.expiry.replace(tzinfo=timezone.utc).timestamp())

    return {
        "access_token": creds.token,
        "refresh_token": creds.refresh_token or old_tokens.get("refresh_token"),
        "expires_at": expires_at or int(time.time()) + 3600,
        "token_uri": creds.token_uri or GOOGLE_TOKEN_URI,
        "scopes": list(creds.scopes or old_tokens.get("scopes") or SCOPES),
    }


def get_credentials() -> Credentials | None:
    if not _google_configured():
        return None

    tokens = _load_tokens()
    if not tokens:
        return None

    creds = Credentials(
        token=tokens.get("access_token"),
        refresh_token=tokens.get("refresh_token"),
        token_uri=tokens.get("token_uri", GOOGLE_TOKEN_URI),
        client_id=_client_id(),
        client_secret=_client_secret(),
        scopes=tokens.get("scopes") or SCOPES,
    )

    expires_at = tokens.get("expires_at")
    if isinstance(expires_at, (int, float)):
        creds.expiry = datetime.fromtimestamp(expires_at, tz=timezone.utc)

    if creds.valid and creds.token:
        return creds

    if not creds.refresh_token:
        LOGGER.info("Google token refresh unavailable: refresh token missing")
        return None

    try:
        creds.refresh(GoogleRequest())
    except Exception:
        LOGGER.exception("Google token refresh failed")
        return None

    if not creds.token:
        LOGGER.error("Google token refresh completed without access token")
        return None

    _save_tokens(_credentials_to_tokens(creds, tokens))
    return creds


async def get_access_token() -> str | None:
    creds = get_credentials()
    if not creds:
        return None
    return creds.token


async def _handle_auth_start(request: Request) -> Response:
    del request

    if not _google_configured():
        return PlainTextResponse("Google OAuth is not configured.", status_code=503)

    auth_url = get_auth_url()
    if not auth_url:
        return PlainTextResponse(
            "Google OAuth redirect URI is not configured.", status_code=503
        )

    return RedirectResponse(url=auth_url, status_code=302)


async def _handle_callback(request: Request) -> Response:
    code = request.query_params.get("code", "")
    if not code:
        return PlainTextResponse("Missing code query parameter.", status_code=400)

    result = await handle_callback(code)
    if not result.get("ok"):
        error = str(result.get("error", "oauth_callback_failed"))
        return PlainTextResponse(f"Google OAuth failed: {error}", status_code=400)

    return HTMLResponse(
        "<h1>Google OAuth complete</h1><p>You can close this tab and return to the MCP client.</p>",
        status_code=200,
    )


def get_routes() -> list[Route]:
    return [
        Route("/google/auth", endpoint=_handle_auth_start, methods=["GET"]),
        Route("/google/callback", endpoint=_handle_callback, methods=["GET"]),
    ]
