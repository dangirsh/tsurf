---
milestone: v1.0
audited: 2026-02-15
status: gaps_found
scores:
  requirements: 18/37
  phases: 4/9
  integration: 15/15
  flows: 3/4
gaps:
  requirements:
    - "DOCK-02: claw-swap stack not configured (Phase 4 not started)"
    - "DOCK-03: grok-mcp container not configured (Phase 4 not started)"
    - "DOCK-04: Docker networks for claw-swap not declared (Phase 4 not started)"
    - "SVC-01: Ollama service not configured (Phase 4 not started)"
    - "DEV-01 through DEV-05: No development tools configured (Phase 5 not started)"
    - "HOME-01 through HOME-05: No home-manager shell/tmux/atuin (Phase 5 not started)"
    - "SVC-02: Syncthing not configured (Phase 6 not started)"
    - "SVC-03: CASS indexer not configured (Phase 6 not started)"
    - "AGENT-01: global-agent-conf clone/symlink not configured (Phase 6 not started)"
    - "AGENT-02: Infrastructure repo cloning not configured (Phase 6 not started)"
    - "BACK-01: Restic backups not configured (Phase 7 not started)"
  integration:
    - "Parts flake uses path: URI — must change to github: before deployment"
    - "Host key mismatch between neurosys .sops.yaml and parts .sops.yaml"
    - "acfs secrets contain placeholder values — deployment will fail"
  flows:
    - "Secrets decryption pipeline: broken at step 1 (placeholder values)"
tech_debt:
  - phase: 02-bootable-base-system
    items:
      - "Plan 02 (nixos-anywhere deployment) not executed — human-interactive, deferred"
      - "Root SSH key still declared in users.nix despite PermitRootLogin=no"
      - "NAT externalInterface=eth0 unverified on Contabo (may be ens3)"
  - phase: 03-networking-secrets-docker-foundation
    items:
      - "Secret placeholders need real values before deployment"
  - phase: 03.1-parts-migration
    items:
      - "Parts flake input uses path: (local dev) — must become github: for production"
      - "Host age key in parts .sops.yaml differs from neurosys .sops.yaml"
  - phase: planning
    items:
      - "No VERIFICATION.md exists for any completed phase"
      - "Phase 2.1 TODOs need re-evaluation per Phase 9 context"
      - "Roadmap structure review needed (merge/reorder/drop phases)"
---

# Milestone v1.0 Audit

**Audited:** 2026-02-15
**Status:** gaps_found
**Core Value:** One command to deploy a fully working development server

## Requirements Coverage

| Requirement | Phase | Status | Notes |
|-------------|-------|--------|-------|
| BOOT-01 | 2 | Config-ready | NixOS config builds, awaiting deployment |
| BOOT-02 | 1 | Config-ready | disko partition layout defined |
| BOOT-03 | 2 | Blocked | nixos-anywhere not yet executed |
| BOOT-04 | 1 | Config-ready | GRUB hybrid BIOS+UEFI configured |
| BOOT-05 | 2 | Config-ready | Weekly GC in base.nix |
| BOOT-06 | 2 | Config-ready | Store optimization in base.nix |
| NET-01 | 2 | Config-ready | SSH key-only, root login disabled |
| NET-02 | 2 | Config-ready | nftables default-deny |
| NET-03 | 3 | Config-ready | Tailscale module configured |
| NET-04 | 2 | Config-ready | Ports 22/80/443/22000 open |
| NET-05 | 3 | Config-ready | fail2ban with progressive multipliers |
| NET-06 | 3 | Config-ready | Tailscale useRoutingFeatures=client |
| SEC-01 | 1 | Config-ready | sops-nix decrypts to /run/secrets/ |
| SEC-02 | 1 | Config-ready | Age key from SSH host key |
| SEC-03 | 3 | Partial | Secrets declared but contain placeholders |
| SYS-01 | 2 | Config-ready | dangirsh user with wheel+docker |
| SYS-02 | 2 | Config-ready | Hostname acfs, tz Europe/Berlin |
| DOCK-01 | 3 | Config-ready | Docker iptables=false |
| DEV-01 | 5 | **Not started** | — |
| DEV-02 | 5 | **Not started** | — |
| DEV-03 | 5 | **Not started** | — |
| DEV-04 | 5 | **Not started** | — |
| DEV-05 | 5 | **Not started** | — |
| HOME-01 | 5 | **Not started** | home-manager stub only |
| HOME-02 | 5 | **Not started** | — |
| HOME-03 | 5 | **Not started** | — |
| HOME-04 | 5 | **Not started** | — |
| HOME-05 | 5 | **Not started** | — |
| DOCK-02 | 4 | **Not started** | — |
| DOCK-03 | 4 | **Not started** | — |
| DOCK-04 | 4 | **Not started** | — |
| SVC-01 | 4 | **Not started** | — |
| SVC-02 | 6 | **Not started** | — |
| SVC-03 | 6 | **Not started** | — |
| AGENT-01 | 6 | **Not started** | — |
| AGENT-02 | 6 | **Not started** | — |
| BACK-01 | 7 | **Not started** | — |

**Summary:** 18/37 config-ready (awaiting deployment), 19/37 not started

## Phase Status

| Phase | Status | Plans | Requirements |
|-------|--------|-------|-------------|
| 1. Flake Scaffolding | Complete | 2/2 | BOOT-02, BOOT-04, SEC-01, SEC-02 |
| 2. Bootable Base | Partial | 1/2 | BOOT-01, BOOT-03, BOOT-05, BOOT-06, NET-01, NET-02, NET-04, SYS-01, SYS-02 |
| 2.1 Base Fixups | Not started | 0/TBD | None (advisory) |
| 3. Networking+Secrets+Docker | Complete | 2/2 | NET-03, NET-05, NET-06, SEC-03, DOCK-01 |
| 3.1 Parts Integration | Complete | 3/3 | None (inserted) |
| 4. Docker Services+Ollama | Not started | 0/TBD | DOCK-02, DOCK-03, DOCK-04, SVC-01 |
| 5. User Env+Dev Tools | Not started | 0/TBD | DEV-01-05, HOME-01-05 |
| 6. User Services+Agent | Not started | 0/TBD | SVC-02, SVC-03, AGENT-01, AGENT-02 |
| 7. Backups | Not started | 0/TBD | BACK-01 |
| 8. Neurosys Review | Complete | 1/1 | None (research) |
| 9. Audit & Simplify | Not started | 0/TBD | None (quality gate) |

## Integration Check

**Score: 15/15 exports connected, 0 orphaned**

All completed modules compose correctly. `nix flake check` passes. Cross-flake integration (parts → neurosys) works.

### Production Blockers (3)

1. **Parts flake uses `path:` URI** — `flake.nix:17` must change to `github:dangirsh/parts` before deployment
2. **acfs secrets contain placeholders** — `secrets/acfs.yaml` has `placeholder-replace-me` for all 4 secrets
3. **Host key mismatch** — neurosys `.sops.yaml` has `age1jgn7pqqf4h...`, parts `.sops.yaml` has `age1k55y5y...` — one is wrong

### Warnings (2)

1. **NAT externalInterface=eth0** — may be `ens3` on Contabo VPS (verify on deploy)
2. **Root SSH key still declared** — benign (PermitRootLogin=no) but should be cleaned up

## E2E Flows

| Flow | Status | Notes |
|------|--------|-------|
| Boot → SSH → User | Complete | All modules compose, nix flake check passes |
| Secrets Pipeline | Broken | Placeholders in acfs.yaml; host key mismatch |
| Docker Container Startup | Complete | Ordering, images, env templates all wired |
| Network Stack | Complete | nftables + Tailscale + fail2ban + Docker NAT compose |

## Unverified Phases

No VERIFICATION.md files exist for any phase. All phases were validated via `nix flake check` and full system build (`nix build .#nixosConfigurations.acfs.config.system.build.toplevel`), but formal verification was not run.

---
*Milestone: v1.0*
*Audited: 2026-02-15*
