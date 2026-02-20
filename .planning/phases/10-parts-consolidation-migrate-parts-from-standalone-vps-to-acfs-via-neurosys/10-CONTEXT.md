# Phase 10: Parts Deployment Pipeline - Context

**Gathered:** 2026-02-17
**Status:** Ready for planning

<domain>
## Phase Boundary

Establish a deployment pipeline where neurosys owns the deployment (nixos-rebuild switch) but the parts repo defines what gets deployed for its own components (containers, services, secrets via its existing NixOS module). Includes a deploy script, input tracking, health verification, and rollback documentation. Research of current deployment mechanism is included.

</domain>

<decisions>
## Implementation Decisions

### Deployment trigger
- Manual CLI command only — no CI/CD, no webhooks, no automation
- Deploy script lives at `scripts/deploy.sh` in the neurosys repo
- Supports two modes: local-push (build locally, push closure, switch remotely) and remote-self-deploy (SSH in, run on server)
- Every deploy is a full `nixos-rebuild switch` — no partial/container-only deploys
- NixOS handles incrementality natively (only changed derivations rebuild, only affected containers restart)

### Parts input tracking
- Parts is a git-based flake input tracking the `main` branch
- Deploy script automatically runs `nix flake update parts` before building
- Only the parts input is updated — other inputs (nixpkgs, home-manager, sops-nix) stay pinned in flake.lock
- Other inputs are updated on a deliberate, separate schedule (not during parts deploys)
- No tags or releases — main is the source of truth for parts

### Verification & health
- After `nixos-rebuild switch`, deploy script checks Docker container status for all parts containers
- On failure: print which containers aren't running, exit non-zero
- On success: brief summary showing container statuses, parts input revision deployed, and deploy duration
- No application-level health checks (e.g., Telegram bot ping) — container running = healthy enough

### Rollback & recovery
- Use NixOS generation rollback — no custom rollback tooling
- On deploy failure, the script's error output includes the rollback command to copy/paste (`nixos-rebuild switch --rollback`)
- Recovery flow: deploy fails → script shows error + rollback command → user runs rollback → previous generation activates → fix parts → redeploy

</decisions>

<specifics>
## Specific Ideas

- Deploy script should feel like a single-command operation: run it, see what happened, done
- Error output should be actionable — include the exact rollback command, not just "something went wrong"
- The parts flake input already exists from Phase 3.1 — this phase wires up the operational deploy workflow around it

</specifics>

<deferred>
## Deferred Ideas

- Automated deploys via CI/CD or git push hooks — potential future phase if manual becomes tedious
- Application-level health checks (Telegram bot responds, API returns 200) — could be added later
- Nixpkgs update schedule/automation — separate concern from parts deployment

</deferred>

---

*Phase: 10-parts-consolidation-migrate-parts-from-standalone-vps-to-acfs-via-neurosys*
*Context gathered: 2026-02-17*
