# Phase 28: User Context and Decisions

**Source:** /gsd:discuss-phase (via inline questions during /gsd:plan-phase 28)
**Date:** 2026-02-23

## Decisions (Locked)

### HOST-01: Target host is OVH (production)
dangirsh.org MUST be served from the OVH host (135.125.196.143), not Contabo.

### SECURITY-01: Minimize attack surface — nginx as unified reverse proxy
User priority: "secure + simple. don't want to worry that a vuln in either could give an attacker access to the full nixos node."

Implication: NixOS nginx handles ALL web traffic on ports 80/443 for both dangirsh.org and claw-swap.com. Docker Caddy is REMOVED from claw-swap. claw-swap app container binds to localhost only (not public port). This gives a single internet-facing process with minimal attack surface.

### WORKFLOW-01: Manual update workflow
Content updates: edit site → push to GitHub → `nix flake update dangirsh-site` in neurosys → deploy. No CI/CD automation.

## Claude's Discretion

- Hakyll build strategy (flake input vs nix derivation approach)
- ACME configuration details (email, staging vs production toggle)
- Cache-control headers for static assets
- www redirect handling
- Homepage dashboard entry
- dangirsh-site repo tracking in repos.nix
- Exact impermanence configuration for /var/lib/acme

## Deferred / Out of Scope

- CI/CD auto-deploy on site push
- Keeping NFS as fallback (fully decommission after cutover)
- Multiple hosts / round-robin (overkill for personal blog)
