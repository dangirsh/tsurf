# Phase 60: Dashboard DM Pairing & Backup Decrypt Guide - Context

**Gathered:** 2026-03-02
**Status:** Ready for planning

<domain>
## Phase Boundary

Self-hosted guide page linked from the neurosys homepage dashboard. Two workflows: (1) show QR codes for initial DM bridge pairing (Signal, WhatsApp, Telegram via mautrix), and (2) upload UI for message backup files to be decrypted and imported. This is an MVP for rare initial onboarding — not a polished product.

</domain>

<decisions>
## Implementation Decisions

### Scope & complexity
- MVP / quick and dirty — this page is used rarely (initial onboarding only)
- Minimal UI, no polish needed — just functional
- Hosted behind Tailscale (same access model as homepage)

### QR code pairing
- Page shows QR codes for linking each DM bridge (Signal, WhatsApp, Telegram)
- QR codes are generated/fetched from the mautrix bridge APIs
- One section per bridge with the QR and minimal instructions

### Backup upload & decrypt
- File upload UI on the page (drag-and-drop or file picker)
- Accepts backup files (Signal .backup, WhatsApp .zip, Telegram JSON export)
- Server-side decrypt + import into Matrix bridge / Spacebot LanceDB

### Claude's Discretion
- Technology choice for the page (static HTML with JS, Python server, etc.)
- Hosting approach (serve from homepage, standalone service, nginx location)
- How QR codes are fetched from bridge APIs
- Decrypt/import pipeline implementation details
- Any additional instructions beyond the QR codes themselves

</decisions>

<specifics>
## Specific Ideas

- "I want a simple page that shows QRs for initial linking + has an upload UI for the backups"
- "Everything else I can do by discussing with the agent" — the guide doesn't need to be comprehensive
- "I expect this to be rare, so just need an MVP to do the initial onboarding"
- "Quick and dirty"

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 60-dashboard-dm-pairing-backup-decrypt-guide*
*Context gathered: 2026-03-02*
