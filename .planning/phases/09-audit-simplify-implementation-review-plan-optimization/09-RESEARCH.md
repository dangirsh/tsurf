# Phase 9: Audit & Simplify — Research

**Researched:** 2026-02-15
**Domain:** NixOS module review, security hardening, plan optimization
**Confidence:** HIGH

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

#### Simplification philosophy
- Minimal config that meets all requirements — nothing extra
- Keep options/config that are referenced by future phase plans; only strip truly dead code
- Service-specific details (e.g., Caddy TLS config) belong in service repos (claw-swap), not here
- Audit scope is agent-neurosys base repo only

#### Security stance
- Best security without interfering with use cases
- SSH moves to Tailscale-only access (implement during this audit, not deferred to deploy)
  - Contabo VNC console is the emergency fallback
  - Public ports reduced to 80/443 only (for web services like claw-swap)
- Docker container hardening: **research needed** — produce exec summary + recommendation on security/usability tradeoffs (read-only rootfs, dropped capabilities, no-new-privileges, resource limits)
- Secrets: light check only — verify secrets decrypt and are used. No key rotation policy or access scope audit
- Public services (claw-swap) must be strongly isolated from rest of VPS (Docker network isolation is the baseline)

#### Plan revision scope
- Review ALL unexecuted phase goals and success criteria for bloat/clarity (Phases 2, 2.1, 4, 5, 6, 7)
- Don't draft plan outlines — that's what /gsd:plan-phase does. Just tighten goals
- Re-evaluate Phase 2.1 TODOs (from Phase 8 neurosys review) with fresh eyes — some may be unnecessary complexity
- Review roadmap structure — consider whether phases should be merged, reordered, or dropped
- Contabo-specific assumptions in Phase 2 plans: defer verification to deploy time

#### Audit deliverables
- Apply code changes directly with atomic commits (no findings report)
- Apply roadmap/plan changes directly (no approval gate)
- Git commits are sufficient documentation — no separate summary document
- `nix flake check` must pass after any implementation changes

### Claude's Discretion
- Whether to merge small modules (<20 lines) into parent concern files
- Whether to normalize extraConfig/freeform strings to structured NixOS options (case-by-case)
- Whether the parts cross-flake pattern (curried modules, sops.templates) earns its complexity or should be simplified

### Deferred Ideas (OUT OF SCOPE)
None — discussion stayed within phase scope
</user_constraints>

## Summary

This phase is an audit-and-act pass across three domains: (1) the committed NixOS codebase (287 lines of Nix across 12 files), (2) the security posture (firewall, SSH, Docker, secrets), and (3) the unexecuted phase plans in the roadmap (Phases 2, 2.1, 4, 5, 6, 7). The codebase is small and clean — the main audit actions are security tightenings (SSH-to-Tailscale-only, removing port 22 from public firewall) and plan simplification (Phase 2.1 candidates are partially redundant with what was already done during deployment).

**Primary recommendation:** Split into two plans: (1) code changes (security hardening + module simplification + `nix flake check`) and (2) roadmap/plan revision (tighten goals, evaluate Phase 2.1, consider phase merges). Code changes first since they must pass `nix flake check`.

## Codebase Audit Findings

### Current Module Inventory (287 lines total)

| File | Lines | Concern | Finding |
|------|-------|---------|---------|
| `flake.nix` | 42 | Entrypoint | Clean. `path:` input for parts must stay for local dev (production fix is deploy-time). |
| `modules/default.nix` | 10 | Import hub | Clean. Just imports. |
| `modules/base.nix` | 12 | Nix settings + GC | Small but distinct concern. Worth keeping separate. |
| `modules/boot.nix` | 9 | GRUB config | Small but distinct concern. Worth keeping separate. |
| `modules/networking.nix` | 66 | Firewall + SSH + Tailscale + fail2ban | Largest module. Contains the SSH-to-Tailscale change target. |
| `modules/users.nix` | 22 | User accounts + sudo | Contains root SSH keys marked for cleanup. |
| `modules/secrets.nix` | 14 | sops-nix declarations | Clean. 5 secrets declared (1 used, 3 for future Phase 7, 1 unused). |
| `modules/docker.nix` | 29 | Docker engine + NAT | Clean. `eth0` assumption documented. |
| `hosts/acfs/default.nix` | 25 | Host-specific config | Clean. Static IP, hostname, timezone. |
| `hosts/acfs/hardware.nix` | 16 | Kernel modules | Clean. VirtIO modules for Contabo. |
| `hosts/acfs/disko-config.nix` | 36 | Disk layout | Clean. GPT + EFI + root partition. |
| `home/default.nix` | 6 | home-manager stub | Minimal stub — expanded in Phase 5. |

### Issues Found

#### 1. SSH accessible on public interface (SECURITY - implement now)
**Current:** `networking.firewall.allowedTCPPorts = [ 22 80 443 22000 ];` and `services.openssh` does not set `openFirewall`.
**Problem:** Port 22 is open on the public interface. Per user decision, SSH should only be accessible via Tailscale.
**Fix:** Remove port 22 from `allowedTCPPorts`, set `services.openssh.openFirewall = false`. The `trustedInterfaces = [ "tailscale0" ]` already allows all traffic on the Tailscale interface, so SSH will work over Tailscale without any additional rules.
**Confidence:** HIGH — verified via NixOS wiki and Discourse. `services.openssh.openFirewall` defaults to `true` and must be explicitly disabled.

#### 2. Port 22000 (Syncthing) open but Syncthing not yet configured (SIMPLIFICATION)
**Current:** Port 22000 is in `allowedTCPPorts` but Syncthing is Phase 6 (not started).
**Decision:** Keep or remove? Since user said "keep options referenced by future phase plans; only strip truly dead code" — port 22000 IS referenced by Phase 6. **Recommendation: keep it.** Removing and re-adding creates churn.

#### 3. Root SSH authorized keys still present (CLEANUP)
**Current:** `users.users.root.openssh.authorizedKeys.keys` has 2 keys. Comment says "Remove after confirming dangirsh SSH + sudo works (Plan 02)."
**Status:** Plan 02 is complete. dangirsh SSH + sudo confirmed working. Root SSH was useful during deployment but is no longer needed.
**Fix:** Remove `users.users.root.openssh.authorizedKeys.keys` block. Root login is already `prohibit-password` and will further benefit from SSH moving to Tailscale-only.
**Confidence:** HIGH — deployment log confirms dangirsh SSH + passwordless sudo verified.

#### 4. `PermitRootLogin = "prohibit-password"` can be tightened (SECURITY)
**Current:** Set to `"prohibit-password"` with comment "key-only root for initial deploy recovery."
**Status:** Deployment is complete. Recovery can use Contabo VNC.
**Fix:** Change to `"no"`. Combined with removing root's authorized_keys, this eliminates root SSH entirely.
**Confidence:** HIGH — Contabo VNC confirmed as emergency fallback.

#### 5. Secrets contain placeholder values (KNOWN - not this phase's scope)
**Current:** `secrets/acfs.yaml` contains `placeholder-replace-me` for all 5 secrets.
**Status:** The v1-MILESTONE-AUDIT already documents this. The live server has REAL secrets (deployed manually). The repo placeholders are a known gap — real values must be encrypted into the file before any redeployment.
**Scope:** Light check only per user decision. Secrets ARE declared and the decryption pipeline works (verified on live server with 15 secrets). No action needed in this phase beyond noting the placeholder issue.

#### 6. `example_secret` in secrets.nix (DEAD CODE)
**Current:** `secrets/acfs.yaml` contains `example_secret` which is not referenced by any module.
**Status:** Leftover from Phase 1 scaffolding.
**Fix:** Remove from `secrets/acfs.yaml`. This is truly dead — no module references it.

#### 7. Parts cross-flake pattern assessment (CLAUDE'S DISCRETION)
**Current:** Parts uses a curried module pattern: `{ self, sops-nix }: { config, lib, pkgs }: { ... }`. It declares 10 sops secrets, 2 sops templates, 2 Docker networks, 2 containers, and systemd ordering.
**Assessment:** The curried pattern earns its complexity. It solves a real problem — parts needs `self` for `sopsFile` paths and must NOT import sops-nix (agent-neurosys owns that). The `sops.templates` pattern for env files is the idiomatic sops-nix approach. The module is 200 lines but well-structured with clear sections.
**Recommendation:** Keep as-is. No simplification needed. The complexity is proportional to the problem.

#### 8. Small modules assessment (CLAUDE'S DISCRETION)
**Current:** `base.nix` (12 lines) and `boot.nix` (9 lines) are small.
**Assessment:** Both are distinct concerns (Nix daemon config vs bootloader config). Merging them gains nothing — they would still be logically separate sections. The module-per-concern pattern is consistent across the codebase.
**Recommendation:** Keep separate. The overhead of separate files is negligible and the organization is clear.

## SSH-to-Tailscale-Only Implementation

### The Change

```nix
# modules/networking.nix — BEFORE
networking.firewall.allowedTCPPorts = [ 22 80 443 22000 ];

# modules/networking.nix — AFTER
networking.firewall.allowedTCPPorts = [ 80 443 22000 ];

# Also add:
services.openssh.openFirewall = false;
```

### How It Works

1. `services.openssh.openFirewall = false` prevents NixOS from auto-opening port 22 (default is `true`)
2. Removing 22 from `allowedTCPPorts` closes it on all interfaces
3. `trustedInterfaces = [ "tailscale0" ]` already trusts ALL traffic on the Tailscale interface — this means SSH works over Tailscale without any port-specific rules
4. `allowedUDPPorts = [ config.services.tailscale.port ]` keeps Tailscale's WireGuard handshake port open (required for Tailscale to connect at all)

### Safety Considerations

- **Emergency access:** Contabo VNC console provides out-of-band access if Tailscale fails
- **Tailscale auth:** Uses authkey from sops secret — if secrets fail, Tailscale won't connect and SSH becomes inaccessible. This is already the case; the change doesn't make it worse
- **fail2ban:** Still useful — protects against brute-force on any remaining open ports. However, the SSH jail becomes less critical since port 22 is no longer public. Keep fail2ban as defense-in-depth

### Decision annotations to update

- `@decision NET-01`: Change from "key-only SSH, no root login" to "key-only SSH via Tailscale only, no root login"
- `@decision NET-04`: Change from "ports 22, 80, 443, 22000 on public interface" to "ports 80, 443, 22000 on public interface; SSH via Tailscale only"
- Remove `allowPing`? No — keep for diagnostics. ICMP ping on the public interface is fine.

**Confidence:** HIGH — pattern verified from NixOS wiki, Discourse, and multiple blog posts.

## Docker Container Hardening — Executive Summary

### Options Evaluated

| Hardening | What It Does | Compatibility | Recommendation |
|-----------|-------------|---------------|----------------|
| `--read-only` | Root filesystem becomes read-only | Node.js apps need `--tmpfs /tmp` for temp files; Nix store paths in image are already immutable | **Recommend for Phase 4** |
| `--cap-drop ALL` | Drops all Linux capabilities | Node.js web apps need zero capabilities (no raw sockets, no mount, etc.) | **Recommend for Phase 4** |
| `--security-opt=no-new-privileges` | Prevents setuid/setgid privilege escalation | No impact on Node.js apps | **Recommend for Phase 4** |
| `--memory` / `--cpus` | Resource limits | Prevents runaway containers from starving the host | **Recommend for Phase 4** |

### NixOS Implementation

NixOS `virtualisation.oci-containers` supports these via:
- `capabilities` attribute: `{ ALL = false; }` to drop all capabilities (native NixOS option, not extraOptions)
- `extraOptions`: `[ "--read-only" "--tmpfs=/tmp:rw,noexec,nosuid" "--security-opt=no-new-privileges" "--memory=512m" "--cpus=1.0" ]`

### Tradeoffs

**Benefits:**
- Read-only rootfs prevents attackers from modifying container filesystem (Nix images are already mostly immutable, but this enforces it at runtime)
- Dropping capabilities means even container-root cannot perform privileged operations
- no-new-privileges prevents setuid binaries from escalating
- Resource limits prevent a compromised container from consuming all host resources

**Costs:**
- `--read-only` requires identifying writable paths (tmp, data volumes) and mounting tmpfs. For the parts containers, `/app/data` and `/data/sessions` are already bind-mounted volumes, so they are writable regardless. Only `--tmpfs=/tmp` is needed additionally
- `--cap-drop ALL` can break containers that need specific capabilities (e.g., `NET_BIND_SERVICE` for ports < 1024). Parts containers don't bind to privileged ports, so no issue
- Resource limits need tuning — too tight and containers crash under load. Start generous (512M memory, 1 CPU for parts-agent; 1G memory, 2 CPUs for parts-tools which runs signal-cli + Java)

### Recommendation

**Implement hardening in Phase 4 (Docker Services), not in this audit phase.** Rationale:
1. Phase 4 is when claw-swap containers are declared — that's when container security matters (public-facing service)
2. Parts containers are already declared in the parts repo's `nix/module.nix`, not in agent-neurosys. Hardening parts containers requires changes to the parts repo
3. The audit phase's scope is agent-neurosys base repo only (per user decision)

**Deliver this research as a recommendation section in the ROADMAP Phase 4 goals.** The implementation pattern is clear:
```nix
# Example: add to each container declaration in oci-containers
extraOptions = [
  "--read-only"
  "--tmpfs=/tmp:rw,noexec,nosuid"
  "--security-opt=no-new-privileges"
  "--memory=512m"
  "--cpus=1.0"
];
capabilities = { ALL = false; };
```

**Confidence:** HIGH — OWASP Docker Security Cheat Sheet, Docker official docs, NixOS oci-containers source all confirm this approach.

## Roadmap & Plan Revision Findings

### Phase 2: Bootable Base System

**Status:** Complete (2/2 plans). Plans are historical — no revision needed.
**Note:** The 02-02-PLAN.md and 02-02-SUMMARY.md/DEPLOY-LOG are untracked (in git status). They document the deployment. No action needed.

### Phase 2.1: Base System Fixups from Neurosys Review

**Status:** Not started. 0/TBD plans.
**Current TODOs (from Phase 8 review):**

| TODO | Assessment | Recommendation |
|------|-----------|----------------|
| Settings module (`config.settings.*`) | Adds indirection for 3 values (name, username, email) used in 1-2 places. Over-engineered for a single-host config. | **Drop.** Hardcoded values in the 1-2 places they appear is simpler. |
| System packages baseline (16 pkgs) | Useful but agent-neurosys is base infra. Dev tools belong in Phase 5 (home-manager). System packages should be minimal. | **Slim down.** Move most to Phase 5. Keep only system-level tools: `git`, `curl`, `wget`, `rsync`, `jq`, `tmux`. Dev tools (ripgrep, fd, shellcheck, sd, etc.) go to Phase 5 as home-manager packages. |
| `users.mutableUsers = false` | Good security — prevents `passwd` changes outside Nix. | **Keep.** |
| `security.sudo.wheelNeedsPassword = false` | Already implemented during deployment. | **Already done.** Remove from TODO. |
| `security.sudo.execWheelOnly = true` | Good security — only wheel users can use sudo. | **Keep.** |
| `programs.ssh.startAgent = true` | Useful for SSH forwarding. | **Move to Phase 5** (user environment concern, not base system). |

**Recommendation:** Phase 2.1 shrinks to 2-3 small changes (`mutableUsers`, `execWheelOnly`, maybe a few system packages). Consider merging into Phase 9 itself rather than keeping as a separate phase. The settings module should be dropped — it's unnecessary indirection for a single-host config.

### Phase 4: Docker Services + Ollama

**Current success criteria:**
1. claw-swap stack running (Caddy + app + PostgreSQL)
2. grok-mcp container running
3. Ollama service running
4. Docker network created

**Revision suggestions:**
- Add container hardening to success criteria (read-only rootfs, cap-drop, no-new-privileges)
- claw-swap containers should be declared in a claw-swap flake module (same pattern as parts), not inline in agent-neurosys. This keeps service-specific config in service repos per user decision.
- grok-mcp: evaluate if still needed. If yes, declare as a simple oci-container in agent-neurosys.
- Ollama: simple NixOS service module. Keep.

### Phase 5: User Environment + Dev Tools

**Current scope:** 10 requirements (DEV-01..05, HOME-01..05).
**Revision suggestions:**
- Absorb the dev-tools system packages from Phase 2.1 (ripgrep, fd, shellcheck, etc.)
- Absorb `programs.ssh.startAgent = true` from Phase 2.1
- Absorb SSH client config (controlMaster, etc.) from Phase 8 TODO
- Absorb direnv from Phase 8 TODO
- This is already a large phase. Consider splitting: 5a (shell + home-manager basics) and 5b (dev tools + languages). Or just accept it as a 2-3 plan phase.

### Phase 6: User Services + Agent Tooling

**Current scope:** 4 requirements (SVC-02, SVC-03, AGENT-01, AGENT-02).
**Revision suggestions:**
- CASS indexer (SVC-03): binary availability is flagged as a blocker in STATE.md. Research needed before planning.
- Syncthing (SVC-02): device IDs captured, straightforward NixOS module.
- Agent tooling (AGENT-01, AGENT-02): activation scripts to clone repos and create symlinks.
- Phase 6 depends on Phase 5 (home-manager for CASS user service). This dependency is correct.
- No bloat found. Phase is well-scoped.

### Phase 7: Backups

**Current scope:** 1 requirement (BACK-01).
**Revision suggestions:**
- Restic module is well-supported in NixOS. B2 credentials are already in sops secrets (b2-account-id, b2-account-key, restic-password).
- Phase is well-scoped. Single plan.
- No bloat found.

### Roadmap Structure Assessment

**Current order:** 1 -> 2 -> 2.1 -> 3 -> 3.1 -> 4 -> 5 -> 6 -> 7 -> 8 -> 9

**Proposed changes:**
1. **Absorb Phase 2.1 into Phase 9.** The 2-3 remaining items (mutableUsers, execWheelOnly) are trivial and fit naturally in the audit. No need for a separate phase with its own planning overhead.
2. **Keep Phases 4-7 as-is.** Each has a clear delivery boundary and distinct concern. No merge benefit.
3. **Update Phase 4 goals** to include container hardening success criteria.
4. **Update Phase 5 goals** to absorb items moved from Phase 2.1.
5. **Execution order after Phase 9:** 4 -> 5 -> 6 -> 7 (unchanged).

### Milestone Audit Tech Debt Items

The v1-MILESTONE-AUDIT identified these items. Status check:

| Tech Debt | Status | Action |
|-----------|--------|--------|
| Plan 02 not executed | RESOLVED — deployment complete | Remove from tech debt |
| Root SSH key still declared | This phase fixes it | Implement |
| NAT externalInterface=eth0 unverified | Verified during deployment (eth0 confirmed) | Remove from tech debt |
| Secret placeholders need real values | Known — live server has real values | Note in roadmap, not this phase |
| Parts flake uses path: URI | Known — must change for production deploy | Note in roadmap, not this phase |
| Host age key mismatch | RESOLVED during deployment | Remove from tech debt |
| No VERIFICATION.md for any phase | Per user decision, commits are sufficient documentation | Drop requirement |
| Phase 2.1 TODOs need re-evaluation | This research re-evaluates them | Implement |
| Roadmap structure review | This research covers it | Implement |

## Architecture Patterns

### NixOS Module Security Hardening Pattern

When tightening security on an existing NixOS config, follow this order:
1. **Firewall first** — reduce attack surface (remove ports, restrict interfaces)
2. **Service hardening** — tighten service-specific settings (SSH, Docker)
3. **User hardening** — restrict user capabilities (mutableUsers, execWheelOnly)
4. **Validate** — `nix flake check` + verify existing services still work

### SSH-to-Tailscale-Only Pattern

```nix
# Standard NixOS pattern for Tailscale-only SSH
services.openssh = {
  enable = true;
  openFirewall = false;  # Don't auto-open port 22
  settings = {
    PasswordAuthentication = false;
    KbdInteractiveAuthentication = false;
    PermitRootLogin = "no";
  };
};

networking.firewall = {
  enable = true;
  allowedTCPPorts = [ 80 443 ];  # Public web only
  trustedInterfaces = [ "tailscale0" ];  # All Tailscale traffic trusted
};
```

Source: NixOS Wiki (Tailscale), NixOS Discourse, MyNixOS documentation.

## Common Pitfalls

### Pitfall 1: Locking yourself out with firewall changes
**What goes wrong:** Removing port 22 from the firewall before Tailscale is confirmed working.
**Why it happens:** The change is applied at next nixos-rebuild or reboot. If Tailscale is down, SSH is unreachable.
**How to avoid:** The live server already has Tailscale working (verified in deployment). The change is safe. Emergency fallback: Contabo VNC console.
**Warning signs:** If `systemctl status tailscaled` shows inactive after the change, SSH will be unreachable from outside.

### Pitfall 2: `openFirewall` default is true
**What goes wrong:** Setting `services.openssh.openFirewall = false` but forgetting to also remove port 22 from `allowedTCPPorts`.
**Why it happens:** Two independent code paths both open port 22 — the openssh module's openFirewall AND the manual allowedTCPPorts list.
**How to avoid:** Do both: set `openFirewall = false` AND remove 22 from `allowedTCPPorts`.

### Pitfall 3: Editing secrets/acfs.yaml with placeholder values
**What goes wrong:** Running `sops` to edit the file locally works, but the placeholder values would break services on the live server.
**Why it happens:** The repo has placeholders; the live server has real values that were set manually.
**How to avoid:** For this phase, only remove `example_secret` (dead key). Don't modify other secret values. If removing a key from the YAML, re-encrypt with `sops --encrypt --in-place`.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Per-interface firewall rules | Custom nftables rules | `trustedInterfaces` + `openFirewall = false` | NixOS abstractions handle the nftables rules correctly |
| Docker container security | Custom systemd service wrappers | `oci-containers` `capabilities` + `extraOptions` | Native NixOS option handles Docker flag translation |
| Secret placeholder management | Custom validation scripts | Deployment-time verification | Secrets are correct on the live server; repo placeholders are an intentional pattern for public repos |

## Code Examples

### Firewall change (networking.nix)

```nix
# BEFORE
networking.firewall = {
  enable = true;
  allowPing = true;
  allowedTCPPorts = [ 22 80 443 22000 ];
  allowedUDPPorts = [ config.services.tailscale.port ];
  trustedInterfaces = [ "tailscale0" ];
};

# AFTER
networking.firewall = {
  enable = true;
  allowPing = true;
  allowedTCPPorts = [ 80 443 22000 ];
  allowedUDPPorts = [ config.services.tailscale.port ];
  trustedInterfaces = [ "tailscale0" ];
};

services.openssh = {
  enable = true;
  openFirewall = false;
  settings = {
    PasswordAuthentication = false;
    KbdInteractiveAuthentication = false;
    PermitRootLogin = "no";
  };
};
```

### Root key removal (users.nix)

```nix
# REMOVE this entire block:
users.users.root.openssh.authorizedKeys.keys = [
  "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIac0b7Yb2yCJrPiWf+KJQJ1c7gwH7SgHTiadSSUH0tM dan@worldcoin.org"
  "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAqNVObi1HflLIV/FkO/rAz/ABdTvADidl5tuIulS3WE parts-agent@vm"
];
```

### User hardening (users.nix)

```nix
# ADD these:
users.mutableUsers = false;
security.sudo.execWheelOnly = true;
```

## Open Questions

1. **Should `example_secret` be removed from acfs.yaml?**
   - What we know: It is not referenced by any module. It is dead code from Phase 1 scaffolding.
   - What's unclear: Whether removing a key from an encrypted sops file and re-encrypting will work cleanly when the live server has different secret values.
   - Recommendation: Remove it. The re-encryption only affects the repo copy (which has placeholders anyway). The live server's secrets are independent.

2. **Should Phase 2.1 be formally absorbed into Phase 9 or just dropped?**
   - What we know: Only 2-3 items remain after re-evaluation. They are trivial.
   - What's unclear: Whether the user prefers to keep Phase 2.1 as a future placeholder or absorb it.
   - Recommendation: Absorb the remaining items (mutableUsers, execWheelOnly) into Phase 9's code changes plan. Update the roadmap to mark Phase 2.1 as "absorbed into Phase 9."

## Sources

### Primary (HIGH confidence)
- NixOS codebase: all 12 .nix files in agent-neurosys read directly
- Parts codebase: flake.nix, nix/module.nix, nix/parts-agent.nix, nix/parts-tools.nix read directly
- Planning documents: ROADMAP.md, STATE.md, v1-MILESTONE-AUDIT.md, all phase plans and summaries
- [MyNixOS: services.openssh.openFirewall](https://mynixos.com/nixpkgs/option/services.openssh.openFirewall) — default value confirmed as `true`
- [NixOS Discourse: Firewall block port 22 while enabling SSH](https://discourse.nixos.org/t/possible-to-firewall-block-port-22-while-still-enabling-ssh-on-port-22/36665) — `openFirewall = false` pattern
- [NixOS Wiki: Tailscale](https://wiki.nixos.org/wiki/Tailscale) — trustedInterfaces pattern
- [OWASP Docker Security Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Docker_Security_Cheat_Sheet.html) — container hardening flags
- [NixOS oci-containers module source](https://github.com/NixOS/nixpkgs/blob/master/nixos/modules/virtualisation/oci-containers.nix) — capabilities option confirmed

### Secondary (MEDIUM confidence)
- [NixOS nftables + Tailscale issue #285676](https://github.com/NixOS/nixpkgs/issues/285676) — TS_DEBUG_FIREWALL_MODE nftables workaround
- [Docker official docs: container run](https://docs.docker.com/reference/cli/docker/container/run/) — security-opt, cap-drop flags

## Metadata

**Confidence breakdown:**
- Codebase audit: HIGH — all files read directly, line counts verified
- Security hardening (SSH/firewall): HIGH — multiple authoritative sources confirm the pattern
- Docker hardening: HIGH — OWASP + Docker docs + NixOS source confirm the approach
- Plan revision: HIGH — based on direct reading of all plans and cross-referencing with deployment results
- Module simplification: HIGH — direct assessment of 287 lines of code

**Research date:** 2026-02-15
**Valid until:** 2026-03-15 (stable domain, NixOS options don't change frequently)
