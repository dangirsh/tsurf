"""
REST shim endpoints for Gmail and Calendar.

Exposes the same Gmail/Calendar operations as plain POST endpoints with
shared-bearer auth — no MCP protocol or interactive OAuth involved.

Google OAuth tokens stay inside the neurosys-mcp process. The caller
(parts) authenticates with a pre-shared secret via Authorization: Bearer.

@decision SHIM-01: Starlette routes mounted alongside MCP app.
@rationale Reuse existing gmail.py/_gmail_request and calendar_tools.py/_cal_request.
"""

from __future__ import annotations

import os
import secrets as _secrets
from typing import Any

from starlette.requests import Request
from starlette.responses import JSONResponse
from starlette.routing import Route

import gmail as _gmail
import calendar_tools as _cal

REST_SHIM_SECRET = os.environ.get("REST_SHIM_SECRET", "")


def _check_auth(request: Request) -> bool:
    if not REST_SHIM_SECRET:
        return False
    auth = request.headers.get("authorization", "")
    if not auth.startswith("Bearer "):
        return False
    token = auth.removeprefix("Bearer ")
    return _secrets.compare_digest(token, REST_SHIM_SECRET)


def _unauthorized() -> JSONResponse:
    return JSONResponse({"ok": False, "error": "unauthorized"}, status_code=401)


# --- Gmail endpoints ---

async def gmail_search(request: Request) -> JSONResponse:
    if not _check_auth(request):
        return _unauthorized()
    body = await request.json()
    result = await _gmail._gmail_request(
        "GET",
        "/messages",
        params={
            "q": body.get("query", ""),
            "maxResults": max(1, min(body.get("max_results", 10), 50)),
        },
    )
    if not result.get("ok"):
        return JSONResponse(result)
    # Fetch metadata for each message (same logic as gmail_search MCP tool)
    message_refs = result["data"].get("messages", [])
    results: list[dict[str, Any]] = []
    for ref in message_refs:
        message_id = ref.get("id")
        if not message_id:
            continue
        meta_resp = await _gmail._gmail_request(
            "GET",
            f"/messages/{message_id}",
            params={
                "format": "metadata",
                "metadataHeaders": ["From", "To", "Subject", "Date"],
            },
        )
        if not meta_resp.get("ok"):
            if meta_resp.get("error") == "google_auth_required":
                return JSONResponse(meta_resp)
            continue
        msg = meta_resp["data"]
        payload = msg.get("payload", {})
        results.append({
            "id": msg.get("id"),
            "thread_id": msg.get("threadId"),
            "snippet": msg.get("snippet", ""),
            "headers": _gmail._extract_headers(payload),
        })
    return JSONResponse({"ok": True, "query": body.get("query", ""), "count": len(results), "messages": results})


async def gmail_read(request: Request) -> JSONResponse:
    if not _check_auth(request):
        return _unauthorized()
    body = await request.json()
    message_id = body.get("message_id", "")
    max_body_chars = body.get("max_body_chars", 500)
    response = await _gmail._gmail_request(
        "GET",
        f"/messages/{message_id}",
        params={"format": "full"},
    )
    if not response.get("ok"):
        return JSONResponse(response)
    message = response["data"]
    payload = message.get("payload", {})
    return JSONResponse({
        "ok": True,
        "message": {
            "id": message.get("id"),
            "thread_id": message.get("threadId"),
            "label_ids": message.get("labelIds", []),
            "snippet": message.get("snippet", ""),
            "headers": _gmail._extract_headers(payload),
            "body": _gmail._extract_body(payload, max_chars=max_body_chars),
        },
    })


async def gmail_draft(request: Request) -> JSONResponse:
    if not _check_auth(request):
        return _unauthorized()
    body = await request.json()
    raw = _gmail._build_message_raw(to=body["to"], subject=body["subject"], body=body["body"])
    response = await _gmail._gmail_request("POST", "/drafts", json={"message": {"raw": raw}})
    if not response.get("ok"):
        return JSONResponse(response)
    draft = response["data"]
    return JSONResponse({"ok": True, "draft_id": draft.get("id"), "message_id": draft.get("message", {}).get("id")})


async def gmail_send(request: Request) -> JSONResponse:
    if not _check_auth(request):
        return _unauthorized()
    body = await request.json()
    raw = _gmail._build_message_raw(to=body["to"], subject=body["subject"], body=body["body"])
    response = await _gmail._gmail_request("POST", "/messages/send", json={"raw": raw})
    if not response.get("ok"):
        return JSONResponse(response)
    sent = response["data"]
    return JSONResponse({"ok": True, "message_id": sent.get("id"), "thread_id": sent.get("threadId")})


async def gmail_archive(request: Request) -> JSONResponse:
    if not _check_auth(request):
        return _unauthorized()
    body = await request.json()
    message_id = body.get("message_id", "")
    response = await _gmail._gmail_request("POST", f"/messages/{message_id}/modify", json={"removeLabelIds": ["INBOX"]})
    if not response.get("ok"):
        return JSONResponse(response)
    data = response["data"]
    return JSONResponse({"ok": True, "message_id": data.get("id", message_id)})


# --- Calendar endpoints ---

async def calendar_list(request: Request) -> JSONResponse:
    if not _check_auth(request):
        return _unauthorized()
    body = await request.json()
    response = await _cal._cal_request(
        "GET",
        "/calendars/primary/events",
        params={
            "timeMin": body["time_min"],
            "timeMax": body["time_max"],
            "maxResults": max(1, min(body.get("max_results", 10), 250)),
            "singleEvents": "true",
            "orderBy": "startTime",
        },
    )
    if not response.get("ok"):
        return JSONResponse(response)
    items = response["data"].get("items", [])
    return JSONResponse({"ok": True, "count": len(items), "events": [_cal._format_event(e) for e in items]})


async def calendar_search(request: Request) -> JSONResponse:
    if not _check_auth(request):
        return _unauthorized()
    body = await request.json()
    params: dict[str, Any] = {
        "q": body["query"],
        "maxResults": max(1, min(body.get("max_results", 10), 250)),
        "singleEvents": "true",
        "orderBy": "startTime",
    }
    if body.get("time_min"):
        params["timeMin"] = body["time_min"]
    if body.get("time_max"):
        params["timeMax"] = body["time_max"]
    response = await _cal._cal_request("GET", "/calendars/primary/events", params=params)
    if not response.get("ok"):
        return JSONResponse(response)
    items = response["data"].get("items", [])
    return JSONResponse({"ok": True, "query": body["query"], "count": len(items), "events": [_cal._format_event(e) for e in items]})


async def calendar_free_busy(request: Request) -> JSONResponse:
    if not _check_auth(request):
        return _unauthorized()
    body = await request.json()
    response = await _cal._cal_request("POST", "/freeBusy", json={"timeMin": body["time_min"], "timeMax": body["time_max"], "items": [{"id": "primary"}]})
    if not response.get("ok"):
        return JSONResponse(response)
    busy = response["data"].get("calendars", {}).get("primary", {}).get("busy", [])
    return JSONResponse({"ok": True, "busy_periods": [{"start": b.get("start"), "end": b.get("end")} for b in busy]})


async def calendar_create(request: Request) -> JSONResponse:
    if not _check_auth(request):
        return _unauthorized()
    body = await request.json()
    event: dict[str, Any] = {
        "summary": body["summary"],
        "start": _cal._time_field(body["start"]),
        "end": _cal._time_field(body["end"]),
    }
    if body.get("description"):
        event["description"] = body["description"]
    if body.get("location"):
        event["location"] = body["location"]
    if body.get("attendees"):
        event["attendees"] = _cal._attendee_payload(body["attendees"])
    response = await _cal._cal_request("POST", "/calendars/primary/events", json=event)
    if not response.get("ok"):
        return JSONResponse(response)
    return JSONResponse({"ok": True, "event": _cal._format_event(response["data"])})


async def calendar_update(request: Request) -> JSONResponse:
    if not _check_auth(request):
        return _unauthorized()
    body = await request.json()
    from urllib.parse import quote
    safe_id = quote(body["event_id"], safe="")
    existing = await _cal._cal_request("GET", f"/calendars/primary/events/{safe_id}")
    if not existing.get("ok"):
        return JSONResponse(existing)
    event = existing["data"]
    if body.get("summary") is not None:
        event["summary"] = body["summary"]
    if body.get("start") is not None:
        event["start"] = _cal._time_field(body["start"])
    if body.get("end") is not None:
        event["end"] = _cal._time_field(body["end"])
    if body.get("description") is not None:
        event["description"] = body["description"]
    if body.get("location") is not None:
        event["location"] = body["location"]
    if body.get("attendees") is not None:
        event["attendees"] = _cal._attendee_payload(body["attendees"])
    response = await _cal._cal_request("PUT", f"/calendars/primary/events/{safe_id}", json=event)
    if not response.get("ok"):
        return JSONResponse(response)
    return JSONResponse({"ok": True, "event": _cal._format_event(response["data"])})


async def calendar_delete(request: Request) -> JSONResponse:
    if not _check_auth(request):
        return _unauthorized()
    body = await request.json()
    from urllib.parse import quote
    safe_id = quote(body["event_id"], safe="")
    response = await _cal._cal_request("DELETE", f"/calendars/primary/events/{safe_id}")
    if not response.get("ok"):
        return JSONResponse(response)
    return JSONResponse({"ok": True, "event_id": body["event_id"]})


def get_shim_routes() -> list[Route]:
    """Return Starlette routes for the REST shim."""
    return [
        Route("/shim/gmail/search", endpoint=gmail_search, methods=["POST"]),
        Route("/shim/gmail/read", endpoint=gmail_read, methods=["POST"]),
        Route("/shim/gmail/draft", endpoint=gmail_draft, methods=["POST"]),
        Route("/shim/gmail/send", endpoint=gmail_send, methods=["POST"]),
        Route("/shim/gmail/archive", endpoint=gmail_archive, methods=["POST"]),
        Route("/shim/calendar/list", endpoint=calendar_list, methods=["POST"]),
        Route("/shim/calendar/search", endpoint=calendar_search, methods=["POST"]),
        Route("/shim/calendar/free-busy", endpoint=calendar_free_busy, methods=["POST"]),
        Route("/shim/calendar/create", endpoint=calendar_create, methods=["POST"]),
        Route("/shim/calendar/update", endpoint=calendar_update, methods=["POST"]),
        Route("/shim/calendar/delete", endpoint=calendar_delete, methods=["POST"]),
    ]
