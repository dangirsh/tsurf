# Phase 24: Server Hardening + DX - Context

**Gathered:** 2026-02-23
**Status:** Ready for planning

<domain>
## Phase Boundary

Adopt battle-tested server hardening defaults (srvos), tighten agent sandbox isolation (PID + cgroup), and improve developer experience (devShell, formatting). gVisor and flake check toplevel are explicitly out of scope.

</domain>

<decisions>
## Implementation Decisions

### srvos adoption
- Import `srvos.nixosModules.server` as flake input — get ~48 hardening defaults in one line
- Override `networking.useNetworkd = false` (Contabo static IP uses scripted networking)
- Override `documentation.enable = true` and `documentation.man.enable = true` (dev server, agents and humans need man pages)
- Override `programs.command-not-found.enable = true` (helpful for interactive sessions)
- Override `boot.initrd.systemd.enable = false` (defer to Phase 21 impermanence — don't change initrd independently)
- Accept everything else: emergency mode off, watchdog timers, sleep disabled, OOM priority, LLMNR off, nix daemon scheduling, disk space guards, serial console, known hosts, sudo lecture off, update-diff, hostname change detection

### gVisor
- **Skip entirely.** Low value for single-operator server behind Tailscale. Kernel hardening + nftables + fail2ban is sufficient. Not worth the complexity or potential syscall compatibility issues.

### Sandbox PID + cgroup isolation
- Add `--unshare-pid` to agent-spawn bwrap flags — agents cannot see host processes, cannot kill other agents or system services
- Add `--unshare-cgroup` to agent-spawn bwrap flags — agents cannot see host cgroup hierarchy
- Docker commands still work through the socket (PID namespace doesn't affect Unix socket communication)
- Some agents need Docker access — socket bind-mount stays (SEC6 accepted risk unchanged)

### DevShell
- Add `devShell` to flake.nix for agents working on the repo
- Primary users: agents (not human operator)
- Contents: sops, age, deploy-rs CLI, nixfmt, shellcheck (minimum useful set for secrets editing, deploying, and formatting)

### Formatting
- Add treefmt-nix with nixfmt + shellcheck
- `nix fmt` formats all Nix files and lints shell scripts
- No pre-commit hook enforcement (agents run it manually)

### Flake check toplevel
- **Skip.** Keep `nix flake check` as eval-only (fast). Build errors caught at deploy time. Adding toplevel build to check makes it too slow for agent pre-commit validation.

### Claude's Discretion
- Exact devShell package list (sops + age + deploy-rs + nixfmt + shellcheck as baseline, add more if useful)
- treefmt-nix configuration details
- Which srvos overrides need `mkForce` vs `mkDefault` vs direct set
- Order of srvos import vs existing module imports (to get priority right)
- Any additional srvos defaults that need overriding if they conflict with existing config

</decisions>

<specifics>
## Specific Ideas

- User's philosophy: "each new addition should earn its complexity cost — I default to YAGNI"
- Every addition must have clear security, QoL, or use-case justification
- srvos was approved specifically because ~48 defaults in one import line is less complexity than cherry-picking them manually
- gVisor was explicitly rejected after evaluating threat model (single-operator, Tailscale-isolated, claw-swap is only internet-facing container)

</specifics>

<deferred>
## Deferred Ideas

- **gVisor Docker runtime** — Rejected for now. Reconsider if multi-tenant or more internet-facing services are added.
- **Flake check toplevel build** — Skipped for speed. Reconsider if eval-only check misses real build failures in practice.
- **systemd initrd** — Defer to Phase 21 (impermanence). The two changes should land together, not independently.

</deferred>

---

*Phase: 24-server-hardening-and-dx*
*Context gathered: 2026-02-23*
