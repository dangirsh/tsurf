#!/usr/bin/env python3
# src/neurosys-mcp/server.py
# @decision MCP-45-01: expose Home Assistant operations as FastMCP tools over streamable HTTP.
# @decision MCP-45-02: keep MCP server auth disabled; optional HA bearer token is read from env only.

from __future__ import annotations

import os
from typing import Any

import httpx
from fastmcp import FastMCP

HOME_ASSISTANT_URL = os.environ.get("HOME_ASSISTANT_URL", "http://127.0.0.1:8123").rstrip("/")
HOME_ASSISTANT_TOKEN = os.environ.get("HOME_ASSISTANT_TOKEN", "")
HOME_ASSISTANT_TIMEOUT_SECONDS = float(os.environ.get("HOME_ASSISTANT_TIMEOUT_SECONDS", "15"))

MCP_BIND_HOST = os.environ.get("NEUROSYS_MCP_HOST", "127.0.0.1")
MCP_BIND_PORT = int(os.environ.get("NEUROSYS_MCP_PORT", "8400"))
MCP_PATH = os.environ.get("NEUROSYS_MCP_PATH", "/mcp")

mcp = FastMCP(
    name="neurosys-home-assistant-mcp",
    instructions=(
        "Read and control Home Assistant entities via REST API tools. "
        "Use ha_list_services before calling unknown services."
    ),
)


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


def main() -> None:
    path = MCP_PATH if MCP_PATH.startswith("/") else f"/{MCP_PATH}"
    mcp.run(
        transport="streamable-http",
        host=MCP_BIND_HOST,
        port=MCP_BIND_PORT,
        path=path,
    )


if __name__ == "__main__":
    main()
