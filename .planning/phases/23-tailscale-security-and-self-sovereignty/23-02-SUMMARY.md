---
phase: 23-tailscale-security-and-self-sovereignty
plan: 02
subsystem: infra
tags: [tailscale, tka, acl, security, human-action]

requires:
  - phase: 23-01
    provides: "Port 22 hardening verified, TKA operational runbook"
provides:
  - "Tailnet Key Authority enabled — all nodes signed"
  - "ACL policy tightened with grants + tag:server"
  - "Node key expiry configured per device class"
  - "Pre-signed one-time auth key in sops-nix for DR deployments"

tech-stack:
  added: []
  patterns: ["tailscale-lock", "tailscale-acl-grants"]

key-files:
  created: []
  modified:
    - secrets/neurosys.yaml

key-decisions:
  - "TKA initialization executed on live server — all existing nodes signed"
  - "ACL policy migrated to grants-based model with tag:server for neurosys"
  - "Server node key expiry disabled (tag:server); personal devices 180-day expiry"
  - "New one-time pre-signed auth key stored in sops-nix for nixos-anywhere DR redeployment"

duration: human-action
completed: 2026-02-27
---

# Phase 23 Plan 02: TKA Initialization + ACL Hardening Summary

**Tailnet Key Authority enabled and all nodes signed; ACL policy tightened with grants-based model and tag:server; pre-signed DR auth key in sops-nix**

## Performance

- **Duration:** human-interactive
- **Completed:** 2026-02-27
- **Tasks:** 3 (all human-action checkpoints)

## Accomplishments

- Tailnet Key Authority (TKA) initialized — `tailscale lock init` executed on signing node
- All existing tailnet nodes signed; disablement secrets stored in password manager + offline backup
- ACL policy migrated to grants-based model: `tag:server` on neurosys, members → servers on all ports
- Node key expiry configured: disabled for `tag:server` (neurosys), 180-day default for personal devices
- MagicDNS verified functional — `neurosys` resolves correctly within tailnet
- New one-time tagged auth key generated, pre-signed with TKA, updated in `secrets/neurosys.yaml`
- SSH Tailscale-only verified: public IP port 22 unreachable, `ssh root@neurosys` works via MagicDNS

## Files Created/Modified

- `secrets/neurosys.yaml` — Updated `tailscale-authkey` with new pre-signed one-time tagged key

## Decisions Made

- TKA initialization requires 2+ signing nodes; executed with neurosys + local laptop
- Disablement secrets stored in 2 locations (password manager + offline) per security policy
- `tag:server` applied to neurosys in Tailscale admin console to disable key expiry for server node
- Auth key rotation policy: generate new one-time key + pre-sign before each `nixos-anywhere` redeploy

## Issues Encountered

None

## Next Phase Readiness

- Phase 23 complete — Tailscale security posture fully hardened
- Disablement secrets safely stored; auth key rotation policy documented in recovery runbook

---
*Phase: 23-tailscale-security-and-self-sovereignty*
*Completed: 2026-02-27*
