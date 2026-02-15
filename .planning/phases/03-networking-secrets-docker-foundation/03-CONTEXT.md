# Phase 3: Networking + Secrets + Docker Foundation - Context

**Gathered:** 2026-02-15
**Status:** Ready for planning

<domain>
## Phase Boundary

Tailscale VPN, full secrets management, and Docker engine work together without firewall conflicts on the live NixOS system. This phase delivers the networking and security infrastructure that all service phases (4, 6, 7) depend on.

**Project vision:** This is a generic infrastructure repo for a beefy VPS that runs the user's life — small projects/demos, agents (via parts flake), lots of personal data, and a Tailscale connection to home WiFi for home automation. The base repo should NOT include project-specific details; those come via flake inputs (like parts) or later phases.

</domain>

<decisions>
## Implementation Decisions

### Firewall (nftables)
- Default deny inbound on public interface (eth0)
- Public inbound allow: SSH (22), HTTP (80), HTTPS (443), Syncthing (22000)
- Tailscale interface: allow all traffic (already authenticated by Tailscale)
- Docker runs with `--iptables=false` — NixOS owns the firewall, not Docker
- Container ports bind to 127.0.0.1 or Tailscale IP only; Caddy is the only thing on public 80/443

### Tailscale
- Auth via sops-encrypted authkey, applied automatically at activation
- Accept routes enabled (reach home network devices)
- MagicDNS enabled
- No exit node (server is not a relay)
- No subnet router
- Reverse path filter set to loose mode on tailscale0 (required for Tailscale routing)

### fail2ban
- SSH: ban after 5 failures, 10 min ban, progressive escalation for repeat offenders
- Whitelist Tailscale subnet (100.64.0.0/10) — never ban Tailscale peers
- Monitor SSH only (everything else behind Tailscale or Docker)

### Docker Engine
- `--iptables=false` — no Docker firewall bypass
- Bridge networks for inter-container communication
- Container ports needing public access go through Caddy (reverse proxy), not direct port binding
- Docker socket not exposed to containers

### Secrets (sops-nix)
- Tailscale authkey
- B2 credentials (consumed in Phase 7)
- SSH host keys (already bootstrapped in Phase 1)
- Project-specific secrets imported via flake modules (like parts already does)
- Everything decrypts to /run/secrets/

### Claude's Discretion
- Exact nftables rule structure and chain organization
- fail2ban jail configuration details
- Docker daemon.json structure
- Tailscale NixOS module options beyond what's specified above

</decisions>

<specifics>
## Specific Ideas

- "I want the best security defaults that won't interfere with these usecases"
- Base repo is generic infrastructure — no project-specific container or service declarations
- SSH access is the primary management interface
- Home automation via Tailscale connection to home WiFi is a key use case for accept-routes

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 03-networking-secrets-docker-foundation*
*Context gathered: 2026-02-15*
