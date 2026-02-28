# Phase 46: Big Push — Deploy, Integrate, and Test All Recent Work - Context

**Gathered:** 2026-02-28
**Status:** Ready for planning

<domain>
## Phase Boundary

Re-bootstrap Contabo VPS from fresh Ubuntu to NixOS, deploy both hosts (Contabo + OVH) with all accumulated work from Phases 27–44, merge unmerged branches, enable disabled modules (matrix.nix), wire MCP connectivity for Claude Android, set up forward-sync DM bridges on OVH, verify circadian lighting automation, and confirm the already-public repo has no regressions. This phase absorbs and closes Phases 27, 28, 32, 37, 39, and 44.

</domain>

<decisions>
## Implementation Decisions

### Contabo Re-Bootstrap
- **Fresh SSH host key**: Generate a new ssh_host_ed25519_key, derive a new age key, re-encrypt `secrets/neurosys.yaml` with the new recipient. Do NOT attempt to reuse old keys.
- **Clean deploy**: No restic backup restore. All services re-initialize from scratch (HA re-pairs devices, Prometheus starts empty, Docker images re-pull).
- **Same BTRFS impermanence layout**: 5 subvolumes (@root, @persist, @nix, @docker, @home), initrd rollback — same proven pattern from Phase 21.
- **Same IP**: 161.97.74.121 is unchanged after Ubuntu reinstall. No networking config changes needed in `hardware.nix`.
- **nixos-anywhere**: Full NixOS deployment from local machine via `nixos-anywhere --extra-files` with the new SSH host key injected into `/persist/etc/ssh/`.
- **Tailscale re-auth**: New Tailscale auth key needed (generate reusable key from Tailscale admin, add to `secrets/neurosys.yaml`).

### DM Bridge Setup
- **Host**: Bridges run on **OVH** (dev-agent host), not Contabo. Bridges feed AI agents which live on OVH.
- **All three platforms**: Signal + WhatsApp + Telegram. Full bridge setup as designed in Phase 35.
- **Forward-sync only**: No historical message import in this phase. Bridges sync new messages going forward. History import is a deferred task.
- **Module activation**: Un-comment `matrix.nix` import in private-neurosys `flake.nix` (line 84, currently disabled with "pending legacy config migration").
- **Conduit homeserver**: `neurosys.local` server name, RocksDB backend, federation disabled, registration with token.
- **Bridge credentials**: Telegram API ID/hash from sops, WhatsApp pairing via QR (manual step), Signal registration via linked device (manual step).
- **Account linking**: Each bridge requires a one-time manual pairing step on the user's phone/device. Plan for human checkpoints.

### MCP Connectivity
- **Tailscale**: Already installed on Android phone, same tailnet as servers. No setup needed.
- **Auth**: Long-lived HA access token. Generate in HA UI, store in sops as `ha-token`, configure in Claude Android MCP settings.
- **Entity exposure**: Expose ALL HA entities via MCP (lights, sensors, switches, automations). No filtering/limiting.
- **Endpoint**: `https://neurosys.taildb9d4d.ts.net/mcp` via Tailscale Serve HTTPS proxy.
- **Test target**: Any Hue light on the bridge for verification. User will see it respond physically.

### MCP Queryability for DMs
- **Claude's discretion**: Pick the simplest path that makes DMs queryable from Claude Android via MCP. Options include HA Matrix integration (expose rooms as entities) or a dedicated Matrix MCP server. Researcher should investigate both; planner picks the simpler one.

### Deployment Order & Testing
- **Order**: Claude's discretion based on dependency analysis. Likely: merge branches → fix configs → OVH first (already running, quick verify) → Contabo bootstrap → deploy both → test.
- **Verification rigor**: **Full end-to-end**. Not just health checks — must include:
  - Every systemd service active, every Docker container running
  - curl each HTTP endpoint (homepage, HA, Prometheus, claw-swap if on Contabo)
  - MCP endpoint responds to POST with auth token
  - Successfully toggle a Hue light via MCP from Claude Android
  - Query CO2 level via MCP
  - Send a test message through at least one DM bridge
  - Verify circadian automation is active in HA
- **Cachix**: Auth token is available. Re-add to sops during bootstrap. Both hosts should pull from Cachix; Contabo pushes to Cachix after deploy.
- **Open source**: Repo is **already public**. Verify no PII regressions from merged branches, README still accurate, `nix flake check` passes for the public repo.

### Circadian Lighting
- Automation exists in `dangirsh/home-assistant-config` repo (Phase 44 work). After HA re-initializes on Contabo, pull the config repo and reload automations.
- 6-step circadian cycle (6500K noon → 2000K/10% night, 1h after sunset).
- Verify automation entity is `on` in HA and light temperature changes are visible.

### Phase Closure
- Close/cancel these in-progress phases (work absorbed into Phase 46):
  - **Phase 27** (OVH migration) — plans 27-03 through 27-05 absorbed
  - **Phase 28** (dangirsh.org site) — plans 28-03 and 28-04 absorbed
  - **Phase 32** (Conway automaton) — plan 32-02 absorbed
  - **Phase 37** (Open source prep) — work complete, just needs marking
  - **Phase 39** (Conway dashboard) — integration absorbed
  - **Phase 44** (CO2 alert) — task C checkpoint absorbed

### Unmerged Branches to Handle
- `fix/35-reenable-bridges-v2` — latest mautrix bridge fixes (clean, ready to merge)
- `feat/35-matrix-client` — homepage Matrix widget (1 uncommitted change in modules/homepage.nix)
- `ha-oauth-fix` — HA OAuth for MCP access (evaluate if still needed with long-lived token approach)
- `phase-39-02` — Conway dashboard (pushed to remote, not merged)

### Claude's Discretion
- Deployment ordering (which host first, parallel vs sequential)
- DM queryability approach (HA Matrix integration vs dedicated MCP server)
- Branch merge strategy (cherry-pick vs merge vs rebase)
- How to handle `ha-oauth-fix` branch (may be unnecessary given long-lived token decision)
- Worktree cleanup for the 28 stale worktrees

</decisions>

<specifics>
## Specific Ideas

- User wants to use Claude Android voice mode: "turn off the lights", "what's the CO2 level?" — these must work end-to-end
- "Both deployment hosts are up and running (all green)" — not just systemd, but all services functionally verified
- "Compensate by front-loading discussion, spawning lots of planning and implementation agents, meticulously testing each part" — parallelize heavily, test rigorously
- Circadian automation: lights physically follow the sun (color temp changes visible throughout the day)
- This is a consolidation phase — ship everything that's been accumulating, don't add new features

</specifics>

<deferred>
## Deferred Ideas

- **Historical message import** (Signal backup, WhatsApp .zip, Telegram JSON) — forward-sync first, import in a follow-up phase
- **Worktree mass cleanup** — 28 worktrees accumulated; can clean up after this phase ships
- **Phase 45 (design principles)** — README principles rewrite deferred, not part of this push
- **Contabo restic backup re-setup** — clean deploy means backup state starts fresh; re-verify restic after this phase stabilizes

</deferred>

---

*Phase: 46-big-push-deploy-integrate-and-test-all-recent-work*
*Context gathered: 2026-02-28*
