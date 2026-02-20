# Phase 10: Parts Deployment Pipeline - Research

**Researched:** 2026-02-17
**Domain:** NixOS deployment, nix flake inputs, nixos-rebuild, deploy scripting, Docker health verification
**Confidence:** HIGH

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

#### Deployment trigger
- Manual CLI command only -- no CI/CD, no webhooks, no automation
- Deploy script lives at `scripts/deploy.sh` in the neurosys repo
- Supports two modes: local-push (build locally, push closure, switch remotely) and remote-self-deploy (SSH in, run on server)
- Every deploy is a full `nixos-rebuild switch` -- no partial/container-only deploys
- NixOS handles incrementality natively (only changed derivations rebuild, only affected containers restart)

#### Parts input tracking
- Parts is a git-based flake input tracking the `main` branch
- Deploy script automatically runs `nix flake update parts` before building
- Only the parts input is updated -- other inputs (nixpkgs, home-manager, sops-nix) stay pinned in flake.lock
- Other inputs are updated on a deliberate, separate schedule (not during parts deploys)
- No tags or releases -- main is the source of truth for parts

#### Verification & health
- After `nixos-rebuild switch`, deploy script checks Docker container status for all parts containers
- On failure: print which containers aren't running, exit non-zero
- On success: brief summary showing container statuses, parts input revision deployed, and deploy duration
- No application-level health checks (e.g., Telegram bot ping) -- container running = healthy enough

#### Rollback & recovery
- Use NixOS generation rollback -- no custom rollback tooling
- On deploy failure, the script's error output includes the rollback command to copy/paste (`nixos-rebuild switch --rollback`)
- Recovery flow: deploy fails -> script shows error + rollback command -> user runs rollback -> previous generation activates -> fix parts -> redeploy

### Deferred Ideas (OUT OF SCOPE)
- Automated deploys via CI/CD or git push hooks -- potential future phase if manual becomes tedious
- Application-level health checks (Telegram bot responds, API returns 200) -- could be added later
- Nixpkgs update schedule/automation -- separate concern from parts deployment
</user_constraints>

## Summary

This phase wraps the existing NixOS flake integration (from Phase 3.1) in an operational deploy script. The infrastructure is already built: parts exports `nixosModules.default`, neurosys imports it, Docker images are built via `dockerTools.buildLayeredImage`, and secrets flow through sops-nix. What's missing is the operational workflow -- a single command that updates the parts input, builds the system, pushes the closure to the server, activates it, and verifies that containers came up healthy.

The primary technical challenge is that the build machine is Ubuntu (not NixOS), so `nixos-rebuild` is not natively available. The established pattern from Phase 2 (DEPLOY-02) uses `nix copy --to ssh://` + remote `switch-to-configuration switch`. However, `nixos-rebuild` can be obtained on non-NixOS machines via `nix shell nixpkgs#nixos-rebuild`, which is the cleaner approach since it handles building, copying, and switching atomically. The second challenge is the flake input type: both `parts` and `claw-swap` currently use `path:` inputs (local filesystem paths), which must change to `github:` inputs for the deploy pipeline to work from the server or any other machine. The `path:` inputs only resolve on the local development machine where `/data/projects/parts` exists.

**Primary recommendation:** Change the parts and claw-swap flake inputs from `path:` to `github:`, use `nix shell nixpkgs#nixos-rebuild` for the deploy script, and implement the script as a straightforward bash script with `set -euo pipefail`, timing, and Docker health verification.

## Standard Stack

### Core

| Component | Version/Source | Purpose | Why Standard |
|-----------|---------------|---------|--------------|
| `nixos-rebuild` | NixOS/nixpkgs (via `nix shell`) | Build + deploy NixOS configs remotely | The official NixOS deployment tool; handles build, copy, switch atomically |
| `nix flake update` | Nix 2.33+ | Update single flake input | Built-in command; `nix flake update parts` updates only the parts lock entry |
| `docker` CLI | On target server | Health verification post-deploy | Already installed on acfs; `docker ps --filter` provides container status |
| `ssh` | OpenSSH | Remote command execution | Already configured; Tailscale SSH for secure access |
| bash | System shell | Deploy script | Universally available; `set -euo pipefail` for safety |

### Supporting

| Component | Version/Source | Purpose | When to Use |
|-----------|---------------|---------|-------------|
| `nix copy --to ssh://` | Nix 2.33+ | Push store paths to remote | Alternative to nixos-rebuild's built-in copy; already proven in Phase 2 |
| `nix build` | Nix 2.33+ | Build system closure locally | Used by nixos-rebuild internally; can be used standalone for dry-run builds |
| `jq` | On target server | Parse Docker inspect JSON | If container health checks need structured output parsing |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| `nixos-rebuild` via nix shell | `nix copy` + manual `switch-to-configuration` | More manual steps, no atomic build+switch; nixos-rebuild is cleaner |
| `nixos-rebuild` via nix shell | deploy-rs (serokell) | Adds a dependency for features we don't need (multi-host, rollback automation); overkill for single-host manual deploys |
| `nixos-rebuild` via nix shell | colmena | Same overkill concern; designed for fleets, not single-host |
| bash deploy script | Makefile | Makefiles are awkward for sequential deploy steps with error handling; bash is more natural |

## Architecture Patterns

### Deploy Script Structure

```
scripts/
  deploy.sh           # Main deploy script (both modes)
```

The script is a single file in the neurosys repo. No library dependencies, no framework.

### Pattern 1: Local-Push Mode (nixos-rebuild --target-host)

**What:** Build the NixOS system closure on the local machine, copy it to the server via SSH, and activate it remotely. This is the faster mode when the local machine has good bandwidth and CPU.

**When to use:** Default mode. Running from the development machine where the flake source lives.

**Command sequence:**
```bash
# 1. Update parts input to latest main
nix flake update parts

# 2. Build + copy + switch in one command
nix shell nixpkgs#nixos-rebuild -c \
  nixos-rebuild switch \
    --flake .#acfs \
    --target-host root@acfs \
    --build-host localhost
```

**Source:** [NixOS Wiki: nixos-rebuild](https://wiki.nixos.org/wiki/Nixos-rebuild), [Remote Deployments with nixos-rebuild](https://nixcademy.com/posts/nixos-rebuild-remote-deployment/)

**Key details:**
- `--build-host localhost` explicitly builds on the local machine (default, but makes intent clear)
- `--target-host root@acfs` deploys via SSH to the server
- Using `root@` avoids needing `--use-remote-sudo` (root can directly activate)
- The `acfs` hostname resolves via Tailscale (configured in SSH config or /etc/hosts)
- `nix shell nixpkgs#nixos-rebuild -c` provides nixos-rebuild on non-NixOS machines

### Pattern 2: Remote-Self-Deploy Mode (SSH + nixos-rebuild on server)

**What:** SSH into the server and run `nixos-rebuild switch` directly on the target. The server builds its own closure from the flake. This mode requires the flake source to be accessible from the server (hence the `github:` input requirement).

**When to use:** When the local machine has poor bandwidth or CPU, or when deploying from a machine that can't build x86_64-linux closures.

**Command sequence:**
```bash
# SSH into server and run remotely
ssh root@acfs "
  cd /data/projects/neurosys && \
  git pull && \
  nix flake update parts && \
  nixos-rebuild switch --flake .#acfs
"
```

**Key details:**
- Requires the neurosys repo to be cloned on the server (already done via repos.nix activation script)
- Requires `github:` input for parts (so the server can fetch parts from GitHub, not from a local path)
- Server has nixos-rebuild natively (it IS a NixOS machine)
- The `git pull` fetches the latest neurosys config from GitHub

### Pattern 3: Flake Input Update (parts only)

**What:** `nix flake update parts` updates only the parts input in flake.lock, leaving all other inputs (nixpkgs, home-manager, sops-nix, disko, llm-agents) at their current pinned versions.

**When to use:** Every deploy. The deploy script runs this automatically before building.

**Syntax:**
```bash
# Nix 2.33+ syntax: positional argument is the input name
nix flake update parts

# Alternative (older syntax, still works):
nix flake lock --update-input parts
```

**Source:** [Nix Reference Manual: nix flake update](https://nix.dev/manual/nix/2.25/command-ref/new-cli/nix3-flake-update)

### Pattern 4: Docker Health Check

**What:** After nixos-rebuild switch completes, verify that the expected Docker containers are running.

**When to use:** Post-deploy verification in the deploy script.

**Implementation:**
```bash
PARTS_CONTAINERS=("parts-tools" "parts-agent")

for container in "${PARTS_CONTAINERS[@]}"; do
  if ! ssh root@acfs "docker ps --filter name=^${container}$ --filter status=running -q" | grep -q .; then
    echo "FAIL: Container $container is not running"
    FAILED=1
  fi
done
```

**Key details:**
- NixOS oci-containers creates systemd services named `docker-<container-name>.service`
- Container names match what's declared in `virtualisation.oci-containers.containers.<name>`
- The parts containers are: `parts-tools`, `parts-agent`
- The claw-swap containers are: `claw-swap-db`, `claw-swap-app`, `claw-swap-caddy`
- A brief `sleep` or poll loop may be needed after switch, since containers start asynchronously via systemd

### Anti-Patterns to Avoid

- **Using `nix flake update` (no args) during deploys:** This updates ALL inputs, not just parts. Nixpkgs updates can break the build. Always use `nix flake update parts` to update only the parts input.
- **Using `path:` inputs for production:** `path:` resolves to a local filesystem path. The deploy script on the server cannot resolve `/data/projects/parts` to the same content as the dev machine. Use `github:` for deployable configs.
- **Building on the server without git pull:** If the neurosys repo on the server is stale, the NixOS config won't include recent changes. Always `git pull` before `nixos-rebuild` in remote-self-deploy mode.
- **Checking container health immediately after switch:** Containers may take a few seconds to start (especially if Docker images need loading). Add a brief delay or polling loop.
- **Committing flake.lock changes from the deploy script:** The `nix flake update parts` step modifies flake.lock. This is a deployment concern, not a source change. The script should update, build, and deploy, but NOT commit flake.lock automatically. The user decides when to commit the lock update.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Remote NixOS deployment | Custom `nix build` + `nix copy` + SSH `switch-to-configuration` | `nixos-rebuild switch --target-host` | nixos-rebuild handles the entire pipeline atomically; the manual approach has many edge cases (profile registration, GC root pinning) |
| NixOS generation rollback | Custom snapshot/restore logic | `nixos-rebuild switch --rollback` | NixOS generations are the rollback mechanism; every switch creates a new generation automatically |
| Flake input pinning | Manual flake.lock editing or `nix flake lock --override-input` | `nix flake update parts` | Built-in command does exactly what we need; no manual JSON editing |
| Container orchestration | Docker Compose or manual `docker run` | NixOS `virtualisation.oci-containers` | Already declared in parts/claw-swap modules; NixOS manages containers as systemd services |
| Deploy notification/logging | Custom logging framework | Script stdout + `SECONDS` bash variable | Bash captures duration natively; stdout is sufficient for a manual deploy tool |

**Key insight:** The entire deploy pipeline is just three operations chained together: (1) update flake input, (2) rebuild+switch, (3) verify containers. Everything else is error handling and user-friendly output.

## Common Pitfalls

### Pitfall 1: `path:` Inputs Don't Work From the Server

**What goes wrong:** The flake.nix has `parts.url = "path:/data/projects/parts"`. When nixos-rebuild runs on the acfs server, it tries to resolve `/data/projects/parts` on the server filesystem. The server's `/data/projects/parts` is a bare clone from the repos.nix activation script -- it may not match the development machine's copy, or may be outdated.
**Why it happens:** `path:` inputs resolve at evaluation time from the local filesystem. They are designed for local development, not production deployment.
**How to avoid:** Change to `github:dangirsh/personal-agent-runtime` (the actual GitHub repo name for parts). Note: the GitHub repo is `personal-agent-runtime`, not `parts`. The `nix flake update parts` command still uses the input *name* (`parts`), not the repo name.
**Warning signs:** Build fails with "path does not exist" or "narHash mismatch" when deploying from a different machine than the dev machine.

### Pitfall 2: claw-swap Also Uses `path:` Input

**What goes wrong:** Same issue as Pitfall 1 but for the claw-swap input. Both `path:` inputs must be changed to `github:` for the deploy pipeline to be portable.
**Why it happens:** Both inputs were set to `path:` during Phase 3.1/4 for local development convenience.
**How to avoid:** Change `claw-swap.url` to `github:dangirsh/claw-swap` in flake.nix.
**Warning signs:** Same as Pitfall 1.

### Pitfall 3: narHash Caching With `path:` Inputs

**What goes wrong:** After changing files in a `path:` input, `nix flake update parts` does not pick up the changes because Nix caches the narHash.
**Why it happens:** Nix's evaluation cache uses the narHash from flake.lock. For `path:` inputs, the narHash is computed from the directory contents at lock time. Changes to the directory don't invalidate the cache automatically.
**How to avoid:** This is a `path:`-specific problem. With `github:` inputs, `nix flake update parts` fetches the latest commit from GitHub, which always has a fresh hash. This pitfall goes away entirely once we switch to `github:` inputs.
**Warning signs:** Deployed system doesn't include recent parts changes despite running `nix flake update parts`. The DEPLOY-03 decision from Phase 2 documented this: `nix flake lock --recreate-lock-file` was the workaround for `path:` inputs.

### Pitfall 4: `nixos-rebuild` Not Available on Non-NixOS Build Host

**What goes wrong:** Running `nixos-rebuild switch --target-host ...` fails because `nixos-rebuild` is not in PATH on the Ubuntu build machine.
**Why it happens:** The build machine is Ubuntu 22.04 with Nix installed (not NixOS). `nixos-rebuild` is a NixOS-specific tool.
**How to avoid:** Use `nix shell nixpkgs#nixos-rebuild -c nixos-rebuild ...` to temporarily make nixos-rebuild available. The deploy script wraps this.
**Warning signs:** `command not found: nixos-rebuild`

### Pitfall 5: Containers Not Ready Immediately After Switch

**What goes wrong:** The health check runs immediately after `nixos-rebuild switch` returns, but containers are still starting. The check reports failure even though the deploy is fine.
**Why it happens:** `nixos-rebuild switch` activates the new system configuration (starts/restarts systemd services), but Docker container startup is asynchronous. Image loading, network creation, and container initialization take time.
**How to avoid:** Add a polling loop with timeout (e.g., check every 2 seconds for up to 30 seconds) rather than a single check.
**Warning signs:** Health check flakes -- sometimes passes, sometimes fails depending on how fast the containers start.

### Pitfall 6: Forgetting to Commit flake.lock After Deploy

**What goes wrong:** The deploy script runs `nix flake update parts`, which modifies `flake.lock`. If the user doesn't commit this change, the next `nix flake check` or build will use the old lock, and the deployed state diverges from the git state.
**Why it happens:** The deploy script intentionally does NOT auto-commit (per user decisions). But the user may forget.
**How to avoid:** The deploy script should print a reminder at the end: "flake.lock updated -- remember to commit if deploying from a new parts revision." The `git status` output in the summary helps too.
**Warning signs:** `nix flake check` locally produces different results than what's deployed. `git diff flake.lock` shows uncommitted changes.

## Code Examples

### Deploy Script Core Logic (local-push mode)

```bash
#!/usr/bin/env bash
# scripts/deploy.sh -- Deploy neurosys NixOS config to acfs
set -euo pipefail

FLAKE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TARGET="root@acfs"
SECONDS=0  # bash built-in timer

# --- Update parts input ---
echo "==> Updating parts flake input..."
nix flake update parts --flake "$FLAKE_DIR"
PARTS_REV=$(nix flake metadata "$FLAKE_DIR" --json | jq -r '.locks.nodes.parts.locked.rev // .locks.nodes.parts.locked.narHash')

# --- Build + deploy ---
echo "==> Building and deploying to $TARGET..."
nix shell nixpkgs#nixos-rebuild -c \
  nixos-rebuild switch \
    --flake "$FLAKE_DIR#acfs" \
    --target-host "$TARGET" \
    --build-host localhost

# --- Verify containers ---
echo "==> Verifying containers..."
CONTAINERS=("parts-tools" "parts-agent")
FAILED=0

for attempt in $(seq 1 15); do
  FAILED=0
  for c in "${CONTAINERS[@]}"; do
    if ! ssh "$TARGET" "docker ps --filter name=^${c}$ --filter status=running -q" 2>/dev/null | grep -q .; then
      FAILED=1
    fi
  done
  [ "$FAILED" -eq 0 ] && break
  sleep 2
done

# --- Report ---
DURATION=$SECONDS
if [ "$FAILED" -eq 0 ]; then
  echo ""
  echo "=== Deploy SUCCESS ==="
  echo "Parts revision: $PARTS_REV"
  echo "Duration: $((DURATION / 60))m $((DURATION % 60))s"
  ssh "$TARGET" "docker ps --filter name=parts --format 'table {{.Names}}\t{{.Status}}'"
else
  echo ""
  echo "=== Deploy FAILED ==="
  echo "Some containers are not running after 30s:"
  ssh "$TARGET" "docker ps -a --filter name=parts --format 'table {{.Names}}\t{{.Status}}'"
  echo ""
  echo "To rollback: ssh $TARGET nixos-rebuild switch --rollback"
  exit 1
fi
```

### Remote-Self-Deploy Mode

```bash
# Remote mode: SSH in, pull, update, rebuild on the server
ssh "$TARGET" bash -s <<'REMOTE'
  set -euo pipefail
  cd /data/projects/neurosys
  git pull --ff-only
  nix flake update parts
  nixos-rebuild switch --flake .#acfs
REMOTE
```

### Flake Input Change (path: to github:)

```nix
# BEFORE (local development only):
parts = {
  url = "path:/data/projects/parts";
  inputs.nixpkgs.follows = "nixpkgs";
  inputs.sops-nix.follows = "sops-nix";
};
claw-swap = {
  url = "path:/data/projects/claw-swap";
  inputs.nixpkgs.follows = "nixpkgs";
  inputs.sops-nix.follows = "sops-nix";
};

# AFTER (deployable from anywhere):
parts = {
  url = "github:dangirsh/personal-agent-runtime";  # NOTE: repo name differs from input name
  inputs.nixpkgs.follows = "nixpkgs";
  inputs.sops-nix.follows = "sops-nix";
};
claw-swap = {
  url = "github:dangirsh/claw-swap";
  inputs.nixpkgs.follows = "nixpkgs";
  inputs.sops-nix.follows = "sops-nix";
};
```

### Extracting Parts Revision From flake.lock

```bash
# After `nix flake update parts`, extract the locked revision
nix flake metadata --json | jq -r '.locks.nodes.parts.locked.rev'
# Output: e70d872...  (git commit hash)
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `path:` flake inputs | `github:` flake inputs | This phase | Deploy script works from any machine, not just the dev machine with local clones |
| `nix copy --to ssh://` + manual switch | `nixos-rebuild switch --target-host` | This phase | Atomic build+copy+switch; profile registration handled automatically |
| Manual `nix flake lock --recreate-lock-file` | `nix flake update parts` with `github:` input | This phase | narHash caching issue goes away entirely with `github:` inputs |
| No deploy workflow | `scripts/deploy.sh` | This phase | Single-command deploy with verification and rollback guidance |

**Deprecated/outdated:**
- `nix flake lock --update-input <name>`: Still works but `nix flake update <name>` is the canonical syntax in Nix 2.33+
- `path:` flake inputs for production: Only useful for local development; `github:` is required for portable deployment

## Current System State (Codebase Investigation)

### Flake Inputs (as of 2026-02-17)

| Input | Current URL | Locked At | Needs Change |
|-------|-------------|-----------|--------------|
| parts | `path:/data/projects/parts` | narHash (local) | YES -> `github:dangirsh/personal-agent-runtime` |
| claw-swap | `path:/data/projects/claw-swap` | narHash (local) | YES -> `github:dangirsh/claw-swap` |
| nixpkgs | `github:NixOS/nixpkgs/nixos-25.11` | 6c5e707 | No |
| home-manager | `github:nix-community/home-manager/release-25.11` | 0d782ee | No |
| sops-nix | `github:Mic92/sops-nix` | 8b89f44 | No |
| disko | `github:nix-community/disko` | 71a3fc9 | No |
| llm-agents | `github:numtide/llm-agents.nix` | b73c33c | No |

### GitHub Repo Name Mapping

| Flake Input Name | GitHub Repo | Notes |
|------------------|-------------|-------|
| `parts` | `dangirsh/personal-agent-runtime` | Repo name does NOT match input name |
| `claw-swap` | `dangirsh/claw-swap` | Matches |

### Build Machine

- **OS:** Ubuntu (Linux 6.17.0-8-generic), NOT NixOS
- **Nix:** Installed (Nix 2.33.1)
- **nixos-rebuild:** NOT available natively; must use `nix shell nixpkgs#nixos-rebuild`
- **Decision DEPLOY-02** (Phase 2): Established `nix copy --to ssh://` + remote `switch-to-configuration switch` pattern; this phase upgrades to `nixos-rebuild` via nix shell

### Target Server (acfs)

- **IP:** 62.171.134.33 (Contabo VPS)
- **OS:** NixOS 25.11
- **Access:** SSH via Tailscale (port 22 not on public interface; `root@acfs` via tailnet)
- **nixos-rebuild:** Available natively (NixOS)
- **Docker:** Running with `--iptables=false`, NixOS owns the firewall
- **Containers declared:** parts-tools, parts-agent (from parts module), claw-swap-db, claw-swap-app, claw-swap-caddy (from claw-swap module)

### Parts Module Architecture (already built, from Phase 3.1)

The parts NixOS module (`/data/projects/parts/nix/module.nix`) declares:
- 10 sops.secrets with per-secret sopsFile pointing to `self + "/secrets/parts.yaml"`
- 2 sops.templates (parts-tools-env, parts-agent-env) for container env files
- 2 Docker networks (agent_net internal, tools_net external) as systemd oneshot services
- 2 oci-containers (parts-tools, parts-agent) with imageFile from dockerTools.buildLayeredImage
- Systemd ordering (containers after networks)
- tmpfiles rules for host directories (/var/lib/parts/*)

This module is already imported in neurosys flake.nix as `inputs.parts.nixosModules.default`.

## Open Questions

1. **SSH host alias for `acfs`**
   - What we know: The server is at 62.171.134.33 and on the Tailscale network. SSH is only accessible via Tailscale (not public).
   - What's unclear: Whether `root@acfs` resolves via Tailscale MagicDNS or requires an explicit SSH config entry. The deploy script needs a reliable hostname.
   - Recommendation: Use the Tailscale hostname `acfs` if MagicDNS is configured; otherwise, add an SSH config entry. Check `tailscale status` on the dev machine to confirm the hostname.

2. **flake.lock commit policy**
   - What we know: The deploy script updates flake.lock (via `nix flake update parts`) but does NOT auto-commit.
   - What's unclear: Should the deploy script commit flake.lock after a successful deploy? The CONTEXT.md doesn't specify.
   - Recommendation: Do NOT auto-commit. Print a reminder instead. The user can commit when ready. This avoids dirty working tree issues and keeps the deploy script read-only with respect to git history.

3. **claw-swap input change scope**
   - What we know: The claw-swap input also uses `path:` and needs to change to `github:` for the same reasons as parts.
   - What's unclear: Whether the claw-swap input change is in scope for this phase, or should be a separate quick task.
   - Recommendation: Change both inputs in the same plan task, since the deploy script does a full `nixos-rebuild switch` that includes claw-swap. Having one input on `path:` and another on `github:` would be inconsistent and confusing.

## Sources

### Primary (HIGH confidence)
- **Codebase investigation:** `/data/projects/neurosys/flake.nix` -- current flake inputs, module imports
- **Codebase investigation:** `/data/projects/parts/nix/module.nix` -- parts NixOS module structure (200 lines)
- **Codebase investigation:** `/data/projects/parts/flake.nix` -- parts flake outputs
- **Codebase investigation:** `/data/projects/neurosys/flake.lock` -- current input lock state
- **Codebase investigation:** `/data/projects/neurosys/.planning/phases/02-bootable-base-system/02-02-SUMMARY.md` -- DEPLOY-02, DEPLOY-03 decisions
- **Codebase investigation:** Parts repo remote = `github:dangirsh/personal-agent-runtime` (NOT `dangirsh/parts`)
- **Codebase investigation:** Build machine = Ubuntu with Nix 2.33.1, no nixos-rebuild

### Secondary (MEDIUM confidence)
- [NixOS Wiki: nixos-rebuild](https://wiki.nixos.org/wiki/Nixos-rebuild) -- remote deployment with --target-host
- [Nix Reference Manual: nix flake update](https://nix.dev/manual/nix/2.25/command-ref/new-cli/nix3-flake-update) -- single input update syntax
- [Remote Deployments with nixos-rebuild](https://nixcademy.com/posts/nixos-rebuild-remote-deployment/) -- best practices for SSH deploy
- [NixOS & Flakes Book: Remote Deployment](https://nixos-and-flakes.thiscute.world/best-practices/remote-deployment) -- build-host/target-host patterns
- [NixOS Discourse: Running nixos-rebuild on non-NixOS](https://discourse.nixos.org/t/running-nixos-rebuild-switch-locally-on-a-non-nix-computer/38723) -- `nix shell nixpkgs#nixos-rebuild` pattern

### Tertiary (LOW confidence)
- None. All findings verified against codebase and official documentation.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- all tools are built-in Nix/NixOS commands; no external dependencies
- Architecture: HIGH -- deploy script is straightforward bash; patterns verified against codebase
- Pitfalls: HIGH -- most pitfalls discovered from actual project history (DEPLOY-02, DEPLOY-03, narHash issues)

**Research date:** 2026-02-17
**Valid until:** 2026-03-17 (stable -- NixOS deployment patterns don't change frequently)
