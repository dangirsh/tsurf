# Phase 25: Deploy Safety with deploy-rs - Research

**Researched:** 2026-02-20
**Domain:** NixOS deployment safety, deploy-rs magic rollback, flake integration
**Confidence:** HIGH

## Summary

deploy-rs (serokell/deploy-rs) is a Rust-based NixOS deployment tool that adds magic rollback safety to remote deployments. Its key value proposition for this project: after activating a new NixOS generation, deploy-rs creates a canary file on the target and watches it via inotify. If the deployer cannot SSH back to delete the canary within a configurable timeout (default 30s, we want 120s), the target automatically rolls back to the previous generation. This prevents permanent lockout on a Tailscale-only server where a bad networking/firewall change would otherwise be unrecoverable.

Integration is straightforward: add deploy-rs as a flake input, define `deploy.nodes.neurosys` pointing to the existing `nixosConfigurations.neurosys`, and add `deployChecks` to the flake's `checks` output. The existing `deploy.sh` evolves into a thin wrapper: update flake inputs, run `deploy .#neurosys`, then verify container health. The `nixos-rebuild switch --target-host` call is replaced by `deploy .#neurosys` which handles build, copy, activate, and rollback safety in one step.

There is one critical first-deploy pitfall: since the current system was deployed with `nixos-rebuild` (not deploy-rs), the first deploy-rs activation has no deploy-rs-compatible previous generation to roll back to. If magic rollback triggers on the first deploy, it will fail with "No such file or directory" because the previous generation lacks `deploy-rs-activate`. The workaround is to run the first deploy with `--magic-rollback false` to establish the initial deploy-rs generation, then enable magic rollback for all subsequent deploys.

**Primary recommendation:** Add deploy-rs as a flake input with `inputs.nixpkgs.follows = "nixpkgs"`. Define `deploy.nodes.neurosys` with `confirmTimeout = 120` and `magicRollback = true`. Run the first deploy with `--magic-rollback false`. Evolve `deploy.sh` to call `deploy .#neurosys --confirm-timeout 120` instead of `nixos-rebuild switch --target-host`.

## Standard Stack

### Core

| Component | Source | Purpose | Why Standard |
|-----------|--------|---------|--------------|
| deploy-rs | `github:serokell/deploy-rs` | NixOS deployment with magic rollback | The only Nix deployment tool with inotify-based automatic rollback; written in Rust |
| deploy-rs CLI | `nix run github:serokell/deploy-rs` or via devShell | Execute deployments from local machine | Built from the same flake input; no separate installation needed |
| deploy-rs.lib.activate.nixos | deploy-rs flake output | Wraps `nixosConfigurations` into deployable profiles | Standard activation function; calls `switch-to-configuration switch` with rollback wrapper |
| deploy-rs.lib.deployChecks | deploy-rs flake output | Validate deploy config at `nix flake check` time | Schema validation + activation script existence checks |

### Supporting

| Component | Source | Purpose | When to Use |
|-----------|--------|---------|-------------|
| deploy-rs.lib.activate.custom | deploy-rs flake output | Custom activation scripts | Not needed -- `activate.nixos` handles NixOS systems |
| `--dry-activate` CLI flag | deploy-rs CLI | Preview what will change without applying | Pre-deploy verification; runs `switch-to-configuration dry-activate` |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| deploy-rs | Colmena | Colmena has no magic rollback; designed for multi-host fleets; overkill for single host |
| deploy-rs | nixos-rebuild (current) | No automatic rollback; a bad deploy = permanent lockout on Tailscale-only server |
| deploy-rs | comin (GitOps pull) | Paradigm shift to pull-based; agent runs on server; no rollback safety |

## Architecture Patterns

### Flake Configuration

```nix
# In flake.nix inputs:
deploy-rs = {
  url = "github:serokell/deploy-rs";
  inputs.nixpkgs.follows = "nixpkgs";
};

# In flake.nix outputs:
deploy.nodes.neurosys = {
  hostname = "neurosys";  # Tailscale MagicDNS
  sshUser = "root";
  magicRollback = true;
  confirmTimeout = 120;   # 120s for Tailscale reconnection margin
  profiles.system = {
    user = "root";
    path = deploy-rs.lib.x86_64-linux.activate.nixos
      self.nixosConfigurations.neurosys;
  };
};

# Add deploy-rs checks to flake checks:
checks = builtins.mapAttrs
  (system: deployLib: deployLib.deployChecks self.deploy)
  deploy-rs.lib;
```

### Deploy Script Evolution

The current `deploy.sh` structure stays mostly intact. The core change is replacing the `nixos-rebuild switch --target-host` call with `deploy .#neurosys`:

```bash
# BEFORE (current deploy.sh):
nix shell nixpkgs#nixos-rebuild -c \
  nixos-rebuild switch \
    --flake "$FLAKE_DIR#neurosys" \
    --target-host "$TARGET"

# AFTER (evolved deploy.sh):
nix run github:serokell/deploy-rs -- \
  "$FLAKE_DIR#neurosys" \
  --confirm-timeout 120
```

Everything else stays: flake input update, lock management, container health polling, local+remote locking, reporting.

### CLI Flags Reference (from source: src/cli.rs)

| Flag | Type | Default | Purpose |
|------|------|---------|---------|
| `--magic-rollback` | bool | true | Enable/disable inotify canary rollback |
| `--confirm-timeout` | u16 | 30 | Seconds to wait for confirmation before rollback |
| `--activation-timeout` | u16 | 240 | Seconds allowed for profile activation |
| `--auto-rollback` | bool | true | Roll back on activation script failure |
| `--dry-activate` | flag | false | Preview changes without applying |
| `--skip-checks` | flag | false | Skip `nix flake check` before deploying |
| `--remote-build` | flag | false | Build on target instead of locally |
| `--ssh-user` | string | current user | Override SSH user |
| `--hostname` | string | from config | Override target hostname |
| `--ssh-opts` | string | none | Extra SSH options |
| `--fast-connection` | bool | false | Copy full closure vs. use remote substituters |
| `--boot` | flag | false | Update bootloader only (no live activate) |
| `--rollback-succeeded` | bool | true | Roll back successful deploys if later ones fail |
| `--temp-path` | path | /tmp | Where to store canary file on target |

### Anti-Patterns to Avoid

- **Using deploy-rs for networking-breaking changes with magicRollback ON:** If you intentionally change the SSH port, IP address, or disable Tailscale, magic rollback will trigger (it cannot SSH back). Disable magic rollback for those specific deploys: `deploy .#neurosys --magic-rollback false`.
- **Running first deploy with magicRollback ON:** The first deploy-rs deployment has no deploy-rs-compatible previous generation. If rollback triggers, it crashes. Use `--magic-rollback false` for the first deploy only.
- **Setting confirmTimeout too low:** Default is 30s. For Tailscale, services may restart during activation (including tailscaled). A 120s timeout gives margin for Tailscale reconnection after service restarts.
- **Forgetting deployChecks in flake checks:** Without `deployChecks`, `nix flake check` won't validate the deploy configuration. Always add the checks output.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Automatic rollback on connectivity loss | Custom watchdog timer + SSH health check script | deploy-rs magic rollback (inotify canary) | Canary-based rollback is battle-tested; handles edge cases (systemd restart ordering, activation timing) that a custom script would miss |
| NixOS profile activation with safety | Custom `switch-to-configuration` wrapper with error handling | `deploy-rs.lib.activate.nixos` | Handles dry-activate, boot mode, switch mode, and wraps with deploy-rs-activate for rollback compatibility |
| Deploy config validation | Manual review of deploy target config | `deploy-rs.lib.deployChecks` | Schema validation + activation script existence checks; runs automatically in `nix flake check` |

**Key insight:** deploy-rs's value is entirely in the magic rollback mechanism. The actual deployment (build, copy, activate) is similar to `nixos-rebuild --target-host`. The 15 lines of flake config buy automatic rollback safety that would be extremely complex to hand-roll.

## Common Pitfalls

### Pitfall 1: First Deploy Rollback Crash (Issue #86)

**What goes wrong:** The first deploy-rs deployment to a system previously managed by `nixos-rebuild` triggers magic rollback (e.g., because activation took too long), and deploy-rs tries to execute `deploy-rs-activate` from the previous generation. That generation was created by `nixos-rebuild`, not deploy-rs, so `deploy-rs-activate` doesn't exist. The rollback fails with "No such file or directory (os error 2)".

**Why it happens:** deploy-rs assumes the previous NixOS generation contains its own activation scripts. Generations created by `nixos-rebuild` don't have these scripts.

**How to avoid:** Run the first deploy with `--magic-rollback false`. This establishes a deploy-rs-compatible generation. All subsequent deploys can use magic rollback safely.

**Warning signs:** First deploy hangs or crashes with "os error 2" during rollback.

### Pitfall 2: Tailscale Service Restart During Activation

**What goes wrong:** A NixOS config change that touches Tailscale settings (e.g., `extraUpFlags`, auth key rotation) causes `tailscaled.service` to restart during activation. Tailscale briefly disconnects. deploy-rs cannot SSH back to confirm. Magic rollback triggers even though the deploy was fine.

**Why it happens:** The canary confirmation timeout starts immediately after activation. If Tailscale takes 10-15s to reconnect and the timeout is 30s, there's a race condition.

**How to avoid:** Set `confirmTimeout = 120` (2 minutes) in the node config. This provides generous margin for Tailscale reconnection. The phase description already specifies this value.

**Warning signs:** Deploys that change Tailscale config consistently trigger false rollbacks.

### Pitfall 3: deploy-rs Gets Stuck After Activation Failure (Issue #58, fixed)

**What goes wrong:** In earlier versions, if the activation script failed with a non-zero exit code while magic rollback was enabled, deploy-rs would hang until the timeout elapsed instead of failing immediately.

**Why it happens:** The SSH session wasn't properly monitored during magic rollback activation.

**How to avoid:** Use current deploy-rs (the fix was merged in PR #59). Pin via flake.lock as usual.

**Warning signs:** Deploy hangs for `confirmTimeout` seconds after an obvious activation failure.

### Pitfall 4: tempPath Permissions

**What goes wrong:** Magic rollback canary file creation fails because `/tmp` is not writable by the deployment user, or the temp directory doesn't exist.

**Why it happens:** The `tempPath` option defaults to `/tmp`. On hardened systems or with impermanence, `/tmp` may have restricted permissions or be ephemeral.

**How to avoid:** Default `/tmp` works fine on the current neurosys setup. If Phase 21 (Impermanence) is implemented later, verify that `/tmp` persists across activation or set `tempPath` to a persistent path.

**Warning signs:** Magic rollback fails with permission errors creating canary file.

### Pitfall 5: flake-utils Interaction

**What goes wrong:** Using `flake-utils.lib.eachDefaultSystem` to wrap deploy-rs outputs causes attribute lookup failures. deploy-rs expects `deploy.nodes` at the top level, not nested under a system architecture.

**Why it happens:** `deploy.nodes` is not system-specific (it describes remote hosts). Wrapping it in `eachDefaultSystem` breaks the expected schema.

**How to avoid:** Define `deploy.nodes` and `deploy-rs.lib.deployChecks` at the top level of flake outputs, not inside a per-system function. The current neurosys flake doesn't use flake-utils, so this is not a risk.

**Warning signs:** `nix flake check` fails with "attribute not found" for deploy config.

## Code Examples

### Complete Flake Integration

```nix
# flake.nix — deploy-rs integration
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    # ... existing inputs ...
    deploy-rs = {
      url = "github:serokell/deploy-rs";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, deploy-rs, ... } @ inputs: {
    nixosConfigurations.neurosys = nixpkgs.lib.nixosSystem {
      # ... existing config unchanged ...
    };

    # deploy-rs node configuration
    deploy.nodes.neurosys = {
      hostname = "neurosys";       # Tailscale MagicDNS
      sshUser = "root";
      magicRollback = true;
      autoRollback = true;
      confirmTimeout = 120;        # 2 min — margin for Tailscale reconnect
      profiles.system = {
        user = "root";
        path = deploy-rs.lib.x86_64-linux.activate.nixos
          self.nixosConfigurations.neurosys;
      };
    };

    # deploy-rs schema + activation checks (merged into existing checks if any)
    checks = builtins.mapAttrs
      (system: deployLib: deployLib.deployChecks self.deploy)
      deploy-rs.lib;
  };
}
```

Source: [deploy-rs README](https://github.com/serokell/deploy-rs), verified against deploy-rs flake.nix

### Evolved deploy.sh Core Logic

```bash
# Replace nixos-rebuild section with deploy-rs invocation:

# --- Build + deploy with magic rollback ---
if [[ "$MODE" == "local" ]]; then
  echo "==> Deploying to $TARGET with magic rollback..."
  nix run github:serokell/deploy-rs -- \
    "$FLAKE_DIR#neurosys" \
    --confirm-timeout 120
else
  echo "==> Deploying via remote build on $TARGET..."
  nix run github:serokell/deploy-rs -- \
    "$FLAKE_DIR#neurosys" \
    --confirm-timeout 120 \
    --remote-build
fi
```

Note: `--remote-build` replaces the current SSH-based remote mode. deploy-rs handles the SSH connection and remote build natively.

### First Deploy (One-Time)

```bash
# First deployment only — no magic rollback (no compatible previous generation)
nix run github:serokell/deploy-rs -- \
  .#neurosys \
  --magic-rollback false \
  --confirm-timeout 120
```

### Rollback Test Procedure

```bash
# 1. Deploy a known-good config
./scripts/deploy.sh

# 2. Intentionally break networking (e.g., add a bad firewall rule)
# Edit modules/networking.nix to add: networking.firewall.allowedTCPPorts = [ 22 ];
# (This will fail the port 22 assertion, but for rollback testing, use a
#  different breakage that passes check but breaks connectivity)

# 3. Deploy the broken config
./scripts/deploy.sh

# 4. Observe: deploy-rs cannot SSH back within 120s
# 5. Observe: target auto-rolls back to previous generation
# 6. Observe: SSH access restored after rollback
```

### Using deploy-rs from devShell (Alternative to nix run)

```nix
# Add to flake outputs:
devShells.x86_64-linux.default = nixpkgs.legacyPackages.x86_64-linux.mkShell {
  buildInputs = [ deploy-rs.packages.x86_64-linux.default ];
};

# Then:
# nix develop
# deploy .#neurosys --confirm-timeout 120
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `nixos-rebuild switch --target-host` (no rollback safety) | deploy-rs with magic rollback | This phase | Bad deploy no longer means permanent lockout |
| Manual rollback via `nixos-rebuild switch --rollback` (requires SSH access) | Automatic rollback via inotify canary | This phase | Server self-heals even when SSH is broken |
| deploy.sh calls nixos-rebuild directly | deploy.sh wraps deploy-rs | This phase | Same UX (single `deploy.sh` command), added safety layer |

**Deprecated/outdated:**
- The `nix shell nixpkgs#nixos-rebuild -c nixos-rebuild switch --target-host` pattern in deploy.sh is replaced by `nix run github:serokell/deploy-rs`. The `nixos-rebuild` tool is no longer needed as a direct dependency.

## Magic Rollback Mechanism — Detailed

Understanding the internal mechanism is important for debugging and for the rollback test:

1. **Build phase:** deploy-rs evaluates the flake, builds the NixOS closure (same as `nixos-rebuild build`).
2. **Copy phase:** Closure is copied to the target via `nix copy --to ssh://root@neurosys`.
3. **Activate phase:**
   a. deploy-rs SSHes to the target and runs `deploy-rs-activate`.
   b. `deploy-rs-activate` creates a canary file at `$tempPath/deploy-rs-canary-<uuid>`.
   c. An inotify watcher is started on the canary file.
   d. `switch-to-configuration switch` is executed (the actual NixOS activation).
   e. The inotify watcher waits up to `confirmTimeout` seconds for the canary to be deleted.
4. **Confirm phase:**
   a. After activation completes, the deployer (local machine) SSHes back to the target.
   b. If SSH succeeds, the deployer deletes the canary file.
   c. The inotify watcher sees the deletion and confirms the deploy.
5. **Rollback phase (only if confirm fails):**
   a. If the canary is NOT deleted within `confirmTimeout` seconds, the watcher fires.
   b. The previous NixOS generation's `deploy-rs-activate` is executed.
   c. `switch-to-configuration switch` runs with the previous generation's config.
   d. The server reverts to its pre-deploy state.

**Why 120s timeout for Tailscale:** Step 3d may restart `tailscaled.service` if the NixOS config touches Tailscale settings. Tailscale reconnection takes 5-15s typically, but can be longer if the coordination server is slow. 120s provides ample margin while still rolling back reasonably quickly on actual failures.

## Interaction with Existing deploy.sh Features

| Feature | Current (nixos-rebuild) | After (deploy-rs) | Notes |
|---------|------------------------|-------------------|-------|
| Local build + remote switch | `nixos-rebuild --target-host` | deploy default (fastConnection=false) | Same behavior; deploy-rs copies closure via SSH |
| Remote build | SSH + `nixos-rebuild` on server | `deploy --remote-build` | deploy-rs handles SSH and remote build natively |
| Flake input update | `nix flake update parts` | Same — deploy.sh still does this | deploy-rs doesn't manage flake inputs |
| Container health check | SSH + docker ps polling | Same — deploy.sh still does this after deploy | deploy-rs doesn't know about Docker |
| Local lock | flock | Same — unchanged | deploy-rs doesn't do local locking |
| Remote lock | SSH mkdir | Can be kept or dropped | deploy-rs serializes deploys per-node inherently |
| Rollback on failure | Print `nixos-rebuild switch --rollback` command | Automatic (magic rollback) | Major improvement |
| Rollback guidance | deploy.sh prints rollback command | Not needed for connectivity failures; still useful for container failures | Container issues don't trigger magic rollback |

## Security Considerations

1. **deploy-rs needs root SSH:** Already satisfied (`sshUser = "root"`, `PermitRootLogin = "prohibit-password"` in networking.nix).
2. **No new ports exposed:** deploy-rs uses the same SSH connection as the current deploy. No new firewall rules needed.
3. **tempPath security:** Canary files are created in `/tmp` by default. On a single-user server this is fine. The canary contains no secrets.
4. **deploy-rs.lib follows nixpkgs:** Using `inputs.nixpkgs.follows = "nixpkgs"` ensures deploy-rs builds against the same nixpkgs as the rest of the system.
5. **Flake input adds attack surface:** deploy-rs is a Rust binary pulled from GitHub. It runs on the local machine (not the server). The server only runs the activation script which is built from the flake. Risk is comparable to any other flake input.

## Open Questions

1. **Remote mode behavior with deploy-rs**
   - What we know: deploy-rs has `--remote-build` which builds on the target. The current deploy.sh has `--mode remote` which SSHes in and runs `nixos-rebuild` locally on the server.
   - What's unclear: Whether `--remote-build` behaves identically to SSH-in-and-build. Specifically, does the repo need to be on the server for `--remote-build`?
   - Recommendation: `--remote-build` should work since deploy-rs copies the build instructions. Verify during implementation. If it doesn't work, keep the SSH remote mode as a fallback path that calls `deploy` on the server directly.

2. **nix run vs. devShell for deploy-rs binary**
   - What we know: `nix run github:serokell/deploy-rs -- .#neurosys` works. Alternatively, a devShell can provide the `deploy` binary.
   - What's unclear: Whether `nix run github:serokell/deploy-rs` pins to flake.lock or fetches latest. Performance of `nix run` vs. cached devShell binary.
   - Recommendation: Use the flake input's package for consistency. In deploy.sh: `nix run .#deploy-rs -- .#neurosys` if the flake exposes the app, or `nix shell .#deploy-rs -c deploy .#neurosys` using the flake input's package. This ensures the binary version matches the lib version used for activation scripts. Validate during implementation.

3. **Remote lock necessity**
   - What we know: deploy-rs inherently serializes deploys to a single node. The current deploy.sh has both local flock and remote mkdir locking.
   - What's unclear: Whether deploy-rs's serialization replaces the remote lock, or if concurrent `deploy` invocations from different machines could conflict.
   - Recommendation: Keep both locks for defense in depth. The lock mechanism is cheap and already working.

## Sources

### Primary (HIGH confidence)
- [deploy-rs GitHub README](https://github.com/serokell/deploy-rs) — Complete feature documentation, flake configuration examples, CLI usage
- [deploy-rs flake.nix](https://github.com/serokell/deploy-rs/blob/master/flake.nix) — lib.activate.nixos implementation, deployChecks, input structure
- [deploy-rs src/cli.rs](https://github.com/serokell/deploy-rs/blob/master/src/cli.rs) — Complete CLI flag definitions with types and defaults
- [Serokell blog: Our New Deployment Tool deploy-rs](https://serokell.io/blog/deploy-rs) — Magic rollback mechanism internals, design rationale
- Codebase investigation: `/data/projects/neurosys/flake.nix` — Current flake inputs and nixosConfigurations
- Codebase investigation: `/data/projects/neurosys/scripts/deploy.sh` — Current deploy script structure (202 lines)
- Codebase investigation: `/data/projects/neurosys/modules/networking.nix` — SSH/firewall config, Tailscale setup
- Codebase investigation: `/data/projects/neurosys/ecosystem_research.md` — Decision P20-03: deploy-rs over Colmena

### Secondary (MEDIUM confidence)
- [deploy-rs Issue #86](https://github.com/serokell/deploy-rs/issues/86) — First-deploy rollback crash (no deploy-rs-activate in previous generation)
- [deploy-rs Issue #68](https://github.com/serokell/deploy-rs/issues/68) — Rollback not restarting all services (NixOS activation issue, not deploy-rs)
- [deploy-rs Issue #58](https://github.com/serokell/deploy-rs/issues/58) — Hanging after activation failure (fixed in PR #59)
- [NixOS Discourse: Using deploy-rs with existing configuration](https://discourse.nixos.org/t/using-deploy-rs-with-existing-configuration/31665) — Integration pattern, flake-utils pitfall
- [NixOS Discourse: Evaluating deployment tools](https://discourse.nixos.org/t/deployment-tools-evaluating-nixops-deploy-rs-and-vanilla-nix-rebuild/36388) — Tradeoffs vs. nixos-rebuild
- [paradigmatic.systems: Setting up deploy-rs](https://paradigmatic.systems/posts/setting-up-deploy-rs/) — Practical setup tutorial
- [ayats.org: NixOS on Hetzner with deploy-rs](https://ayats.org/blog/deploy-rs) — Cloud server deployment pattern

### Tertiary (LOW confidence)
- None. All claims verified with source code or official documentation.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — deploy-rs is the only tool with inotify rollback; verified via source code and official docs
- Architecture: HIGH — Flake integration pattern verified against multiple sources and existing codebase structure
- Pitfalls: HIGH — First-deploy crash (Issue #86) verified via GitHub issue; Tailscale timeout concern derived from mechanism analysis and networking module review
- CLI flags: HIGH — Extracted directly from Rust source code (src/cli.rs)

**Research date:** 2026-02-20
**Valid until:** 2026-03-20 (stable — deploy-rs is mature, low change velocity)
