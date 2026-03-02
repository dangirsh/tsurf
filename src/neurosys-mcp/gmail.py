"""
Gmail MCP tools for the neurosys MCP server.

@decision MCP-63-04: Implement Gmail calls directly with httpx + REST endpoints.
@rationale Keeps runtime lightweight and avoids google-api-python-client overhead.

@decision MCP-63-05: Centralize auth handling in _gmail_request.
@rationale Ensures all Gmail tools return the same google_auth_required error shape.
"""

from __future__ import annotations

import base64
from email.mime.text import MIMEText
from typing import Any

import httpx

import google_auth as _google_auth

GMAIL_API = "https://gmail.googleapis.com/gmail/v1/users/me"


def _google_auth_required() -> dict[str, Any]:
    return {"ok": False, "error": "google_auth_required"}


async def _gmail_request(method: str, path: str, **kwargs: Any) -> dict[str, Any]:
    if not _google_auth._google_configured():
        return _google_auth_required()

    token = await _google_auth.get_access_token()
    if not token:
        return _google_auth_required()

    url = f"{GMAIL_API}{path}"
    headers = kwargs.pop("headers", {})
    headers["Authorization"] = f"Bearer {token}"

    try:
        async with httpx.AsyncClient(timeout=20.0) as client:
            response = await client.request(method, url, headers=headers, **kwargs)
    except httpx.HTTPError as exc:
        return {
            "ok": False,
            "error": "gmail_request_failed",
            "details": str(exc),
        }

    if response.status_code in {401, 403}:
        return _google_auth_required()

    if response.status_code >= 400:
        try:
            error_data = response.json()
        except ValueError:
            error_data = {"body": response.text[:500]}

        return {
            "ok": False,
            "error": "gmail_api_error",
            "status_code": response.status_code,
            "details": error_data,
        }

    if response.status_code == 204:
        return {"ok": True, "data": {}}

    try:
        return {"ok": True, "data": response.json()}
    except ValueError:
        return {"ok": False, "error": "gmail_invalid_response"}


def _decode_base64url(content: str) -> str:
    if not content:
        return ""
    padding = "=" * (-len(content) % 4)
    try:
        data = base64.urlsafe_b64decode(content + padding)
    except Exception:
        return ""
    return data.decode("utf-8", errors="replace")


def _extract_body(payload: dict[str, Any], max_chars: int = 500) -> str:
    body_data = payload.get("body", {}).get("data", "")
    if body_data:
        text = _decode_base64url(body_data)
        return text[:max_chars]

    for part in payload.get("parts", []):
        mime_type = part.get("mimeType", "")
        if mime_type in {"text/plain", "text/html"}:
            part_body = part.get("body", {}).get("data", "")
            if part_body:
                text = _decode_base64url(part_body)
                return text[:max_chars]

        nested = _extract_body(part, max_chars=max_chars)
        if nested:
            return nested[:max_chars]

    return ""


def _extract_headers(payload: dict[str, Any]) -> dict[str, str]:
    result = {"from": "", "to": "", "subject": "", "date": ""}

    for header in payload.get("headers", []):
        name = str(header.get("name", "")).lower()
        value = str(header.get("value", ""))
        if name == "from":
            result["from"] = value
        elif name == "to":
            result["to"] = value
        elif name == "subject":
            result["subject"] = value
        elif name == "date":
            result["date"] = value

    return result


def _build_message_raw(to: str, subject: str, body: str) -> str:
    message = MIMEText(body)
    message["To"] = to
    message["Subject"] = subject
    encoded = base64.urlsafe_b64encode(message.as_bytes()).decode("utf-8")
    return encoded


def register(mcp_instance: Any) -> None:
    """Register Gmail tools on the given FastMCP instance."""

    @mcp_instance.tool()
    async def gmail_read(message_id: str, max_body_chars: int = 500) -> dict[str, Any]:
        """Read a Gmail message by id with extracted headers/body."""
        response = await _gmail_request(
            "GET",
            f"/messages/{message_id}",
            params={"format": "full"},
        )
        if not response.get("ok"):
            return response

        message = response["data"]
        payload = message.get("payload", {})
        return {
            "ok": True,
            "message": {
                "id": message.get("id"),
                "thread_id": message.get("threadId"),
                "label_ids": message.get("labelIds", []),
                "snippet": message.get("snippet", ""),
                "headers": _extract_headers(payload),
                "body": _extract_body(payload, max_chars=max_body_chars),
            },
        }

    @mcp_instance.tool()
    async def gmail_search(query: str, max_results: int = 10) -> dict[str, Any]:
        """Search Gmail messages and return metadata for each match."""
        list_resp = await _gmail_request(
            "GET",
            "/messages",
            params={
                "q": query,
                "maxResults": max(1, min(max_results, 50)),
            },
        )
        if not list_resp.get("ok"):
            return list_resp

        message_refs = list_resp["data"].get("messages", [])
        results: list[dict[str, Any]] = []
        for ref in message_refs:
            message_id = ref.get("id")
            if not message_id:
                continue

            meta_resp = await _gmail_request(
                "GET",
                f"/messages/{message_id}",
                params={
                    "format": "metadata",
                    "metadataHeaders": ["From", "To", "Subject", "Date"],
                },
            )
            if not meta_resp.get("ok"):
                if meta_resp.get("error") == "google_auth_required":
                    return meta_resp
                continue

            msg = meta_resp["data"]
            payload = msg.get("payload", {})
            results.append(
                {
                    "id": msg.get("id"),
                    "thread_id": msg.get("threadId"),
                    "snippet": msg.get("snippet", ""),
                    "headers": _extract_headers(payload),
                }
            )

        return {
            "ok": True,
            "query": query,
            "count": len(results),
            "messages": results,
        }

    @mcp_instance.tool()
    async def gmail_draft(to: str, subject: str, body: str) -> dict[str, Any]:
        """Create a Gmail draft message."""
        raw = _build_message_raw(to=to, subject=subject, body=body)
        response = await _gmail_request(
            "POST",
            "/drafts",
            json={"message": {"raw": raw}},
        )
        if not response.get("ok"):
            return response

        draft = response["data"]
        return {
            "ok": True,
            "draft_id": draft.get("id"),
            "message_id": draft.get("message", {}).get("id"),
        }

    @mcp_instance.tool()
    async def gmail_send(to: str, subject: str, body: str) -> dict[str, Any]:
        """Send a Gmail message immediately."""
        raw = _build_message_raw(to=to, subject=subject, body=body)
        response = await _gmail_request(
            "POST",
            "/messages/send",
            json={"raw": raw},
        )
        if not response.get("ok"):
            return response

        sent = response["data"]
        return {
            "ok": True,
            "message_id": sent.get("id"),
            "thread_id": sent.get("threadId"),
            "label_ids": sent.get("labelIds", []),
        }

    @mcp_instance.tool()
    async def gmail_archive(message_id: str) -> dict[str, Any]:
        """Archive a Gmail message by removing the INBOX label."""
        response = await _gmail_request(
            "POST",
            f"/messages/{message_id}/modify",
            json={"removeLabelIds": ["INBOX"]},
        )
        if not response.get("ok"):
            return response

        data = response["data"]
        return {
            "ok": True,
            "message_id": data.get("id", message_id),
            "label_ids": data.get("labelIds", []),
        }
