# Phase 59: Logseq PKM Agent Suite - Context

**Gathered:** 2026-03-02
**Status:** Ready for planning

<domain>
## Phase Boundary

Build the infrastructure that makes the Logseq PKM vault an agent-accessible knowledge interface:
a private repo (`logseq-agent-suite`) with tooling + agent instruction files, a neurosys private
overlay NixOS module exposing the vault to agentd agents, and new Logseq query tools added to the
existing neurosys MCP server. The vault is already synced to neurosys via Syncthing.

</domain>

<decisions>
## Implementation Decisions

### Vault format
- The Logseq graph is **org-mode format** (not markdown) — all tooling must handle `.org` files
- This is the critical constraint: org-specific parsing is required for properties, TODO states,
  tags, scheduled/deadline timestamps, and block structure

### Vault access model
- **Direct filesystem read/write** — no Logseq app dependency, works headless on neurosys
- Research whether better org-mode tooling exists for agent use (e.g. org-ruby, pandoc org support,
  Python orgparse/orgparse2, or Emacs batch-mode with org-agenda). Prefer a library/CLI that
  understands org structure semantically, not just raw text.
- The NixOS module exposes the vault path as a config value (e.g. `services.logseq-mcp.vaultPath`)
  so agents and the MCP server can find it without hardcoding

### Agent instruction files
- Derive the "todo triage" flow from the existing **"agentic-dev todo review"** page in the graph
  — researcher should read that page as the authoritative spec for what the triage flow does
- One instruction file per distinct flow (triage, graph maintenance, review) — not a unified blob
- Format: SOUL.md-style (plain prose instructions, not structured YAML) so agents can read them
  as system prompt context

### Parts-agent interface
- **Extend the existing neurosys MCP server** (port 8400) with new Logseq tools — no separate
  service or repo needed
- **Query-only initially** — read operations first (search pages, get todo list, query by tag/date),
  write operations in a future phase once read patterns are established
- Tool naming convention follows existing MCP tools: `logseq_search_pages`, `logseq_get_todos`,
  `logseq_query_tagged`, etc.

### Query library scope
- **Build organically** — no upfront library of Datalog queries to implement
- Start with what the MCP tools need; add queries as actual agent usage reveals patterns
- Document queries in the repo as they accumulate, not before

### Claude's Discretion
- Choice of org-mode parsing library (after researching available options)
- MCP tool input/output schema design
- Instruction file prose style and level of detail
- NixOS module option names and structure

</decisions>

<specifics>
## Specific Ideas

- Read the "agentic-dev todo review" page in the Logseq graph before writing any instruction files
  — it defines the existing triage workflow and should be the source of truth
- The vault path on neurosys will be somewhere under the Syncthing-managed folder;
  researcher should confirm the exact path (likely `/home/dangirsh/Sync/` or similar)
- The MCP server already has a FastMCP + sops pattern established (Phase 45) — new Logseq tools
  follow the same module structure in the private overlay

</specifics>

<deferred>
## Deferred Ideas

- Write operations in the MCP (journal entries, task creation, page modification) — future phase
  once read patterns are established
- Datalog query library as a standalone deliverable — will grow from real usage organically
- Homepage dashboard widget for PKM status — own phase if ever needed
- Restic backup coverage for the Logseq graph — already covered by blanket `/` backup with
  Syncthing folder included

</deferred>

---

*Phase: 59-logseq-pkm-agent-suite*
*Context gathered: 2026-03-02*
