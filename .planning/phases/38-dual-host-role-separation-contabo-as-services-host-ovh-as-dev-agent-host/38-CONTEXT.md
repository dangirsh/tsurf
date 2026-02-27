# Phase 38: Dual-host role separation - Context

**Gathered:** 2026-02-27
**Status:** Ready for planning

<domain>
## Phase Boundary

Reorganize all NixOS modules and services across two VPS hosts to establish clean role separation: Contabo = services host (HA, Spacebot, Matrix, monitoring, claw-swap, Parts), OVH = dev-agent host (agent-compute, Claude/Codex, sandbox, agent-spawn). Audit current module allocation, migrate misplaced services/modules, ensure deploy.sh covers both targets, verify Tailscale MagicDNS reachability for both.

</domain>

<decisions>
## Implementation Decisions

### Service allocation by host

**Contabo (services host) — runs these, not OVH:**
- Home Assistant + ESPHome
- Spacebot
- Matrix (Conduit + mautrix bridges)
- claw-swap (PostgreSQL + app service)
- Parts Docker containers (parts-agent, parts-tools)
- Conway Automaton systemd service
- Homepage dashboard (single dashboard showing all Contabo services)
- Restic backups (all important stateful data lives on Contabo)

**OVH (dev-agent host) — runs these, not Contabo:**
- repos.nix (repo cloning activation scripts)
- agent-config.nix (~/.claude and ~/.codex symlinks)

**Both hosts:**
- Prometheus + node_exporter (each host runs its own independent instance — no cross-host scraping)
- agent-compute.nix (claude-code, codex, agent-spawn, bubblewrap sandbox) — agents may run on either host
- Secret proxy (port 9091, ANTHROPIC_BASE_URL injection) — agents run on both hosts, both need the proxy
- CASS indexer — both hosts have repos worth indexing
- Syncthing — both hosts participate in the Syncthing mesh (OVH syncs /data/projects agent workspace, Contabo syncs its own state)
- Base infrastructure: base.nix, networking.nix, users.nix, secrets.nix, docker.nix

### Module split strategy

Use the existing pattern: shared `modules/` directory, each host's `default.nix` imports only what it needs. No new directory structure — the existing `hosts/neurosys/default.nix` (Contabo) and `hosts/ovh/default.nix` (OVH) already use this pattern (e.g., `modules/nginx.nix` is OVH-only today).

### Migration execution

- **Approach**: Restructure config first (all module import changes in one pass), then redeploy both hosts. Cleaner git history than one-service-at-a-time.
- **What to add to `hosts/ovh/default.nix`**: repos.nix, agent-config.nix, cass.nix, syncthing.nix, agent-compute.nix, secret-proxy.nix, monitoring.nix
- **What to remove from `hosts/ovh/default.nix`** (if imported there): homepage.nix, restic.nix (Contabo-only)
- **What to verify in `hosts/neurosys/default.nix`** (Contabo): homepage.nix and restic.nix present, repos.nix and agent-config.nix removed or kept only if there's a Contabo-specific need

### Cross-host connectivity

- **Tailscale MagicDNS for all inter-host traffic** — WireGuard under the hood, ~5-20ms between European datacenters, negligible overhead for API calls
- **No firewall changes needed** — `trustedInterfaces = ["tailscale0"]` already allows all tailnet traffic on all `internalOnlyPorts`. OVH agents can already reach Contabo services (Prometheus at `http://neurosys:9090`, HA at `http://neurosys:8123`, etc.)
- OVH agents reach Contabo services via `http://neurosys:<port>` (Tailscale MagicDNS hostname)

### Claude's Discretion

- Exact import list audit — Claude reviews current `hosts/*/default.nix` imports and identifies any additional misplaced services not discussed
- Whether restic.nix needs any OVH-specific config (SSH host key, etc.) even if Contabo handles data backups
- Exact sequence of deploy commands (deploy Contabo first or OVH first, or simultaneous)

</decisions>

<specifics>
## Specific Ideas

- Agent execution model: agents always have full tooling on both hosts, but OVH is primary (repos/symlinks there). Agents on OVH SSH to Contabo for deploy operations — same as local-machine workflow, not a regression.
- Conway Automaton is categorized as a "persistent service" not an "agent" for placement purposes — goes on Contabo with Parts.
- No new firewall rules needed — the existing `trustedInterfaces` pattern covers all cross-host access.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 38-dual-host-role-separation-contabo-as-services-host-ovh-as-dev-agent-host*
*Context gathered: 2026-02-27*
