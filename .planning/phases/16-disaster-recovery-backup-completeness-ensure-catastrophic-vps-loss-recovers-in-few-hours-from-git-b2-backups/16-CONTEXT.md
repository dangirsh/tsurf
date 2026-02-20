# Phase 16: Disaster Recovery & Backup Completeness - Context

**Gathered:** 2026-02-19
**Status:** Ready for planning

<domain>
## Phase Boundary

Ensure catastrophic VPS loss recovers in < 2 hours from `neurosys` git state + Backblaze B2 backups. Audit all stateful paths, close backup gaps, create a tested recovery runbook. This phase does NOT add new services or change backup infrastructure — it completes and documents what's already in place.

</domain>

<decisions>
## Implementation Decisions

### Recovery scope
- "Fully recovered" = all NixOS services running, all Docker containers healthy, all secrets decrypted, SSH access working
- Recovery flow: `nixos-anywhere` deploy from git → `restic restore` stateful data → minimal manual re-auth → verify services
- Target recovery time: < 2 hours total (30min deploy, 30min restore, 30min verify, 30min re-auth buffer)
- Manual re-auth list (unavoidable, document these):
  - Tailscale: generate fresh auth key in admin console
  - Home Assistant: device re-pairing only if `/var/lib/hass/` restore fails
  - No other services require external re-auth — everything else in sops secrets or git

### Backup coverage — gaps to close
- ADD `/etc/ssh/ssh_host_ed25519_key*` — without host key, sops-nix can't derive age key, no secrets decrypt
- ADD `/var/lib/docker/volumes/` — claw-swap PostgreSQL data is not reconstructible
- ADD `/var/lib/tailscale/` — avoids Tailscale re-auth if state survives restore
- SKIP `/var/lib/prometheus/` — accept metrics loss on catastrophic failure, Prometheus rebuilds from scratch (saves B2 cost)
- SKIP `/var/lib/fail2ban/` — reconstructible, low value
- Keep existing excludes: `.git/objects`, `node_modules`, `__pycache__`, `.direnv`, `result`, `/nix/store`
- RPO: 24 hours (daily backups) — acceptable for personal server

### Already covered (no changes needed)
- `/data/projects/` — code repos, agent configs, secrets yaml (encrypted)
- `/home/dangirsh/` — Syncthing config/data, home-manager state, podman storage
- `/var/lib/hass/` — Home Assistant state/database

### Runbook format
- Lives in git at `docs/recovery-runbook.md` (versioned with the config it documents)
- Numbered steps with verification checks after each — detailed enough for an agent to follow
- Includes exact commands, not descriptions
- Clearly separates: what's in git (config) vs what's in B2 (state) vs what needs manual re-auth
- Lists pre-requisites (local age key, SSH access to B2, fresh Tailscale auth key)

### Testing depth
- Dry-run restore to temporary directory on VPS + verify file integrity and completeness
- NOT a full wipe-and-rebuild (too risky on only VPS; nixos-anywhere deploy already proven)
- Run `restic check` (repo integrity) + `restic restore --target /tmp/restore-test/` + spot-check critical files
- Document what was verified vs what was assumed

### Claude's Discretion
- Exact restic path patterns for SSH host keys (glob vs explicit paths)
- Whether to add restic pre/post hooks for consistency (e.g., docker pause before backup)
- Runbook section organization and formatting
- Which files to spot-check during restore verification

</decisions>

<specifics>
## Specific Ideas

- SSH host key is the single most critical stateful file — without it, the entire sops-nix secret chain breaks
- The local admin age key (`age1vma7w9...`) lives on the workstation only — document that this is a separate backup concern (not server-side)
- claw-swap PostgreSQL: consider whether a `pg_dump` pre-backup hook is cleaner than backing up raw Docker volumes
- Runbook should reference the nixos-anywhere deployment experience from Phase 2/10 (already proven, known gotchas documented)

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 16-disaster-recovery-backup-completeness*
*Context gathered: 2026-02-19*
