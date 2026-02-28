# Phase 46 Research: Big Push -- Deploy, Integrate, and Test All Recent Work

**Researcher:** Claude Opus 4.6
**Date:** 2026-02-28
**Status:** Complete

---

## 1. Contabo Bootstrap Procedure

### Current Infrastructure

The Contabo host configuration lives in two places:
- **Public:** `/data/projects/neurosys/hosts/neurosys/default.nix` -- basic host identity, grub device, sops file, srvos overrides
- **Private:** `/data/projects/private-neurosys/hosts/neurosys/default.nix` -- static IP (`161.97.74.121/18`), gateway (`161.97.64.1`), DNS (`213.136.95.10`, `213.136.95.11`), port 8443 firewall addition

### Disko Layout

Five BTRFS subvolumes on `/dev/sda` (GPT, 2M BIOS boot + 512M ESP + remaining BTRFS):
- `@root` -> `/` (ephemeral, rolled back on reboot)
- `@nix` -> `/nix`
- `@persist` -> `/persist` (neededForBoot=true)
- `@log` -> `/var/log` (neededForBoot=true)
- `@docker` -> `/var/lib/docker`

Config: `/data/projects/neurosys/hosts/neurosys/disko-config.nix`

### SSH Host Key and Age Key Derivation

**Process:**
1. Generate fresh SSH ed25519 host key: `ssh-keygen -t ed25519 -f /tmp/ssh_host_ed25519_key -N ""`
2. Derive age public key: `cat /tmp/ssh_host_ed25519_key.pub | nix run nixpkgs#ssh-to-age`
3. Update `&host_neurosys` in BOTH `.sops.yaml` files (public + private repos) with the new age key
4. Re-encrypt secrets: `sops updatekeys secrets/neurosys.yaml` in both repos
5. Place key in extra-files: `tmp/neurosys-host-keys/persist/etc/ssh/ssh_host_ed25519_key`

**Critical detail:** The current `&host_neurosys` key in `.sops.yaml` is `age1sczx067gq0grjm0kunw6m9z0vgxdtt357ksnzdhw78sh25hkmauqqkxf24`. This MUST be replaced with the new key derived from the freshly generated SSH host key.

### Bootstrap Command (Adapted from OVH Script)

The OVH bootstrap script (`/data/projects/neurosys/scripts/bootstrap-ovh.sh`) provides the pattern. For Contabo:

```bash
nix run github:nix-community/nixos-anywhere -- \
  --extra-files tmp/neurosys-host-keys \
  --flake /data/projects/private-neurosys#neurosys \
  -i ~/.ssh/id_ed25519 \
  "root@161.97.74.121"
```

**Key differences from OVH:**
- Contabo uses Ubuntu (not rescue mode), so `/dev/sda` is the correct disk (no rescue disk present)
- No PAM password expiry handling needed (Contabo provides direct root SSH with key)
- Static IP requires networking config in the NixOS host config (already present in private overlay)
- Use the PRIVATE overlay flake (`private-neurosys#neurosys`), not the public one

**No bootstrap-contabo.sh exists.** The planner should consider creating one adapting `bootstrap-ovh.sh`, or documenting a manual procedure.

### Impermanence Boot Ordering

The `setupSecrets` activation script depends on `persist-files` (in `impermanence.nix` line 26-28). This ensures the SSH host key is bind-mounted from `/persist/etc/ssh/` to `/etc/ssh/` before sops-nix tries to derive the age key. This is critical and already correctly configured.

### Post-Bootstrap Manual Steps

1. **Tailscale auth:** New Tailscale auth key needed in sops (`tailscale-authkey` secret)
2. **Remove old Tailscale node:** Delete old `neurosys` from Tailscale admin to avoid `-1` suffix
3. **SSH known_hosts:** Clear old host key from local `~/.ssh/known_hosts`
4. **Cachix auth token:** Add `cachix-auth-token` to sops (currently missing -- see Cachix section)

---

## 2. Unmerged Branch Analysis

### Branch: `fix/35-reenable-bridges-v2`

**Commits:** 0 unique (merge base `f4fb6d9` is the tip of the branch -- this means the branch was likely already merged or represents the same point)

**Diff from main:** 47 files changed, 2268 insertions, 2478 deletions. This is a MASSIVE diff.

**Critical finding:** This branch represents a PRE-open-source state of the repo. It includes:
- `modules/default.nix` with ALL modules (homepage, restic, repos, spacebot, automaton, matrix, openclaw) imported directly -- contradicts the current public/private split
- Personal identifiers (`dangirsh` instead of `myuser`, `/home/dangirsh` instead of `/home/myuser`)
- Removal of the `setupSecrets` dependency on `persist-files` from impermanence.nix (dangerous!)
- Many service-specific port additions to `internalOnlyPorts` in networking.nix

**Recommendation:** Do NOT merge this branch as-is. The module imports and personal identifiers are incompatible with the current public/private repo split. Cherry-pick only the specific mautrix bridge fixes:
- `5856943` -- fix(matrix): remove appservice.database from bridgev2 services
- `dd51dbe` / `f4fb6d9` -- feat(matrix): re-enable mautrix-whatsapp and mautrix-signal bridges
- `fd8e9b6` -- fix(matrix): guard MemoryDenyWriteExecute override with mkIf enable

BUT these changes are already present in `modules/matrix.nix` on main. The current main `matrix.nix` already has all three bridges enabled with the correct `mkIf` guard and no `appservice.database` on bridgev2 services. **This branch has no remaining unique value.**

### Branch: `feat/35-matrix-client`

**Commits:** 0 unique from main (same pattern as above -- branch diverged long ago, main has moved past it)

**Diff from main:** 23 files changed, 1155 insertions, 908 deletions. Context says "1 uncommitted change in modules/homepage.nix."

**Assessment:** The diff is mostly the same open-source migration changes as the bridges branch. The homepage Matrix widget was the unique contribution, but homepage.nix has been significantly restructured since (now in private overlay). **This branch has no remaining unique value** for the current architecture.

### Branch: `ha-oauth-fix`

**Commits:** 1 unique: `14c1892 feat(34): nginx OAuth bridge for HA MCP -- fix /authorize 404`

**Changes:**
- `modules/nginx.nix`: Adds OAuth path bridge (nginx on 127.0.0.1:8124) that translates `/authorize` -> `/auth/authorize` and `/token` -> `/auth/token`
- `modules/home-assistant.nix`: Changes Tailscale Serve to proxy to nginx:8124 instead of HA:8123
- `modules/networking.nix`: Adds ports 8123 and 8124 to `internalOnlyPorts`

**Assessment:** The phase context says MCP auth will use long-lived access tokens, not OAuth. The HA MCP server documentation confirms it supports both OAuth AND long-lived tokens. Claude Android configures MCP connectors via claude.ai settings, which supports OAuth.

**Recommendation:** The `internalOnlyPorts` additions (8123, 8124) are independently valuable and should be cherry-picked. The nginx OAuth bridge itself is NOT needed if using long-lived tokens, but COULD be useful if OAuth is preferred for Claude Android MCP (which it is -- the HA docs show Claude Desktop uses OAuth). **Keep this branch available but do not merge yet.** Evaluate during implementation whether long-lived token or OAuth is simpler for Claude Android.

### Branch: `phase-39-02`

**Commits:** 5 unique: Conway dashboard module + flake input

**Changes:**
- `flake.nix`: Adds `conway-dashboard` flake input
- `modules/automaton-dashboard.nix`: New module (Conway dashboard on port 9093)
- `modules/default.nix`: Imports automaton-dashboard.nix
- Various planning/state files

**Assessment:** This belongs in the PRIVATE overlay, not the public repo. The private overlay's `flake.nix` already has `conway-dashboard` as an input and `./modules/automaton-dashboard.nix` in `contaboModules`. The private overlay already has `modules/automaton-dashboard.nix`.

**Recommendation:** Do NOT merge to public main. The private overlay already contains this work. **This branch is superseded.**

### Summary: Branch Disposition

| Branch | Action | Reason |
|--------|--------|--------|
| `fix/35-reenable-bridges-v2` | **Delete** | Superseded; matrix.nix on main already has all fixes |
| `feat/35-matrix-client` | **Delete** | Superseded; homepage now in private overlay |
| `ha-oauth-fix` | **Evaluate** | Cherry-pick `internalOnlyPorts` additions; OAuth bridge only if needed |
| `phase-39-02` | **Delete** | Superseded; private overlay already has dashboard |

---

## 3. Matrix Module Migration

### Current State

- **Public repo:** `modules/matrix.nix` exists on main with full Conduit + 3 bridges config. NOT imported by `modules/default.nix`.
- **Private overlay:** `modules/matrix.nix` exists (identical content). Listed in `contaboModules` but COMMENTED OUT (`# ./modules/matrix.nix  # disabled: pending legacy config migration`).
- **Guard:** Both versions use `lib.mkIf isNeurosys` where `isNeurosys = config.networking.hostName == "neurosys"`.

### Critical Issue: Host Guard Conflicts with OVH Deployment

The phase context says bridges should run on **OVH** (`neurosys-prod`), NOT Contabo. But the module's `isNeurosys = config.networking.hostName == "neurosys"` guard prevents activation on OVH (hostname `neurosys-prod`).

**Required changes to deploy bridges on OVH:**

1. **Change the host guard** in matrix.nix:
   - Option A: Replace `isNeurosys` with `isOvh = config.networking.hostName == "neurosys-prod"` and use `lib.mkIf isOvh`
   - Option B: Remove the guard entirely and control activation via `contaboModules` vs OVH-specific module list in private overlay's flake.nix

2. **Move matrix.nix from contaboModules to OVH modules** in private overlay's flake.nix:
   ```nix
   ovhModules = [
     ./modules/matrix.nix
   ];
   # Then: mkHost (commonModules ++ ovhModules) ./hosts/ovh;
   ```

3. **Add impermanence paths for OVH:** The current impermanence.nix already includes `/var/lib/mautrix-telegram`, `/var/lib/mautrix-whatsapp`, `/var/lib/mautrix-signal`. These are in the shared impermanence.nix, so they'll be available on both hosts.

4. **Secrets:** matrix.nix references three sops placeholders:
   - `matrix-registration-token`
   - `telegram-api-id`
   - `telegram-api-hash`

   These must exist in `secrets/ovh.yaml` (currently they likely only exist in `secrets/neurosys.yaml`). Need to add them to OVH's sops file.

5. **Conduit data:** `/var/lib/matrix-conduit` is NOT in the impermanence persist list. It needs to be added for OVH (or Conduit will lose state on reboot).

### "Legacy Config Migration" -- What Does It Mean?

The comment says "pending legacy config migration." Based on the branch history:
- mautrix bridges were enabled, then disabled (`717aecb fix(matrix): re-disable mautrix-whatsapp and mautrix-signal pending legacy config migration`), then re-enabled (`f4fb6d9`)
- The "legacy" likely refers to stale bridge registration files or Conduit state from a previous deployment that conflicts with a fresh start

For OVH (clean deploy, no existing state), there is NO legacy config to migrate. The module can be enabled directly.

### Recommendation (Option B preferred)

Remove the `isNeurosys` guard entirely from matrix.nix (both repos). Control host-specific activation purely through the private overlay's flake.nix module list. This is cleaner and consistent with how other host-specific modules are handled (e.g., `contaboModules` vs `commonModules`).

---

## 4. MCP DM Queryability Options

The user wants to query DMs (Signal, WhatsApp, Telegram) from Claude Android via MCP. Two approaches evaluated:

### Option A: HA Matrix Integration + HA MCP Server

**How it works:** HA's built-in Matrix integration allows sending/receiving commands via Matrix rooms. The HA MCP server (`mcp_server` component, already enabled) would expose Matrix-connected entities to Claude.

**Limitations:**
- HA's Matrix integration is primarily for **sending notifications and reacting to commands** -- it does NOT expose room messages as queryable entities/sensors
- No way to "read the last 10 messages from my WhatsApp chat" through HA entities
- Would need a custom HA integration to bridge Matrix rooms to HA sensors, which is significant development work
- The HA MCP server only exposes entities configured for "voice control access"

**Verdict:** Not suitable. The HA Matrix integration does not provide message queryability.

### Option B: Dedicated Matrix MCP Server

**How it works:** A standalone MCP server (e.g., `mjknowles/matrix-mcp-server`) connects directly to the Conduit homeserver and exposes Matrix rooms/messages as MCP tools.

**Features of `mjknowles/matrix-mcp-server`:**
- 15 Matrix tools including room listing, message retrieval, user profiles
- Tier 0 (read-only): Room info, message retrieval, user profiles, public room search
- Tier 1 (action): Message sending, room creation/management
- HTTP transport (Express-based)
- OAuth 2.0 or direct token auth
- TypeScript/Node.js

**Deployment approach:**
1. Run matrix-mcp-server as a NixOS systemd service on OVH (alongside Conduit)
2. Configure it to connect to Conduit at `http://localhost:6167`
3. Expose it via Tailscale Serve on a dedicated HTTPS endpoint
4. Register in Claude Android as a custom connector

**Gaps:**
- No Nix package exists (would need `buildNpmPackage`)
- OAuth support on Claude.ai side may require additional configuration
- Conduit compatibility not explicitly confirmed (but uses standard Matrix client-server API)

### Option C: Simple Custom MCP Server (Minimal)

Write a minimal Python/Node MCP server that:
- Connects to Conduit via the Matrix client-server API
- Exposes `list_rooms` and `read_messages(room_id, count)` tools
- Runs as a systemd service, exposed via Tailscale Serve
- Uses streamable HTTP transport

This avoids the dependency on `mjknowles/matrix-mcp-server` and can be tailored exactly to the need.

### Recommendation

**Option B (dedicated Matrix MCP server)** is the right approach. Between the existing `mjknowles/matrix-mcp-server` and a custom implementation (Option C), the planner should choose based on build complexity:

- If Nix packaging of the existing server is straightforward -> Option B
- If packaging is complex (npm workspace issues, native deps) -> Option C (custom minimal server)

Either way, the HA MCP server (Option A) is NOT the path for DM queryability.

---

## 5. Claude Android MCP Setup

### Configuration Flow

1. Claude Android does NOT support configuring MCP servers directly
2. Configuration is done via **claude.ai website** -> Settings -> Connectors -> Add Custom Connector
3. Settings sync automatically across web, desktop, and mobile

### Auth Options

The HA MCP server supports two auth methods:
1. **OAuth (preferred by Claude):** HA implements IndieAuth-style OAuth. Claude.ai initiates OAuth flow with callback `https://claude.ai/api/mcp/auth_callback`. No pre-registration of client ID needed (HA uses IndieAuth).
2. **Long-lived access token:** For clients that cannot do OAuth. Generated in HA UI -> Profile -> Long-Lived Access Tokens.

### MCP Endpoint

The endpoint is already configured: `https://neurosys.taildb9d4d.ts.net/mcp`

This is served by `tailscale-serve-ha` systemd service which proxies HTTPS 443 -> HA 8123.

### Setup Steps

1. Ensure HA is running on Contabo with MCP server component enabled
2. Ensure Tailscale Serve is active (`tailscale-serve-ha.service`)
3. Ensure Claude Android phone is on the same Tailscale tailnet
4. Go to claude.ai -> Settings -> Connectors -> Add Custom Connector
5. Enter name: "Home Assistant" and URL: `https://neurosys.taildb9d4d.ts.net/mcp`
6. Complete OAuth flow (HA will show consent screen) OR configure with long-lived token
7. Verify on Claude Android: the connector should appear and provide HA tools

### Entity Exposure

Per context: expose ALL HA entities. In HA UI -> Settings -> Voice Control -> Expose Entities, enable all entities. The MCP server only sees entities that are exposed for voice control.

### Test Verification

Use any Hue light on the bridge. Ask Claude Android to "turn on the living room light" or similar. Physical light response confirms end-to-end MCP connectivity.

### Important Note: HA MCP is on Contabo

The HA MCP endpoint is at `https://neurosys.taildb9d4d.ts.net/mcp` -- this is the Contabo Tailscale hostname. HA runs on Contabo (in `contaboModules`), not OVH. The Contabo bootstrap must complete before MCP testing can happen.

---

## 6. OVH Current State and Gaps

### Current Configuration

- **Host config:** `/data/projects/private-neurosys/hosts/ovh/default.nix`
- **DHCP networking** (OVH assigns static via DHCP)
- **SSH port 22 open** on public interface (OVH-01 decision)
- **sops.age.sshKeyPaths** explicitly points to `/persist/etc/ssh/...` (OVH-02 decision)
- **Deploy node:** `hostname = "neurosys-prod"` via Tailscale MagicDNS

### Services Currently on OVH

Based on `commonModules` in private overlay flake.nix, OVH receives:
- srvos server baseline
- disko, impermanence, sops-nix, home-manager
- parts NixOS module
- Public modules (base, boot, users, networking, secrets, docker, monitoring, syncthing, agent-compute, secret-proxy, impermanence)
- Private replacements: users.nix, syncthing.nix, agent-compute.nix, homepage.nix
- Private-only: secrets.nix, repos.nix

OVH does NOT receive `contaboModules` (nginx, home-assistant, spacebot, automaton, automaton-dashboard, openclaw, claw-swap, matrix).

### Gaps for Bridge Deployment on OVH

1. **matrix.nix not in OVH modules:** Must create `ovhModules` list or move matrix.nix to `commonModules`
2. **Matrix secrets missing from OVH sops:** `secrets/ovh.yaml` needs `matrix-registration-token`, `telegram-api-id`, `telegram-api-hash`
3. **Conduit persist path missing:** `/var/lib/matrix-conduit` not in impermanence.nix persist directories
4. **No Matrix MCP server module:** If choosing Option B/C for DM queryability, a new module is needed
5. **olm insecure package allowance:** matrix.nix allows `olm-3.2.16` -- this is scoped to `isNeurosys` which must change for OVH
6. **deploy.sh service health checks:** OVH currently checks `prometheus`, `syncthing`, `tailscaled`. Should add Matrix services: `conduit`, `mautrix-telegram`, `mautrix-whatsapp`, `mautrix-signal`
7. **No Tailscale Serve on OVH:** The Matrix MCP server needs HTTPS exposure if Claude Android will connect. Currently only Contabo has Tailscale Serve configured (for HA).

### OVH Deploy Status

The private overlay has deploy-rs configured for OVH: `hostname = "neurosys-prod"`. The OVH VPS should already be running NixOS from Phase 27 deployment. Verify SSH connectivity before deploying bridge updates.

---

## 7. Cachix Setup

### Current State

- **Package installed:** `cachix` is in `modules/base.nix` system packages
- **Push logic:** `scripts/deploy.sh` (lines 275-288) pushes to `dan-testing.cachix.org` after successful Contabo deploy
- **Auth token referenced:** `CACHIX_AUTH_TOKEN=$(cat /run/secrets/cachix-auth-token)` in deploy.sh
- **Secret NOT declared:** `cachix-auth-token` is NOT in any `secrets.nix` (public or private). This is a gap.
- **Substituters commented out:** `modules/base.nix` lines 11-12 have placeholder comments for binary cache config

### Required Setup

1. **Declare sops secret** in private overlay's `secrets.nix`:
   ```nix
   sops.secrets."cachix-auth-token" = {};
   ```

2. **Add token to sops files:** Add `cachix-auth-token` to `secrets/neurosys.yaml` (for Contabo push) and optionally `secrets/ovh.yaml` (if OVH should also push)

3. **Enable substituters** in private overlay (override base.nix settings):
   ```nix
   nix.settings = {
     substituters = [ "https://dan-testing.cachix.org" ];
     trusted-public-keys = [ "dan-testing.cachix.org-1:<PUBLIC_KEY>" ];
   };
   ```
   The public key is obtained from `cachix use dan-testing`.

4. **Both hosts pull from Cachix:** Add substituters to both neurosys and OVH configs (via commonModules or private base override)

5. **Only Contabo pushes:** deploy.sh already gates Cachix push on `$NODE == "neurosys"`

### Cachix Workflow

- After Contabo deploy: deploy.sh automatically pushes the system closure to Cachix
- OVH deploys: `nix build` fetches from Cachix first, avoiding redundant builds for shared derivations
- Net effect: OVH deploy is faster because it pulls pre-built closures from Contabo's Cachix push

---

## 8. Deployment Order Analysis

### Dependency Graph

```
1. Merge/cleanup branches (prerequisite for clean main)
   |
2. Generate Contabo SSH host key + re-encrypt sops
   |
3. Bootstrap Contabo (nixos-anywhere)
   |-- Needs: new SSH key in extra-files, new Tailscale authkey in sops
   |-- Produces: running NixOS with Tailscale, sops working
   |
4. Post-bootstrap Contabo verification
   |-- SSH via Tailscale, all services green
   |-- Cachix push
   |
5. Deploy OVH with bridge modules
   |-- Needs: matrix secrets in ovh.yaml, matrix.nix migration
   |-- Can happen in parallel with step 4
   |
6. Bridge pairing (manual, per-platform)
   |-- Telegram: automatic (API key in sops)
   |-- WhatsApp: QR code pairing (manual)
   |-- Signal: linked device (manual)
   |
7. HA re-initialization on Contabo
   |-- Clone home-assistant-config repo
   |-- Re-pair Hue bridge (manual: press link button)
   |-- Re-pair ESPHome devices
   |-- Generate long-lived access token
   |
8. MCP setup
   |-- HA MCP: configure in claude.ai connectors
   |-- Matrix MCP (if implemented): deploy server, configure in claude.ai
   |
9. Circadian lighting verification
   |-- Pull automations.yaml on server
   |-- Reload HA automations
   |-- Verify sunset trigger
   |
10. Open-source repo verification
    |-- grep -r "dangirsh" on public repo
    |-- nix flake check passes
    |
11. Worktree cleanup
    |-- 28 worktrees to prune
    |
12. Phase closure
    |-- Close phases 27, 28, 32, 37, 39, 44
```

### Recommended Order

**Contabo first, then OVH:**
- Contabo bootstrap is the highest-risk step (full OS reinstall)
- HA/MCP testing depends on Contabo being live
- Cachix push from Contabo speeds up OVH deploy
- Bridge setup on OVH is independent but lower priority

### Parallel Opportunities

- While Contabo bootstraps (10-20 min): prepare OVH sops secrets and matrix.nix migration
- After Contabo is up: start OVH deploy in parallel with HA re-initialization
- Worktree cleanup and phase closure can happen anytime

---

## 9. Worktree Cleanup

28 worktrees exist. Most correspond to completed or superseded phases. Safe to remove all except the main worktree:

```
.claude/worktrees/fix-35-bridges       -> fix/35-reenable-bridges (superseded)
.claude/worktrees/phase-38             -> gsd/phase-38 (completed)
.worktrees/beads-pkg                   -> beads-pkg (evaluate)
.worktrees/feat/35-matrix-client       -> feat/35-matrix-client (superseded)
.worktrees/fix-api-acme                -> fix-api-acme (evaluate)
.worktrees/fix-sops-ordering           -> fix/sops-boot-ordering (merged)
.worktrees/fix/35-reenable-bridges-v2  -> fix/35-reenable-bridges-v2 (superseded)
.worktrees/ha-oauth-fix                -> ha-oauth-fix (evaluate)
.worktrees/ovh-bootstrap               -> ovh-bootstrap (completed)
.worktrees/phase-13-02-hardening       -> phase-13-02-hardening (completed)
.worktrees/phase-30-docs               -> phase-30-docs (completed)
.worktrees/phase-37-wave2              -> phase-37-wave2 (completed)
.worktrees/rm-api-vhost                -> rm-api-vhost (evaluate)
tmp/24-01-hardening-dx                 -> phase24-01-hardening-dx (completed)
tmp/39-02-conway-dashboard             -> phase-39-02 (superseded)
tmp/phase-37-01                        -> phase-37-01-privacy-audit (completed)
tmp/phase-54-02-site-monitor           -> gsd/phase-54-02-site-monitor (evaluate)
tmp/worktrees/deploy-impermanence      -> deploy/impermanence-migration (completed)
tmp/worktrees/phase-22-cleanup         -> phase-22-cleanup (completed)
tmp/worktrees/phase-22-secret-proxy    -> phase-22-secret-proxy (completed)
tmp/worktrees/phase-28-02              -> phase-28-02-nginx (completed)
tmp/worktrees/phase-28-03-staging      -> phase-28-03-staging (completed)
tmp/worktrees/phase-28-cf-dns          -> phase-28-cf-dns (completed)
tmp/worktrees/phase-28-staging-subdomain -> phase-28-staging-subdomain (completed)
tmp/worktrees/phase-32-01-automaton    -> phase-32-01-automaton (completed)
tmp/worktrees/phase-32-02-automaton-svc -> phase-32-02-automaton-svc (completed)
tmp/worktrees/phase-36-01-stereos-research -> phase-36-01-stereos-research (completed)
tmp/worktrees/phase27-02-ovh-multihost -> phase27-02-ovh-multihost (completed)
```

**Cleanup command:**
```bash
git worktree list --porcelain | grep '^worktree ' | grep -v '/data/projects/neurosys$' | \
  sed 's/^worktree //' | while read wt; do git worktree remove --force "$wt"; done
```

Then prune stale branches:
```bash
git branch | grep -v '^\*\|main' | xargs git branch -D
```

---

## 10. Risks and Unknowns

### High Risk
1. **Contabo bootstrap failure:** If static IP config is wrong, the VPS loses network and requires Contabo console access to fix. The private overlay has the correct IP/gateway/DNS -- verify these match Contabo's current assignment.
2. **sops re-encryption:** If the new age key derivation is wrong, ALL secrets fail to decrypt on boot. Test with `sops --decrypt secrets/neurosys.yaml` using the new key before deploying.
3. **olm insecure package:** nixpkgs may have updated `olm` version. The `permittedInsecurePackages = [ "olm-3.2.16" ]` must match the current nixpkgs version.

### Medium Risk
4. **Matrix-Conduit compatibility with mautrix bridges:** Conduit is a lightweight server; some mautrix features may not work (e.g., appservice registration). Test bridges in isolation before wiring DM queryability.
5. **WhatsApp ban risk:** mautrix-whatsapp uses unofficial protocol. Account could be flagged. Accepted risk per MTX-05.
6. **Tailscale name collision:** If old `neurosys` node still in tailnet, new node gets `-1` suffix.

### Low Risk
7. **Cachix auth token missing from sops:** Non-fatal; deploy.sh prints warning and continues.
8. **Circadian automation requires manual HA setup:** Hue bridge needs physical button press; ESPHome auto-discovers.

### Unknowns
- Whether Contabo VPS has already been reinstalled with Ubuntu or still has old NixOS
- Whether the old Tailscale node has been removed from the tailnet admin
- Whether OVH is still reachable via Tailscale (or needs SSH via public IP)
- Exact olm version in current nixpkgs 25.11
- Whether `mjknowles/matrix-mcp-server` works with Conduit (untested)

---

## 11. Secrets Inventory

### Contabo (`secrets/neurosys.yaml`) -- Needs These Secrets

| Secret | Status | Notes |
|--------|--------|-------|
| `tailscale-authkey` | **NEEDS NEW** | Generate reusable key from Tailscale admin |
| `anthropic-api-key` | Existing | Re-encrypt with new age key |
| `github-pat` | Existing | Re-encrypt with new age key |
| `google-api-key` | Existing | Re-encrypt with new age key |
| `openai-api-key` | Existing | Re-encrypt with new age key |
| `openrouter-api-key` | Existing | Re-encrypt with new age key |
| `xai-api-key` | Existing | Re-encrypt with new age key |
| `cloudflare-dns-token` | Existing | Re-encrypt with new age key |
| `ha-token` | **NEEDS NEW** | Generate after HA re-initializes |
| `cachix-auth-token` | **NEEDS NEW** | Add to sops + declare in secrets.nix |
| `conway-api-key` | Existing | Re-encrypt with new age key |
| `creator-address` | Existing | Re-encrypt with new age key |
| `restic-password` | Existing | Re-encrypt with new age key |
| `restic-b2-*` | Existing | Re-encrypt with new age key |
| Various openclaw tokens | Existing | Re-encrypt with new age key |

### OVH (`secrets/ovh.yaml`) -- Needs These Additional Secrets for Bridges

| Secret | Status | Notes |
|--------|--------|-------|
| `matrix-registration-token` | **NEEDS NEW** | For Conduit registration |
| `telegram-api-id` | **NEEDS NEW** | Telegram API credentials |
| `telegram-api-hash` | **NEEDS NEW** | Telegram API credentials |

---

## 12. Key Files Reference

| File | Path | Purpose |
|------|------|---------|
| Public flake | `/data/projects/neurosys/flake.nix` | Public NixOS config entrypoint |
| Private flake | `/data/projects/private-neurosys/flake.nix` | Private overlay with real services |
| Contabo host (public) | `/data/projects/neurosys/hosts/neurosys/default.nix` | Basic host identity |
| Contabo host (private) | `/data/projects/private-neurosys/hosts/neurosys/default.nix` | Static IP, firewall |
| OVH host (public) | `/data/projects/neurosys/hosts/ovh/default.nix` | OVH-specific config |
| OVH host (private) | `/data/projects/private-neurosys/hosts/ovh/default.nix` | OVH-specific config |
| Disko config | `/data/projects/neurosys/hosts/neurosys/disko-config.nix` | BTRFS subvolume layout |
| Matrix module | `/data/projects/private-neurosys/modules/matrix.nix` | Conduit + mautrix bridges |
| Impermanence | `/data/projects/neurosys/modules/impermanence.nix` | Persist paths |
| HA module | `/data/projects/private-neurosys/modules/home-assistant.nix` | HA + Tailscale Serve |
| Sops config (public) | `/data/projects/neurosys/.sops.yaml` | Age key recipients |
| Sops config (private) | `/data/projects/private-neurosys/.sops.yaml` | Same recipients |
| Deploy script | `/data/projects/neurosys/scripts/deploy.sh` | deploy-rs wrapper |
| Bootstrap OVH | `/data/projects/neurosys/scripts/bootstrap-ovh.sh` | Reference for Contabo bootstrap |
