---
phase: 59-logseq-pkm-agent-suite
plan: 02
subsystem: infra
tags: [nix, private-overlay, logseq, github, agent-instructions]

requires:
  - phase: 59-01
    provides: logseq MCP tools in public neurosys-mcp package

provides:
  - Private overlay wired with LOGSEQ_VAULT_PATH=/home/dangirsh/Sync/logseq
  - ProtectHome="read-only" + ReadOnlyPaths for vault access
  - dangirsh/logseq-agent-suite GitHub repo with 3 instruction files
  - logseq-agent-suite added to activation repo cloning list

affects: []

tech-stack:
  added: []
  patterns: [vaultPath let binding for DynamicUser vault read access]

key-files:
  created: [/data/projects/logseq-agent-suite/README.md, instructions/triage.md, instructions/graph-maintenance.md, instructions/review.md]
  modified: [private-neurosys/modules/neurosys-mcp.nix, private-neurosys/modules/repos.nix]

key-decisions:
  - "LOGSEQ-04: Vault path hardcoded to /home/dangirsh/Sync/logseq (confirmed by user, Syncthing-managed)"
  - "LOGSEQ-05: ProtectHome changed from true to read-only so DynamicUser can read vault via ReadOnlyPaths"
  - "Vault not yet synced to server — logseq tools will degrade gracefully until Syncthing sync completes"
  - "Triage instructions use skeleton (actual agentic-dev page not readable — vault unsynced)"

duration: 15min
completed: 2026-03-02
---

# Phase 59 Plan 02: Private Overlay + logseq-agent-suite Repo Summary

**Logseq vault path wired into private neurosys-mcp overlay; logseq-agent-suite GitHub repo created with 3 SOUL.md-style instruction files**

## Performance

- **Duration:** ~15 min
- **Started:** 2026-03-02T12:40:00Z
- **Completed:** 2026-03-02T12:55:00Z
- **Tasks:** 6/7 (59-02-A vault SSH confirmation was done via user input; 59-02-C page read was skipped — vault not synced)
- **Files modified:** 5

## Accomplishments

- `private-neurosys/modules/neurosys-mcp.nix`: added `LOGSEQ_VAULT_PATH` env var, changed `ProtectHome = true` → `"read-only"`, added `ReadOnlyPaths = [ vaultPath ]` with LOGSEQ-04/LOGSEQ-05 annotations
- `private-neurosys/modules/repos.nix`: added `dangirsh/logseq-agent-suite` to the activation cloning list
- Created `dangirsh/logseq-agent-suite` private GitHub repo at https://github.com/dangirsh/logseq-agent-suite
- Wrote `instructions/triage.md`, `instructions/graph-maintenance.md`, `instructions/review.md` (SOUL.md-style, read-only MCP tool references)
- `nix flake check` passes (18 checks, both nixosConfigurations)

## Task Commits

1. **Task 59-02-B/F/G: Private overlay changes** — `a2ca409` (feat: vault path, ProtectHome, repos)
2. **Task 59-02-D/E: logseq-agent-suite repo** — `577cd4f` (feat: initial repo + instructions)

## Files Created/Modified

- `private-neurosys/modules/neurosys-mcp.nix` — LOGSEQ_VAULT_PATH + ProtectHome override + ReadOnlyPaths
- `private-neurosys/modules/repos.nix` — logseq-agent-suite added to clone list
- `/data/projects/logseq-agent-suite/README.md` — repo purpose, structure, vault path
- `/data/projects/logseq-agent-suite/instructions/triage.md` — TODO triage workflow
- `/data/projects/logseq-agent-suite/instructions/graph-maintenance.md` — graph cleanup
- `/data/projects/logseq-agent-suite/instructions/review.md` — knowledge review

## Decisions Made

- **LOGSEQ-04**: Vault path hardcoded to `/home/dangirsh/Sync/logseq` (user confirmed; Syncthing-managed, stable path)
- **LOGSEQ-05**: `ProtectHome = "read-only"` required — `true` makes `/home` completely inaccessible even with `ReadOnlyPaths`. Downgrading to `"read-only"` grants read access to listed paths while keeping rest of `/home` read-only.
- Vault not synced at plan time (only `.stfolder` present) — tools will return `{"ok": false, "error": "logseq_pages_dir_not_found"}` until Syncthing syncs the vault.
- Triage instruction file uses Plan skeleton content (actual "agentic-dev todo review" page not readable until vault syncs).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Vault not accessible via SSH during task 59-02-A**
- **Found during:** Task 59-02-A (SSH to confirm vault path)
- **Issue:** Tailscale connectivity to `neurosys` timed out. Fallback IP `100.104.43.26` succeeded but vault at `/home/dangirsh/Sync/logseq` not synced yet (only `.stfolder` present).
- **Fix:** User confirmed path as `Sync/logseq`. Proceeded with hardcoded path knowing vault will sync later. Tools degrade gracefully.
- **Verification:** `nix flake check` passes; graceful degradation path confirmed in logseq.py.

**2. [Rule 1 - Bug] Task 59-02-C skipped — triage page not readable**
- **Found during:** Task 59-02-C (read agentic-dev todo review page via SSH)
- **Issue:** Vault not synced; no .org files present on server.
- **Fix:** Used Plan skeleton content for `triage.md`. Can be updated once vault syncs.

---

**Total deviations:** 2 auto-handled (1 blocking unblocked by user input, 1 deferred content)
**Impact:** No functional impact. Tools degrade gracefully until Syncthing syncs. Triage instructions are functional with skeleton content.

## Issues Encountered

- Tailscale SSH to `neurosys` MagicDNS hostname timed out; Contabo direct IP worked
- Logseq vault not yet synced to server — only Syncthing `.stfolder` present

## Next Phase Readiness

Phase 59 complete. To activate:
1. Deploy private overlay: `cd /data/projects/private-neurosys && ./scripts/deploy.sh`
2. Verify `LOGSEQ_VAULT_PATH` in service: `ssh root@neurosys "systemctl show neurosys-mcp --property=Environment"`
3. Once Syncthing syncs vault, test: `logseq_get_todos` should return vault TODOs

---
*Phase: 59-logseq-pkm-agent-suite*
*Completed: 2026-03-02*
