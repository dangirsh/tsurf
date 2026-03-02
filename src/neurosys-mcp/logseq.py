"""
Logseq org-mode vault tools for the neurosys MCP server.

@decision LOGSEQ-01: orgparse for org-mode parsing.
@rationale: In nixpkgs, handles TODO state, tags, properties, timestamps.
  No alternatives needed. Page-level #+title:/#+tags: extracted via regex
  (orgparse does not parse these as structured data).

@decision LOGSEQ-02: Read-only tools only. Write operations deferred.
@rationale: Establish read patterns and tool usage before adding mutations.
  Aligns with Phase 59 scope (query-only initially).

@decision LOGSEQ-03: Vault path via LOGSEQ_VAULT_PATH env var.
@rationale: DynamicUser service needs ProtectHome override in the NixOS
  module (Plan 59-02). Path is configurable, not hardcoded.
"""

from __future__ import annotations

import os
import re
from pathlib import Path
from typing import Any

import orgparse

VAULT_PATH = os.environ.get("LOGSEQ_VAULT_PATH", "")


def _pages_dir() -> Path:
    return Path(VAULT_PATH) / "pages"


def _journals_dir() -> Path:
    return Path(VAULT_PATH) / "journals"


def _extract_page_title(root_body: str, filename_stem: str) -> str:
    """Extract #+title: from page frontmatter, or fall back to filename."""
    match = re.search(r"#\+title:\s*(.+)", root_body, re.IGNORECASE)
    return match.group(1).strip() if match else filename_stem


def _extract_page_tags(root_body: str) -> list[str]:
    """Extract #+tags: from page frontmatter."""
    match = re.search(r"#\+tags:\s*(.+)", root_body, re.IGNORECASE)
    if not match:
        return []
    return [tag.strip() for tag in match.group(1).split(",") if tag.strip()]


def _vault_error() -> dict[str, Any] | None:
    if not VAULT_PATH:
        return {"ok": False, "error": "logseq_vault_path_not_configured"}
    if not Path(VAULT_PATH).is_dir():
        return {"ok": False, "error": f"logseq_vault_path_not_found: {VAULT_PATH}"}
    return None


def register(mcp_instance: Any) -> None:
    """Register Logseq tools on the given FastMCP instance."""

    @mcp_instance.tool()
    async def logseq_get_todos(
        state: str = "TODO",
        limit: int = 50,
        include_journals: bool = False,
    ) -> Any:
        """Return TODO blocks from the Logseq vault.

        Args:
            state: TODO keyword to filter (e.g. "TODO", "DONE", "DOING").
            limit: Maximum number of results to return.
            include_journals: If True, also scan journal files.
        """
        error = _vault_error()
        if error:
            return error
        if limit < 1:
            return {"ok": False, "error": "limit_must_be_positive"}
        if not state.strip():
            return {"ok": False, "error": "state_must_not_be_empty"}

        pages_dir = _pages_dir()
        if not pages_dir.is_dir():
            return {"ok": False, "error": f"logseq_pages_dir_not_found: {pages_dir}"}

        files = sorted(pages_dir.glob("*.org"))
        if include_journals and _journals_dir().is_dir():
            files.extend(sorted(_journals_dir().glob("*.org")))

        wanted_state = state.strip().upper()
        results: list[dict[str, Any]] = []
        for org_file in files:
            try:
                root = orgparse.load(str(org_file))
            except Exception:
                continue

            page = _extract_page_title(getattr(root, "body", ""), org_file.stem)
            for node in root[1:]:
                if str(node.todo or "").upper() != wanted_state:
                    continue
                results.append(
                    {
                        "file": org_file.name,
                        "page": page,
                        "heading": node.heading,
                        "todo": node.todo,
                        "tags": list(node.tags),
                        "scheduled": str(node.scheduled) if node.scheduled else None,
                        "deadline": str(node.deadline) if node.deadline else None,
                        "id": node.properties.get("id"),
                    }
                )
                if len(results) >= limit:
                    return {"ok": True, "count": len(results), "todos": results}

        return {"ok": True, "count": len(results), "todos": results}

    @mcp_instance.tool()
    async def logseq_search_pages(query: str, limit: int = 20) -> Any:
        """Search Logseq page titles by substring match.

        Args:
            query: Case-insensitive substring to match against page titles.
            limit: Maximum number of results to return.
        """
        error = _vault_error()
        if error:
            return error
        if not query.strip():
            return {"ok": False, "error": "query_must_not_be_empty"}
        if limit < 1:
            return {"ok": False, "error": "limit_must_be_positive"}

        pages_dir = _pages_dir()
        if not pages_dir.is_dir():
            return {"ok": False, "error": f"logseq_pages_dir_not_found: {pages_dir}"}

        needle = query.strip().lower()
        results: list[dict[str, str]] = []
        for org_file in sorted(pages_dir.glob("*.org")):
            stem = org_file.stem
            if needle in stem.lower():
                results.append({"page": stem, "file": org_file.name})
            if len(results) >= limit:
                break

        return {"ok": True, "count": len(results), "pages": results}

    @mcp_instance.tool()
    async def logseq_get_page(page_name: str) -> Any:
        """Return full content of a Logseq page by name.

        Returns structured data: title, tags, and all heading blocks
        with their TODO state, tags, properties, and body text.

        Args:
            page_name: Exact page filename stem (without .org extension).
        """
        error = _vault_error()
        if error:
            return error
        if not page_name.strip():
            return {"ok": False, "error": "page_name_must_not_be_empty"}

        pages_dir = _pages_dir()
        if not pages_dir.is_dir():
            return {"ok": False, "error": f"logseq_pages_dir_not_found: {pages_dir}"}

        org_file = pages_dir / f"{page_name}.org"
        if not org_file.exists():
            return {"ok": False, "error": f"page not found: {page_name}"}

        try:
            root = orgparse.load(str(org_file))
        except Exception as exc:
            return {"ok": False, "error": f"logseq_parse_error: {exc}"}

        root_body = getattr(root, "body", "")
        title = _extract_page_title(root_body, org_file.stem)
        page_tags = _extract_page_tags(root_body)

        blocks: list[dict[str, Any]] = []
        for node in root[1:]:
            blocks.append(
                {
                    "level": node.level,
                    "heading": node.heading,
                    "todo": node.todo,
                    "tags": list(node.tags),
                    "properties": dict(node.properties),
                    "body": node.body,
                    "id": node.properties.get("id"),
                }
            )

        try:
            raw = org_file.read_text()
        except Exception as exc:
            return {"ok": False, "error": f"logseq_read_error: {exc}"}

        return {
            "ok": True,
            "page": title,
            "tags": page_tags,
            "blocks": blocks,
            "raw": raw,
        }
