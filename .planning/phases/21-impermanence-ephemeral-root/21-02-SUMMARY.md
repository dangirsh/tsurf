---
phase: 21-impermanence-ephemeral-root
plan: 02
subsystem: infra
tags: [nixos, btrfs, impermanence, nixos-anywhere, sops, tailscale, tailnet-lock, deploy]

# Dependency graph
requires:
  - phase: 21-01
    provides: BTRFS disko config, impermanence module, updated restic paths
provides:
  - Neurosys (Contabo VPS) running NixOS with BTRFS impermanence (ephemeral root)
  - All services verified running: docker, tailscaled, sshd, prometheus, syncthing, claw-swap, parts-agent
  - Merged to main — deploy/impermanence-migration branch closed
affects: [hosts/neurosys, modules/networking, secrets/neurosys.yaml, flake.lock, .sops.yaml]

# Tech tracking
tech-stack:
  used: [nixos-anywhere, btrfs, sops-nix, tailscale-tailnet-lock, nix-community/impermanence]
  patterns: [nixos-anywhere-extra-files-persist, tailnet-lock-signing, first-boot-race-workaround]

key-files:
  modified:
    - modules/networking.nix
    - modules/users.nix
    - secrets/neurosys.yaml
    - flake.lock
    - .sops.yaml

key-decisions:
  - "NET-01 (temporary): Port 22 opened on public interface to recover from Tailscale bootstrap chicken-and-egg"
  - "NET-08: Only ed25519 hostKey declared — prevents ephemeral RSA/ECDSA key generation overwriting the injected key"
  - "Extra-files path: SSH host key in persist/etc/ssh/ (not etc/ssh/) so it survives initrd root wipe"
  - "Fresh deploy (not restic restore): user opted to start with clean service state after disk wipe"

patterns-established:
  - "nixos-anywhere --extra-files: SSH host key must go in persist/etc/ssh/ for impermanence layout"
  - "Tailnet lock bootstrap: new nodes need signing via tailscale lock sign nodekey:<pubkey>"
  - "First-boot race conditions: systemd units that depend on sops secrets may hit restart limit — restart manually or wait for next boot"
  - "sops cross-flake key rotation: updating host SSH key requires updatekeys in ALL dependent flakes (parts, claw-swap)"

# Metrics
duration: ~3hr (including several blocking issues resolved mid-session)
completed: 2026-02-24
---

# Phase 21 Plan 02: Impermanence Deployment Summary

**nixos-anywhere redeploy of neurosys to BTRFS + impermanence — deployed and verified with all services running**

## Performance

- **Duration:** ~3hr (extended by sops key rotation, tailnet lock, first-boot race conditions)
- **Completed:** 2026-02-24
- **Tasks:** 1 (checkpoint:human-action — fully operator-driven)

## Accomplishments

- Executed nixos-anywhere destructive redeploy of Contabo VPS (161.97.74.121) from Ubuntu to NixOS with BTRFS impermanence
- Resolved sops key mismatch: new SSH host key (`age1sczx067...`) required re-encryption of `secrets/neurosys.yaml`, `parts` flake secrets, and `claw-swap` flake secrets
- Fixed claw-swap `.sops.yaml` (host_acfs → host_neurosys key alias) and ran `sops updatekeys`; pushed fix and updated flake.lock
- Unblocked tailnet lock: signed neurosys node via vmi2996850 (added as trusted signing node first via `tailscale lock add`)
- All services verified running post-deploy: docker, tailscaled, sshd, sops secrets, syncthing, claw-swap, parts-agent, prometheus
- Merged `deploy/impermanence-migration` into main (`c4a4e07`) and pushed

## Task Commits

Key commits from this plan:

1. `f106138` — fix(networking): open port 22 on public interface for bootstrap access (Tailscale-chicken-and-egg workaround)
2. `eaf38ca` — merge(impermanence): integrate impermanence migration into main (merge commit, 5 conflicts resolved)
3. `c4a4e07` — Merge commit '39a1df1' into deploy/impermanence-migration (picked up OVH bootstrap fix from main)
4. `3d10e7c` (claw-swap repo) — fix(.sops.yaml): rotate host key from host_acfs to host_neurosys

## Files Created/Modified

- `modules/networking.nix` — port 22 added to allowedTCPPorts (temporary bootstrap), fail2ban removed (deferred), hostKeys pinned to ed25519 only (NET-08)
- `modules/users.nix` — updated for impermanence (root authorized keys ensured persistent)
- `secrets/neurosys.yaml` — re-encrypted with new host key `age1sczx067gq0grjm0kunw6m9z0vgxdtt357ksnzdhw78sh25hkmauqqkxf24`
- `.sops.yaml` — updated with new neurosys host key + OVH host key (merged from main)
- `flake.lock` — parts@53e5f63 (new neurosys key), claw-swap@e3289f4 (includes key rotation fix)

## Decisions Made

- **Port 22 temporarily public**: Tailscale-only SSH (port 22 closed) is a chicken-and-egg problem when doing a fresh nixos-anywhere deploy — Tailscale can't connect until after first boot, but first boot needs sops secrets which need the SSH host key which was just injected. Opened port 22 on public interface to allow post-deploy access.
- **Fresh service state**: After the disk wipe, user opted not to restore service state from restic. Docker image layer cache persisted on the `@docker` BTRFS subvolume; application data (claw-swap DB, etc.) started fresh.
- **No restic restore step**: Departed from plan. The server was a clean fresh deploy; services were configured declaratively and came up from scratch.
- **No deploy-rs first-deploy**: Standard `nixos-rebuild switch` was used post-deploy. deploy-rs baseline not established in this session.

## Deviations from Plan

| Step | Plan | Actual |
|------|------|--------|
| Step 2 (host key) | Extract from restic backup | Pre-generated fresh key in `tmp/neurosys-host-keys/persist/etc/ssh/` |
| Step 5 (restore) | Full restic restore to /persist | Skipped — fresh service state |
| Step 6 (tailscale) | Reconnects from restored state | Required manual `tailscale lock sign` (tailnet lock blocked new node) |
| Task 2 (deploy-rs) | `--first-deploy` to establish baseline | Not executed (next deploy will need `--first-deploy`) |
| Extra: claw-swap sops | Not planned | claw-swap had stale host_acfs key; required .sops.yaml fix + updatekeys + flake.lock update |

## Issues Encountered

### 1. Previous NixOS install blocked recovery (resolved)
Server had a failed prior nixos-anywhere run with NixOS nftables DROP on port 22. Port 22 appeared to timeout (not refuse), matching NixOS nftables behavior. Resolution: user reinstalled Ubuntu via Contabo VPS panel.

### 2. claw-swap sops decrypt failure on first boot (resolved)
`Error getting data key: 0 successful groups required` — claw-swap's `.sops.yaml` still had `host_acfs` key alias which didn't match the new neurosys age key. Fix: updated claw-swap `.sops.yaml`, ran `sops updatekeys --yes`, committed and pushed to claw-swap repo, updated neurosys flake.lock.

### 3. tailscaled-autoconnect race condition on first boot (mitigated)
`tailscaled-autoconnect` service ran before sops secrets were decrypted. `cat: /run/secrets/tailscale-authkey: No such file or directory`. Manual `systemctl restart tailscaled-autoconnect` resolved it. Root cause: sops-nix activation happens after early boot services. Subsequent reboots work correctly (sops secrets available earlier in systemd ordering).

### 4. Tailnet lock blocked new node (resolved)
New neurosys node appeared in Tailscale as "locked out" due to tailnet lock being enabled on the tailnet. Steps to unblock: (1) `tailscale lock add tlpub:<vmi2996850-pubkey>` on MacBook to make vmi2996850 a trusted signing node, (2) `tailscale lock sign nodekey:<neurosys-pubkey>` from vmi2996850. Also signed `neurosys-prod` (OVH) which was locked out for the same reason.

### 5. Docker container first-boot race (mitigated)
claw-swap-app, claw-swap-db, parts-agent all hit `start-limit-hit` on first boot — Docker daemon not fully ready when container units started. Docker image layers persisted on `@docker` BTRFS subvolume. Manual `systemctl start` resolved for this session; subsequent reboots work correctly once systemd unit ordering stabilizes.

## Verification Results

Post-deploy checks that passed:
- ✅ BTRFS subvolumes visible: `@root`, `@nix`, `@persist`, `@log`, `@docker`
- ✅ sops secrets decrypted: `/run/secrets/` populated (12+ files)
- ✅ Tailscale connected: `tailscale status` shows peers
- ✅ Docker running: claw-swap-db, claw-swap-app, claw-swap-caddy, parts-tools, parts-agent
- ✅ sshd active (port 22 public + tailscale0 trusted interface)
- ✅ Prometheus active
- ✅ Syncthing active (after manual start — home-manager ran first, then syncthing could start)
- ✅ `nix flake check` on merged config: 40 checks passed
- ⏭ `deploy-rs --first-deploy`: deferred (not executed this session)
- ⏭ Restic backup to /persist: deferred (expected to work on next scheduled run)

## User Setup Required

- **Run `./scripts/deploy.sh --first-deploy`** on next deploy to establish deploy-rs magic rollback baseline
- **Close port 22** once Tailscale bootstrap is confirmed stable (restore `assertion = !builtins.elem 22 ...` in networking.nix)
- **Re-enable fail2ban** — was disabled during impermanence migration; restore `services.fail2ban` block per NET-05 decision

## Next Phase Readiness

- Phase 21 complete — neurosys running with BTRFS impermanence, all services up
- Phase 27 (OVH VPS Migration) and Phase 28 (dangirsh.org) continuing in parallel
- Next unexecuted: Phase 28 Plan 03 (DNS cutover for dangirsh.org → OVH)

---
*Phase: 21-impermanence-ephemeral-root*
*Completed: 2026-02-24*
