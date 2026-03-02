"""
Google Calendar MCP tools for the neurosys MCP server.

@decision CAL-01: httpx for Calendar REST API calls.
@rationale: Same pattern as gmail.py. Bearer token from google_auth.

@decision CAL-02: Primary calendar only.
@rationale: Personal use. No multi-calendar support needed.

@decision CAL-03: File named calendar_tools.py to avoid stdlib shadow.
@rationale: Python stdlib has a 'calendar' module. Using 'calendar.py' would shadow it.
"""

from __future__ import annotations

from typing import Any
from urllib.parse import quote

import httpx

import google_auth as _google_auth

CALENDAR_API = "https://www.googleapis.com/calendar/v3"


def _google_auth_required() -> dict[str, Any]:
    return {"ok": False, "error": "google_auth_required"}


def _event_time(value: dict[str, Any] | None) -> str | None:
    if not value:
        return None
    return value.get("dateTime") or value.get("date")


def _format_event(event: dict[str, Any]) -> dict[str, Any]:
    return {
        "id": event.get("id"),
        "summary": event.get("summary"),
        "start": _event_time(event.get("start")),
        "end": _event_time(event.get("end")),
        "location": event.get("location"),
        "description": event.get("description"),
        "status": event.get("status"),
        "attendees": [
            attendee.get("email")
            for attendee in event.get("attendees", [])
            if attendee.get("email")
        ],
        "html_link": event.get("htmlLink"),
    }


def _time_field(value: str) -> dict[str, str]:
    if "T" in value:
        return {"dateTime": value}
    return {"date": value}


def _attendee_payload(attendees: list[str]) -> list[dict[str, str]]:
    payload: list[dict[str, str]] = []
    for attendee in attendees:
        email = attendee.strip()
        if email:
            payload.append({"email": email})
    return payload


async def _cal_request(method: str, path: str, **kwargs: Any) -> dict[str, Any]:
    if not _google_auth._google_configured():
        return _google_auth_required()

    token = await _google_auth.get_access_token()
    if not token:
        return _google_auth_required()

    headers = kwargs.pop("headers", {})
    headers["Authorization"] = f"Bearer {token}"
    url = f"{CALENDAR_API}{path}"

    try:
        async with httpx.AsyncClient(timeout=20.0) as client:
            response = await client.request(method, url, headers=headers, **kwargs)
    except httpx.HTTPError as exc:
        return {"ok": False, "error": "calendar_request_failed", "details": str(exc)}

    if response.status_code in {401, 403}:
        return _google_auth_required()

    if response.status_code >= 400:
        try:
            details = response.json()
        except ValueError:
            details = {"body": response.text[:500]}
        return {
            "ok": False,
            "error": "calendar_api_error",
            "status_code": response.status_code,
            "details": details,
        }

    if response.status_code == 204:
        return {"ok": True, "data": {}}

    try:
        return {"ok": True, "data": response.json()}
    except ValueError:
        return {"ok": False, "error": "calendar_invalid_response"}


def register(mcp_instance: Any) -> None:
    """Register Google Calendar tools on the given FastMCP instance."""

    @mcp_instance.tool()
    async def calendar_list(time_min: str, time_max: str, max_results: int = 10) -> dict[str, Any]:
        """List calendar events in a time range. Times must be RFC 3339."""
        response = await _cal_request(
            "GET",
            "/calendars/primary/events",
            params={
                "timeMin": time_min,
                "timeMax": time_max,
                "maxResults": max(1, min(max_results, 250)),
                "singleEvents": "true",
                "orderBy": "startTime",
            },
        )
        if not response.get("ok"):
            return response

        items = response["data"].get("items", [])
        return {
            "ok": True,
            "count": len(items),
            "events": [_format_event(event) for event in items],
        }

    @mcp_instance.tool()
    async def calendar_search(
        query: str,
        time_min: str | None = None,
        time_max: str | None = None,
        max_results: int = 10,
    ) -> dict[str, Any]:
        """Search calendar events by text query."""
        params: dict[str, Any] = {
            "q": query,
            "maxResults": max(1, min(max_results, 250)),
            "singleEvents": "true",
            "orderBy": "startTime",
        }
        if time_min:
            params["timeMin"] = time_min
        if time_max:
            params["timeMax"] = time_max

        response = await _cal_request("GET", "/calendars/primary/events", params=params)
        if not response.get("ok"):
            return response

        items = response["data"].get("items", [])
        return {
            "ok": True,
            "query": query,
            "count": len(items),
            "events": [_format_event(event) for event in items],
        }

    @mcp_instance.tool()
    async def calendar_free_busy(time_min: str, time_max: str) -> dict[str, Any]:
        """Return busy periods for the primary calendar in a time range."""
        response = await _cal_request(
            "POST",
            "/freeBusy",
            json={
                "timeMin": time_min,
                "timeMax": time_max,
                "items": [{"id": "primary"}],
            },
        )
        if not response.get("ok"):
            return response

        busy = response["data"].get("calendars", {}).get("primary", {}).get("busy", [])
        return {
            "ok": True,
            "busy_periods": [{"start": item.get("start"), "end": item.get("end")} for item in busy],
        }

    @mcp_instance.tool()
    async def calendar_create(
        summary: str,
        start: str,
        end: str,
        description: str | None = None,
        attendees: list[str] | None = None,
        location: str | None = None,
    ) -> dict[str, Any]:
        """Create a calendar event on the primary calendar."""
        event: dict[str, Any] = {
            "summary": summary,
            "start": _time_field(start),
            "end": _time_field(end),
        }
        if description is not None:
            event["description"] = description
        if location is not None:
            event["location"] = location
        if attendees is not None:
            event["attendees"] = _attendee_payload(attendees)

        response = await _cal_request("POST", "/calendars/primary/events", json=event)
        if not response.get("ok"):
            return response

        return {"ok": True, "event": _format_event(response["data"])}

    @mcp_instance.tool()
    async def calendar_update(
        event_id: str,
        summary: str | None = None,
        start: str | None = None,
        end: str | None = None,
        description: str | None = None,
        attendees: list[str] | None = None,
        location: str | None = None,
    ) -> dict[str, Any]:
        """Update an existing primary-calendar event by id."""
        safe_event_id = quote(event_id, safe="")
        existing_response = await _cal_request("GET", f"/calendars/primary/events/{safe_event_id}")
        if not existing_response.get("ok"):
            return existing_response

        event = existing_response["data"]
        if summary is not None:
            event["summary"] = summary
        if start is not None:
            event["start"] = _time_field(start)
        if end is not None:
            event["end"] = _time_field(end)
        if description is not None:
            event["description"] = description
        if location is not None:
            event["location"] = location
        if attendees is not None:
            event["attendees"] = _attendee_payload(attendees)

        response = await _cal_request(
            "PUT",
            f"/calendars/primary/events/{safe_event_id}",
            json=event,
        )
        if not response.get("ok"):
            return response

        return {"ok": True, "event": _format_event(response["data"])}

    @mcp_instance.tool()
    async def calendar_delete(event_id: str) -> dict[str, Any]:
        """Delete an existing primary-calendar event by id."""
        safe_event_id = quote(event_id, safe="")
        response = await _cal_request("DELETE", f"/calendars/primary/events/{safe_event_id}")
        if not response.get("ok"):
            return response

        return {"ok": True, "event_id": event_id}
