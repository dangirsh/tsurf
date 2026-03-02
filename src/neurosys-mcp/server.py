#!/usr/bin/env python3
# src/neurosys-mcp/server.py
# @decision MCP-01: Expose Home Assistant + Matrix as FastMCP tools over streamable HTTP.
# @decision MCP-02: OAuth enabled when MCP_OAUTH_PASSWORD + MCP_PUBLIC_URL are set;
#   otherwise no auth (local dev / tailnet-only). Auth module in auth.py.
# @decision MCP-03: Matrix tools degrade gracefully when MATRIX_URL/MATRIX_TOKEN empty.
# @decision MCP-63-06: Mount /google/auth + /google/callback only when Google OAuth is configured.
# @rationale Avoid exposing dead routes while preserving one-time interactive authorization flow.

from __future__ import annotations

import os
import time as _time
from typing import Any

import httpx
import uvicorn
from fastmcp import FastMCP
from starlette.applications import Starlette
from starlette.routing import Mount

# --- Home Assistant config ---
HOME_ASSISTANT_URL = os.environ.get("HOME_ASSISTANT_URL", "http://127.0.0.1:8123").rstrip("/")
HOME_ASSISTANT_TOKEN = os.environ.get("HOME_ASSISTANT_TOKEN", "")
HOME_ASSISTANT_TIMEOUT_SECONDS = float(os.environ.get("HOME_ASSISTANT_TIMEOUT_SECONDS", "15"))

# --- Matrix/Conduit config ---
MATRIX_URL = os.environ.get("MATRIX_URL", "").rstrip("/")
MATRIX_TOKEN = os.environ.get("MATRIX_TOKEN", "")

# --- MCP server config ---
MCP_BIND_HOST = os.environ.get("NEUROSYS_MCP_HOST", "127.0.0.1")
MCP_BIND_PORT = int(os.environ.get("NEUROSYS_MCP_PORT", "8400"))
MCP_PATH = os.environ.get("NEUROSYS_MCP_PATH", "/mcp")

# --- OAuth config (optional) ---
MCP_OAUTH_PASSWORD = os.environ.get("MCP_OAUTH_PASSWORD", "")
MCP_PUBLIC_URL = os.environ.get("MCP_PUBLIC_URL", "")

# Build the FastMCP server — with OAuth if credentials are configured
_auth_provider = None
if MCP_OAUTH_PASSWORD and MCP_PUBLIC_URL:
    from auth import create_oauth_provider
    _auth_provider = create_oauth_provider(
        password=MCP_OAUTH_PASSWORD,
        public_url=MCP_PUBLIC_URL,
    )

mcp = FastMCP(
    name="neurosys",
    instructions=(
        "Control Home Assistant entities, query Matrix/Conduit messages, "
        "search the Logseq PKM vault, and manage Gmail. "
        "Use ha_list_services before calling unknown services. "
        "Matrix tools return errors when Matrix is not configured. "
        "Logseq tools return errors when LOGSEQ_VAULT_PATH is not set. "
        "Gmail tools return google_auth_required when Google OAuth is not configured."
    ),
    auth=_auth_provider,
)

# --- Logseq vault tools (Phase 59) ---
import logseq as _logseq_tools
_logseq_tools.register(mcp)

# --- Google OAuth + Gmail tools (Phase 63) ---
import google_auth as _google_auth
import gmail as _gmail_tools
_gmail_tools.register(mcp)


def _normalized_path(path: str) -> str:
    if not path.startswith("/"):
        return f"/{path}"
    return path


def _auth_headers() -> dict[str, str]:
    if HOME_ASSISTANT_TOKEN:
        return {
            "Authorization": f"Bearer {HOME_ASSISTANT_TOKEN}",
            "Content-Type": "application/json",
        }
    return {"Content-Type": "application/json"}


async def _ha_request(method: str, path: str, **kwargs: Any) -> Any:
    url = f"{HOME_ASSISTANT_URL}{_normalized_path(path)}"
    timeout = kwargs.pop("timeout", HOME_ASSISTANT_TIMEOUT_SECONDS)

    async with httpx.AsyncClient(timeout=timeout) as client:
        try:
            response = await client.request(method=method, url=url, headers=_auth_headers(), **kwargs)
            response.raise_for_status()
        except httpx.HTTPStatusError as exc:
            detail: Any
            try:
                detail = exc.response.json()
            except ValueError:
                detail = exc.response.text
            return {
                "ok": False,
                "status": exc.response.status_code,
                "error": "home_assistant_http_error",
                "detail": detail,
            }
        except httpx.HTTPError as exc:
            return {
                "ok": False,
                "error": "home_assistant_transport_error",
                "detail": str(exc),
            }

    if not response.content:
        return {"ok": True, "data": None}

    try:
        payload = response.json()
    except ValueError:
        payload = response.text

    return {"ok": True, "data": payload}


@mcp.tool()
async def ha_get_states() -> Any:
    """Return all entity states from Home Assistant (`GET /api/states`)."""
    return await _ha_request("GET", "/api/states")


@mcp.tool()
async def ha_get_state(entity_id: str) -> Any:
    """Return a single entity state (`GET /api/states/{entity_id}`)."""
    return await _ha_request("GET", f"/api/states/{entity_id}")


@mcp.tool()
async def ha_call_service(
    domain: str,
    service: str,
    service_data: dict[str, Any] | None = None,
    target: dict[str, Any] | None = None,
    return_response: bool = False,
) -> Any:
    """Call a Home Assistant service (`POST /api/services/{domain}/{service}`)."""
    payload: dict[str, Any] = {}
    if service_data:
        payload.update(service_data)
    if target:
        payload["target"] = target

    params = {"return_response": "1"} if return_response else None
    return await _ha_request(
        "POST",
        f"/api/services/{domain}/{service}",
        json=payload,
        params=params,
    )


@mcp.tool()
async def ha_list_services() -> Any:
    """Return all available Home Assistant services (`GET /api/services`)."""
    return await _ha_request("GET", "/api/services")


@mcp.tool()
async def ha_search_entities(query: str, limit: int = 25) -> Any:
    """Search entity IDs, states, and friendly names using a case-insensitive contains match."""
    if not query.strip():
        return {"ok": False, "error": "query_must_not_be_empty"}
    if limit < 1:
        return {"ok": False, "error": "limit_must_be_positive"}

    states_result = await _ha_request("GET", "/api/states")
    if not states_result.get("ok"):
        return states_result

    needle = query.strip().lower()
    results: list[dict[str, Any]] = []

    for item in states_result.get("data", []):
        entity_id = str(item.get("entity_id", ""))
        state = str(item.get("state", ""))
        attributes = item.get("attributes") or {}
        friendly_name = str(attributes.get("friendly_name", ""))

        haystack = " ".join([entity_id, state, friendly_name]).lower()
        if needle in haystack:
            results.append(item)

        if len(results) >= limit:
            break

    return {
        "ok": True,
        "query": query,
        "count": len(results),
        "results": results,
    }


# ---------------------------------------------------------------------------
# Matrix / Conduit tools
# ---------------------------------------------------------------------------


def _matrix_headers() -> dict[str, str]:
    return {
        "Authorization": f"Bearer {MATRIX_TOKEN}",
        "Content-Type": "application/json",
    }


def _matrix_configured() -> bool:
    return bool(MATRIX_URL and MATRIX_TOKEN)


@mcp.tool()
async def matrix_list_rooms() -> Any:
    """List all Matrix rooms the bot has joined, with names."""
    if not _matrix_configured():
        return {"ok": False, "error": "matrix_not_configured"}
    async with httpx.AsyncClient(timeout=10) as client:
        resp = await client.get(
            f"{MATRIX_URL}/_matrix/client/v3/joined_rooms",
            headers=_matrix_headers(),
        )
        resp.raise_for_status()
        room_ids = resp.json().get("joined_rooms", [])
        rooms: list[dict[str, str]] = []
        for room_id in room_ids:
            try:
                state_resp = await client.get(
                    f"{MATRIX_URL}/_matrix/client/v3/rooms/{room_id}/state/m.room.name",
                    headers=_matrix_headers(),
                    timeout=5,
                )
                name = (
                    state_resp.json().get("name", room_id)
                    if state_resp.status_code == 200
                    else room_id
                )
            except Exception:
                name = room_id
            rooms.append({"room_id": room_id, "name": name})
        return {"ok": True, "rooms": rooms}


@mcp.tool()
async def matrix_get_messages(room_id: str, limit: int = 50) -> Any:
    """Get recent messages from a Matrix room."""
    if not _matrix_configured():
        return {"ok": False, "error": "matrix_not_configured"}
    async with httpx.AsyncClient(timeout=10) as client:
        resp = await client.get(
            f"{MATRIX_URL}/_matrix/client/v3/rooms/{room_id}/messages",
            headers=_matrix_headers(),
            params={"dir": "b", "limit": limit},
        )
        resp.raise_for_status()
        events = resp.json().get("chunk", [])
        messages = [
            {
                "sender": e.get("sender"),
                "body": e.get("content", {}).get("body", ""),
                "timestamp": e.get("origin_server_ts"),
                "type": e.get("type"),
            }
            for e in events
            if e.get("type") == "m.room.message"
        ]
        return {"ok": True, "messages": messages}


@mcp.tool()
async def matrix_search_rooms(query: str) -> Any:
    """Search Matrix rooms by name substring."""
    if not _matrix_configured():
        return {"ok": False, "error": "matrix_not_configured"}
    result = await matrix_list_rooms()
    if not result.get("ok"):
        return result
    q = query.lower()
    matched = [r for r in result["rooms"] if q in r.get("name", "").lower()]
    return {"ok": True, "rooms": matched}


@mcp.tool()
async def matrix_get_dm_messages(user: str, limit: int = 50) -> Any:
    """Get recent DM messages with a specific Matrix user.

    Args:
        user: Matrix user ID (e.g., @admin:neurosys.local) or display name.
        limit: Maximum number of messages to return.
    """
    if not _matrix_configured():
        return {"ok": False, "error": "matrix_not_configured"}
    rooms_result = await matrix_list_rooms()
    if not rooms_result.get("ok"):
        return rooms_result
    async with httpx.AsyncClient(timeout=10) as client:
        for room in rooms_result["rooms"]:
            try:
                members_resp = await client.get(
                    f"{MATRIX_URL}/_matrix/client/v3/rooms/{room['room_id']}/joined_members",
                    headers=_matrix_headers(),
                    timeout=5,
                )
                if members_resp.status_code != 200:
                    continue
                members = members_resp.json().get("joined", {})
                if len(members) == 2:
                    member_ids = list(members.keys())
                    member_names = [
                        members[m].get("display_name", m) for m in member_ids
                    ]
                    if any(
                        user.lower() in mid.lower()
                        or user.lower() in mname.lower()
                        for mid, mname in zip(member_ids, member_names)
                    ):
                        return await matrix_get_messages(room["room_id"], limit)
            except Exception:
                continue
    return {"ok": True, "messages": []}


@mcp.tool()
async def matrix_send_message(room_id: str, text: str) -> Any:
    """Send a text message to a Matrix room."""
    if not _matrix_configured():
        return {"ok": False, "error": "matrix_not_configured"}
    txn_id = str(int(_time.time() * 1000))
    async with httpx.AsyncClient(timeout=10) as client:
        resp = await client.put(
            f"{MATRIX_URL}/_matrix/client/v3/rooms/{room_id}/send/m.room.message/{txn_id}",
            headers=_matrix_headers(),
            json={"msgtype": "m.text", "body": text},
        )
        resp.raise_for_status()
        return {"ok": True, "event_id": resp.json().get("event_id")}


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------


def main() -> None:
    path = MCP_PATH if MCP_PATH.startswith("/") else f"/{MCP_PATH}"

    if _google_auth._google_configured():
        mcp_app = mcp.streamable_http_app(path=path)
        routes = [*_google_auth.get_routes(), Mount("/", app=mcp_app)]
        app = Starlette(routes=routes)
        uvicorn.run(app, host=MCP_BIND_HOST, port=MCP_BIND_PORT)
        return

    mcp.run(
        transport="streamable-http",
        host=MCP_BIND_HOST,
        port=MCP_BIND_PORT,
        path=path,
    )


if __name__ == "__main__":
    main()
