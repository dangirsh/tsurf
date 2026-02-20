# Phase 4: Docker Services - Research

**Researched:** 2026-02-16
**Domain:** NixOS cross-flake Docker service modules, container hardening, Caddy reverse proxy, PostgreSQL containers
**Confidence:** HIGH

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

#### claw-swap deployment pattern
- claw-swap repo exports a NixOS module via its own flake (same pattern as parts)
- Agent-neurosys imports it as a flake input
- Docker images built with Nix dockerTools (not pulled from registry) -- reproducible, same as parts
- PostgreSQL stays as a Docker container (not NixOS-native) -- keep current approach
- Service-specific config (containers, networks, secrets) lives in the claw-swap repo, not neurosys

#### Container resource limits
- Generous headroom: 512MB for lightweight containers, 2GB for Java/heavy ones (47GB RAM VPS)
- Both memory AND CPU limits set per container
- Restart policy: on-failure with max retries (prevents crash loops, stays down after repeated failures for investigation)

#### Ollama
- DROPPED from Phase 4 -- only known consumer (claude-memory-daemon) is out of scope for v1
- Can be added later as a simple NixOS module if a use case appears (CASS indexer in Phase 6, experiments)

#### grok-mcp
- DROPPED from Phase 4 -- not needed

### Claude's Discretion
- Caddy TLS/domain config ownership (claw-swap repo vs neurosys)
- Exact CPU/memory values per container -- start generous, document in config
- Container restart max retry count

### Deferred Ideas (OUT OF SCOPE)
- Ollama AI inference service -- add when a consumer exists (Phase 6 CASS indexer may need it)
- grok-mcp -- add back if needed in the future
- NixOS-native PostgreSQL -- could simplify backups in Phase 7, but keep Docker for now
</user_constraints>

## Summary

Phase 4 declares and runs the claw-swap production Docker stack on the acfs VPS, following the exact cross-flake module pattern established in Phase 3.1 with parts. The claw-swap repo gets a `flake.nix` that exports `nixosModules.default`, declaring three containers (Caddy, claw-swap app, PostgreSQL 16), one Docker network (`claw-swap-net`), and sops-nix secrets. Agent-neurosys imports it as a flake input alongside the existing parts module.

The claw-swap app is a Hono (Node.js 22) TypeScript API server with Drizzle ORM talking to PostgreSQL. It is currently deployed manually via Docker on the acfs server with a Caddy reverse proxy handling TLS for `claw-swap.com`. This phase converts that manual setup into fully declarative Nix configuration. The app's Dockerfile is a straightforward two-stage Node.js build with no workspace complexity (unlike parts) -- making the `buildNpmPackage` + `dockerTools.buildLayeredImage` conversion simpler.

The primary new challenge compared to Phase 3.1 is container security hardening. Every container gets `--read-only` rootfs, `--cap-drop=ALL`, `--security-opt=no-new-privileges`, and resource limits via `extraOptions` in `oci-containers`. PostgreSQL additionally needs `--tmpfs` for its runtime directories and `NET_BIND_SERVICE` capability for port binding. Caddy needs `NET_BIND_SERVICE` for ports 80/443 and persistent volumes for TLS certificates and configuration.

**Primary recommendation:** Follow the parts cross-flake pattern exactly. Build the claw-swap app image with `dockerTools.buildLayeredImage`. Use the official PostgreSQL and Caddy Docker images from `dockerTools.pullImage` (not Nix-built) since they have complex init scripts and plugin systems that are impractical to replicate in Nix. Apply hardening via `extraOptions` on every container.

## Standard Stack

### Core

| Component | Version/Source | Purpose | Why Standard |
|-----------|---------------|---------|--------------|
| NixOS flake `nixosModules` output | Built into Nix flakes | Export NixOS module from claw-swap | Same pattern as parts; proven in Phase 3.1 |
| `dockerTools.buildLayeredImage` | nixpkgs 25.11 | Build claw-swap app image | Reproducible, multi-layer for caching; proven in parts-agent/parts-tools |
| `dockerTools.pullImage` | nixpkgs 25.11 | Pull PostgreSQL 16 + Caddy images | These images have complex init scripts (PostgreSQL) and plugin systems (Caddy) that are impractical to rebuild from scratch in Nix |
| `buildNpmPackage` | nixpkgs 25.11 | Package claw-swap Node.js app | Standard nixpkgs builder; claw-swap is simpler than parts (single package, no workspaces) |
| `virtualisation.oci-containers` | NixOS module | Run containers as systemd services | Same as parts; `imageFile` for local images, `image` for pulled images |
| `sops-nix` | Mic92/sops-nix | Secrets management | Same pattern as parts; `sops.templates` for env files, per-secret `sopsFile` overrides |

### Supporting

| Component | Version/Source | Purpose | When to Use |
|-----------|---------------|---------|-------------|
| PostgreSQL 16 Docker image | `docker.io/postgres:16-alpine` | Production database | Pulled via `dockerTools.pullImage`; includes initdb, locale support, extension loading |
| Caddy Docker image | `docker.io/caddy:2-alpine` | TLS termination + reverse proxy | Pulled via `dockerTools.pullImage`; automatic HTTPS, Caddyfile config |
| `pkgs.writeText` | nixpkgs | Generate Caddyfile from Nix | Render Caddyfile as a Nix store path, bind-mount into Caddy container |

### Alternatives Considered

| Instead of | Could Use | Tradeoff | Decision |
|------------|-----------|----------|----------|
| `dockerTools.pullImage` for Caddy | `dockerTools.buildLayeredImage` with `pkgs.caddy` | Nix-built is reproducible but loses Caddy's plugin system and official image optimizations. Caddy itself is a static Go binary, so Nix build is feasible but adds complexity for no gain since we just need a reverse proxy | **Use pullImage** -- Caddy is a stable, well-maintained image with no secrets in the image itself |
| `dockerTools.pullImage` for PostgreSQL | `dockerTools.buildLayeredImage` with `pkgs.postgresql_16` | PostgreSQL's Docker entrypoint handles initdb, locale, extensions, pg_hba.conf -- replicating in Nix is significant work for a stateful service. The official image is battle-tested | **Use pullImage** -- PostgreSQL init complexity is not worth replicating |
| `dockerTools.pullImage` for claw-swap app | `dockerTools.buildLayeredImage` | App code changes frequently; Nix-built image is reproducible and doesn't need registry access | **Use buildLayeredImage** -- same as parts, locked decision |

## Architecture Patterns

### Recommended claw-swap Repo Structure (additions to existing)

```
claw-swap/
  flake.nix              # NEW: nixosModules.default + packages outputs
  flake.lock             # NEW: pins nixpkgs, sops-nix
  nix/                   # NEW: Nix build expressions
    claw-swap-app.nix    #   dockerTools image for the Hono app
    module.nix           #   NixOS module (containers, networks, secrets)
  secrets/               # NEW: sops-encrypted secrets
    claw-swap.yaml       #   Single encrypted YAML with all secrets
  .sops.yaml             # NEW: creation rules referencing acfs host key
  deploy/                # EXISTING: Caddyfile moves to nix/module.nix as pkgs.writeText
    secrets/             #   SUPERSEDED by sops-nix (can be removed after migration)
  # KEPT: src/, package.json, Dockerfile (kept for reference/local dev)
```

### Pattern 1: Cross-Flake Module (Same as Parts)

**What:** claw-swap exports a NixOS module that neurosys imports as a flake input.
**When to use:** Always -- this is a locked decision.

claw-swap `flake.nix`:
```nix
{
  description = "Claw Swap - Agent-first bulletin board";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, sops-nix, ... }:
  let
    system = "x86_64-linux";
    pkgs = nixpkgs.legacyPackages.${system};
  in {
    # NixOS module for neurosys to import
    nixosModules.default = import ./nix/module.nix { inherit self sops-nix; };

    # Standalone image package for testing
    packages.${system}.claw-swap-app = pkgs.callPackage ./nix/claw-swap-app.nix { src = self; };
  };
}
```

Agent-neurosys `flake.nix` addition:
```nix
{
  inputs = {
    # ... existing inputs ...
    claw-swap = {
      url = "path:/data/projects/claw-swap";  # path: for local dev; github: for production
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.sops-nix.follows = "sops-nix";
    };
  };

  outputs = { self, nixpkgs, home-manager, sops-nix, disko, parts, claw-swap, ... } @ inputs: {
    nixosConfigurations.acfs = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = { inherit inputs; };
      modules = [
        # ... existing modules ...
        inputs.parts.nixosModules.default
        inputs.claw-swap.nixosModules.default    # NEW
      ];
    };
  };
}
```

### Pattern 2: Container Hardening via extraOptions

**What:** Apply security hardening to every container using `extraOptions`.
**When to use:** Every container declaration in Phase 4.

```nix
# Hardening template -- apply to every container
virtualisation.oci-containers.containers.<name> = {
  # ... image, environment, volumes, etc. ...
  extraOptions = [
    # Security hardening
    "--read-only"
    "--tmpfs=/tmp:rw,noexec,nosuid"
    "--cap-drop=ALL"
    "--security-opt=no-new-privileges"
    # Resource limits
    "--memory=512m"
    "--cpus=1.0"
    # Restart policy
    "--restart=on-failure:5"
    # Network
    "--network=claw-swap-net"
  ];
};
```

Source: Phase 9 research (09-RESEARCH.md), OWASP Docker Security Cheat Sheet, Docker official docs.

### Pattern 3: Pulled Images (PostgreSQL, Caddy)

**What:** Use `dockerTools.pullImage` for PostgreSQL and Caddy instead of building from scratch.
**When to use:** For complex upstream images with init scripts or plugin systems.

```nix
# In nix/module.nix
let
  postgresImage = pkgs.dockerTools.pullImage {
    imageName = "postgres";
    imageDigest = "sha256:PLACEHOLDER";  # pin to specific digest for reproducibility
    sha256 = "sha256-PLACEHOLDER";       # Nix content hash
    finalImageTag = "16-alpine";
    finalImageName = "postgres";
  };

  caddyImage = pkgs.dockerTools.pullImage {
    imageName = "caddy";
    imageDigest = "sha256:PLACEHOLDER";
    sha256 = "sha256-PLACEHOLDER";
    finalImageTag = "2-alpine";
    finalImageName = "caddy";
  };
in
{
  virtualisation.oci-containers.containers.claw-swap-db = {
    image = "postgres:16-alpine";
    imageFile = postgresImage;
    # ...
  };

  virtualisation.oci-containers.containers.claw-swap-caddy = {
    image = "caddy:2-alpine";
    imageFile = caddyImage;
    # ...
  };
}
```

### Pattern 4: Caddyfile via pkgs.writeText

**What:** Generate the Caddyfile as a Nix store path and bind-mount it.
**When to use:** For the Caddy container configuration.

```nix
let
  caddyfile = pkgs.writeText "Caddyfile" ''
    claw-swap.com {
      reverse_proxy claw-swap-app:3000
    }
  '';
in
{
  virtualisation.oci-containers.containers.claw-swap-caddy = {
    # ...
    volumes = [
      "${caddyfile}:/etc/caddy/Caddyfile:ro"
      "/var/lib/claw-swap/caddy-data:/data"       # TLS certs persist here
      "/var/lib/claw-swap/caddy-config:/config"    # Caddy config cache
    ];
  };
}
```

### Pattern 5: PostgreSQL with Data Volume and Init

**What:** PostgreSQL container with persistent data volume and environment-based initialization.
**When to use:** For the claw-swap database container.

```nix
virtualisation.oci-containers.containers.claw-swap-db = {
  image = "postgres:16-alpine";
  imageFile = postgresImage;

  environment = {
    POSTGRES_DB = "claw_swap";
    POSTGRES_USER = "claw";
  };

  environmentFiles = [
    config.sops.templates."claw-swap-db-env".path
  ];

  volumes = [
    "/var/lib/claw-swap/pgdata:/var/lib/postgresql/data"
  ];

  extraOptions = [
    "--read-only"
    "--tmpfs=/tmp:rw,noexec,nosuid"
    "--tmpfs=/run/postgresql:rw,noexec,nosuid"   # PostgreSQL needs this for socket/pid
    "--cap-drop=ALL"
    "--cap-add=NET_BIND_SERVICE"                  # PostgreSQL binds to port 5432
    "--security-opt=no-new-privileges"
    "--memory=512m"
    "--cpus=1.0"
    "--restart=on-failure:5"
    "--network=claw-swap-net"
    "--shm-size=128m"                             # PostgreSQL shared memory for performance
  ];
};

# PostgreSQL password via sops template
sops.templates."claw-swap-db-env" = {
  content = ''
    POSTGRES_PASSWORD=${config.sops.placeholder."claw-swap-db-password"}
  '';
};
```

### Anti-Patterns to Avoid

- **Setting `sops.defaultSopsFile` in the claw-swap module:** Conflicts with neurosys' own default. Use per-secret `sopsFile` overrides (same lesson as parts).
- **Importing sops-nix module in claw-swap:** Agent-neurosys already imports it. Claw-swap module just declares `sops.secrets` entries.
- **Using `buildLayeredImage` for PostgreSQL/Caddy:** These images have complex init logic. Use `pullImage` with digest pinning.
- **Hardcoding secrets in environment:** Use `sops.templates` + `environmentFiles`, never plaintext in Nix config.
- **Declaring `virtualisation.docker.enable` in claw-swap module:** Docker engine is system-level config owned by neurosys.
- **Forgetting `--tmpfs` with `--read-only`:** PostgreSQL and Node.js apps need writable /tmp. PostgreSQL also needs /run/postgresql.
- **Missing `--shm-size` for PostgreSQL:** Default Docker shared memory (64MB) causes PostgreSQL performance issues and crashes under load.

## Claude's Discretion Recommendations

### 1. Caddy TLS/Domain Config Ownership

**Recommendation: Caddy container and Caddyfile live in the claw-swap repo's NixOS module.**

Rationale:
- The user decision says "service-specific config lives in the claw-swap repo, not neurosys"
- Caddy is service-specific -- it reverse-proxies to the claw-swap app and terminates TLS for `claw-swap.com`
- The Caddyfile is tightly coupled to the app's port and routing structure
- If another service needs its own Caddy/reverse proxy, it would declare its own
- Agent-neurosys only opens ports 80/443 on the firewall (already done in `networking.nix`)

The Caddyfile is generated via `pkgs.writeText` inside the claw-swap module and bind-mounted into the Caddy container. TLS certificate persistence uses a host volume at `/var/lib/claw-swap/caddy-data`.

Caddy uses HTTP-01 challenge for Let's Encrypt certificates. This works because ports 80 and 443 are already open on the public interface (confirmed in `networking.nix`). No DNS challenge or Cloudflare API token is needed. The existing `deploy/secrets/cloudflare.key` was for a previous setup and is no longer required.

**Confidence:** HIGH -- follows the user's service-ownership decision and the HTTP-01 challenge is the simplest, most standard approach.

### 2. Exact CPU/Memory Values Per Container

**Recommendation:**

| Container | Memory | CPU | Rationale |
|-----------|--------|-----|-----------|
| claw-swap-app | 512MB | 1.0 | Node.js Hono server; lightweight API, no heavy computation |
| claw-swap-db | 512MB | 1.0 | PostgreSQL 16; moderate queries, full-text search. `--shm-size=128m` for shared buffers |
| claw-swap-caddy | 256MB | 0.5 | Static reverse proxy; minimal resource usage even under load |

Total for claw-swap stack: ~1.3GB memory, 2.5 CPUs. On a 47GB RAM, 10-core VPS, this is well within headroom.

These are starting values documented in the Nix config with `# @decision` annotations. Adjust based on monitoring.

**Confidence:** HIGH -- conservative starting points with significant headroom on a 47GB RAM VPS.

### 3. Container Restart Max Retry Count

**Recommendation: `--restart=on-failure:5`**

Rationale:
- 5 retries gives enough chances for transient failures (network blip, temporary resource contention)
- After 5 failures, the container stays down for investigation rather than crash-looping
- Docker's `on-failure` policy only restarts on non-zero exit codes (clean shutdown stays down)
- Combined with systemd service management from oci-containers, `systemctl status docker-claw-swap-app` shows the failure
- `journalctl -u docker-claw-swap-app` shows crash logs

If a container consistently fails 5 times, the issue needs human investigation, not more restarts.

**Confidence:** HIGH -- standard practice for production containers. Kubernetes defaults to 5-minute backoff; Docker's simpler model benefits from a hard cap.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| PostgreSQL Docker image | Nix-built PostgreSQL image | `dockerTools.pullImage` of `postgres:16-alpine` | initdb, locale, pg_hba.conf, extension loading are complex; official image is battle-tested |
| Caddy Docker image | Nix-built Caddy image | `dockerTools.pullImage` of `caddy:2-alpine` | Caddy is a static Go binary but official image includes proper entrypoint and config handling |
| TLS certificate management | Manual cert scripts | Caddy automatic HTTPS | Caddy handles Let's Encrypt certificates automatically via HTTP-01 challenge |
| Database migrations at deploy | Custom migration scripts | `drizzle-kit migrate` run manually or via systemd oneshot | Drizzle Kit generates SQL files already in the repo; run against the container after start |
| Secret injection into containers | Custom shell scripts | `sops.templates` + `environmentFiles` | Atomic secret injection, restart on change; proven in parts |
| Docker network creation | Activation scripts | systemd oneshot services | Proper ordering, logging, `systemctl` management; proven in parts |
| Container-to-container DNS | Custom /etc/hosts | Docker network DNS | Containers on `claw-swap-net` resolve each other by container name |

**Key insight:** The entire claw-swap deployment is expressible as Nix declarations. The only imperative steps are (1) initial `sops` secret encryption and (2) database migration after first deploy. Both are one-time operations.

## Common Pitfalls

### Pitfall 1: sharp Native Addon in buildNpmPackage

**What goes wrong:** `npm install` for claw-swap includes `sharp` (image processing), which downloads prebuilt libvips binaries. This fails in the Nix sandbox.
**Why it happens:** `sharp` v0.34.5 is listed in `package.json` dependencies. During `npm install`, sharp's install script downloads platform-specific prebuilt binaries from GitHub.
**How to avoid:** Two options:
1. **If sharp is unused** (current state -- grep finds zero imports in `src/`): Remove it from `package.json` before the Nix build. This is the simplest fix.
2. **If sharp is needed later**: Use `npmFlags = [ "--ignore-scripts" ]` (same pattern as parts-tools with signal-sdk), then in `buildPhase` run `npm rebuild sharp` with `pkgs.vips` available in `nativeBuildInputs`. Alternatively, set `SHARP_IGNORE_GLOBAL_LIBVIPS=1` and provide `pkgs.vips` in the build environment.
**Warning signs:** Build failure with "sharp: Installation error" or "Could not load the 'sharp' module" at runtime.
**Recommendation:** Verify with user whether sharp is needed. If not, recommend removing from `package.json` to avoid build complexity. If needed, the `--ignore-scripts` + `npm rebuild` pattern from parts is proven.

### Pitfall 2: PostgreSQL --read-only Without tmpfs

**What goes wrong:** PostgreSQL container crashes immediately with permission errors when root filesystem is read-only.
**Why it happens:** PostgreSQL needs to write to `/tmp`, `/run/postgresql` (for Unix socket and PID file), and `/var/lib/postgresql/data` (the data directory, which is a volume).
**How to avoid:** Always pair `--read-only` with `--tmpfs=/tmp:rw,noexec,nosuid --tmpfs=/run/postgresql:rw,noexec,nosuid`. The data directory is already a bind-mounted volume, so it's writable regardless.
**Warning signs:** Container exits immediately with "could not create lock file" or "Permission denied" errors in `journalctl -u docker-claw-swap-db`.

### Pitfall 3: PostgreSQL cap-drop ALL Without cap-add

**What goes wrong:** PostgreSQL container crashes because it cannot bind to port 5432.
**Why it happens:** `--cap-drop=ALL` drops all Linux capabilities, including `NET_BIND_SERVICE` needed for socket binding. While port 5432 is above 1024 (so technically doesn't need `NET_BIND_SERVICE`), PostgreSQL's initdb and startup scripts may need additional capabilities like `CHOWN`, `SETUID`, `SETGID`, `FOWNER`, and `DAC_OVERRIDE` for file ownership operations.
**How to avoid:** For PostgreSQL, use `--cap-drop=ALL` followed by `--cap-add=CHOWN --cap-add=SETUID --cap-add=SETGID --cap-add=FOWNER --cap-add=DAC_OVERRIDE`. The official PostgreSQL Docker image runs as root initially (for initdb) then drops to the `postgres` user. These capabilities are needed for that transition.
**Warning signs:** Container fails during initdb with permission errors.

### Pitfall 4: Caddy Certificate Persistence

**What goes wrong:** Caddy re-issues TLS certificates on every container restart, hitting Let's Encrypt rate limits.
**Why it happens:** Caddy stores certificates in `/data` by default. Without a persistent volume, every container restart loses the certificates.
**How to avoid:** Always mount `/var/lib/claw-swap/caddy-data:/data` as a persistent volume. Also mount `/var/lib/claw-swap/caddy-config:/config` for Caddy's auto-saved configuration.
**Warning signs:** Let's Encrypt rate limit errors in Caddy logs (`journalctl -u docker-claw-swap-caddy`). Let's Encrypt limits 5 duplicate certificates per week.

### Pitfall 5: Docker Network Must Exist Before Containers Start

**What goes wrong:** Container fails to start with "network claw-swap-net not found".
**Why it happens:** systemd starts container services before the network-creation oneshot service.
**How to avoid:** Declare explicit `after` and `requires` dependencies on the network service in container systemd units (same pattern as parts).
**Warning signs:** "network claw-swap-net not found" in container service logs.

### Pitfall 6: pullImage Hash Must Be Updated When Image Changes

**What goes wrong:** `nix flake check` or `nixos-rebuild` fails with hash mismatch after upstream image update.
**Why it happens:** `dockerTools.pullImage` uses content-addressed hashes. When the upstream tag (e.g., `16-alpine`) points to a new digest, the Nix hash becomes invalid.
**How to avoid:** Pin to a specific `imageDigest` (SHA256 of the image manifest). Update both `imageDigest` and `sha256` when upgrading. Use `nix-prefetch-docker` to compute hashes:
```bash
nix-prefetch-docker --image-name postgres --image-tag 16-alpine --quiet
```
**Warning signs:** Hash mismatch error during build.

### Pitfall 7: Database Migration Timing

**What goes wrong:** App container starts before database is ready, causing connection errors.
**Why it happens:** oci-containers `dependsOn` only ensures the container is started, not that the service inside is healthy.
**How to avoid:** Two approaches:
1. The app has a `/health` endpoint that checks DB connectivity. Use Docker `HEALTHCHECK` or retry logic in the app.
2. Run database migrations as a separate systemd oneshot service after the PostgreSQL container is healthy, before the app container starts.
**Recommendation:** The app already handles DB connection failures gracefully (connection pool with retries). The `dependsOn` ordering is sufficient for startup. Migrations are a one-time manual step after first deploy.

### Pitfall 8: sops-nix Double Module Import (Same as Parts)

**What goes wrong:** NixOS evaluation fails with "option 'sops' already declared".
**Why it happens:** Both neurosys and claw-swap try to import `sops-nix.nixosModules.sops`.
**How to avoid:** Only neurosys imports the sops-nix module. The claw-swap module just declares `sops.secrets` entries. Use `inputs.sops-nix.follows = "sops-nix"` to share the same instance.

## Code Examples

### Complete claw-swap App Image (nix/claw-swap-app.nix)

```nix
# nix/claw-swap-app.nix -- Docker image for claw-swap Hono API server
#
# @decision: Use buildNpmPackage directly (no workspace complexity, single package.json).
# @decision: sharp may need --ignore-scripts if present in dependencies.
{ pkgs, src, ... }:

let
  nodejs = pkgs.nodejs_22;

  claw-swap-app = pkgs.buildNpmPackage {
    pname = "claw-swap";
    version = "0.1.0";
    inherit src;

    npmDepsHash = "sha256-PLACEHOLDER";  # compute with: prefetch-npm-deps package-lock.json
    inherit nodejs;

    # sharp downloads prebuilt binaries in postinstall -- blocked in Nix sandbox
    # If sharp is removed from dependencies, this flag can be removed too
    npmFlags = [ "--ignore-scripts" ];
    makeCacheWritable = true;

    # Build: TypeScript compilation
    npmBuildScript = "build";

    installPhase = ''
      runHook preInstall

      mkdir -p $out/lib/claw-swap
      cp -r dist $out/lib/claw-swap/dist
      cp -r node_modules $out/lib/claw-swap/node_modules
      cp package.json $out/lib/claw-swap/
      # Static assets served by the app
      cp -r public $out/lib/claw-swap/public
      # Drizzle migrations for manual apply
      cp -r drizzle $out/lib/claw-swap/drizzle 2>/dev/null || true

      runHook postInstall
    '';
  };

in
pkgs.dockerTools.buildLayeredImage {
  name = "claw-swap";
  tag = "latest";

  contents = with pkgs.dockerTools; [
    caCertificates
    fakeNss
  ];

  config = {
    Cmd = [ "${nodejs}/bin/node" "${claw-swap-app}/lib/claw-swap/dist/index.js" ];
    Env = [
      "NODE_ENV=production"
      "PORT=3000"
    ];
    ExposedPorts = { "3000/tcp" = {}; };
    WorkingDir = "${claw-swap-app}/lib/claw-swap";
  };
}
```

### Complete NixOS Module (nix/module.nix)

```nix
# nix/module.nix -- NixOS module for claw-swap containers, networks, and secrets
#
# @decision: Curried module pattern (same as parts).
# @decision: Do NOT import sops-nix module or set sops.defaultSopsFile.
# @decision: Do NOT declare Docker engine, firewall, or system-level config.
# @decision: All containers get security hardening via extraOptions.
{ self, sops-nix, ... }:

{ config, lib, pkgs, ... }:

let
  clawSwapSecretsFile = self + "/secrets/claw-swap.yaml";

  mkSecret = name: extra: {
    sopsFile = clawSwapSecretsFile;
  } // extra;

  postgresImage = pkgs.dockerTools.pullImage {
    imageName = "postgres";
    imageDigest = "sha256:PLACEHOLDER";  # pin via nix-prefetch-docker
    sha256 = "sha256-PLACEHOLDER";
    finalImageTag = "16-alpine";
    finalImageName = "postgres";
  };

  caddyImage = pkgs.dockerTools.pullImage {
    imageName = "caddy";
    imageDigest = "sha256:PLACEHOLDER";
    sha256 = "sha256-PLACEHOLDER";
    finalImageTag = "2-alpine";
    finalImageName = "caddy";
  };

  caddyfile = pkgs.writeText "Caddyfile" ''
    claw-swap.com {
      reverse_proxy claw-swap-app:3000
    }
  '';

in
{
  # -- Secrets ---------------------------------------------------------------

  sops.secrets = {
    "claw-swap-db-password" = mkSecret "claw-swap-db-password" {
      restartUnits = [ "docker-claw-swap-db.service" "docker-claw-swap-app.service" ];
    };
    "claw-swap-r2-account-id" = mkSecret "claw-swap-r2-account-id" {
      restartUnits = [ "docker-claw-swap-app.service" ];
    };
    "claw-swap-r2-access-key-id" = mkSecret "claw-swap-r2-access-key-id" {
      restartUnits = [ "docker-claw-swap-app.service" ];
    };
    "claw-swap-r2-secret-access-key" = mkSecret "claw-swap-r2-secret-access-key" {
      restartUnits = [ "docker-claw-swap-app.service" ];
    };
    "claw-swap-world-id-app-id" = mkSecret "claw-swap-world-id-app-id" {
      restartUnits = [ "docker-claw-swap-app.service" ];
    };
  };

  # -- Secret Templates (container env files) --------------------------------

  sops.templates."claw-swap-db-env" = {
    content = ''
      POSTGRES_PASSWORD=${config.sops.placeholder."claw-swap-db-password"}
    '';
  };

  sops.templates."claw-swap-app-env" = {
    content = ''
      DATABASE_URL=postgres://claw:${config.sops.placeholder."claw-swap-db-password"}@claw-swap-db:5432/claw_swap
      R2_ACCOUNT_ID=${config.sops.placeholder."claw-swap-r2-account-id"}
      R2_ACCESS_KEY_ID=${config.sops.placeholder."claw-swap-r2-access-key-id"}
      R2_SECRET_ACCESS_KEY=${config.sops.placeholder."claw-swap-r2-secret-access-key"}
      WORLD_ID_APP_ID=${config.sops.placeholder."claw-swap-world-id-app-id"}
    '';
  };

  # -- Docker Network --------------------------------------------------------

  systemd.services."docker-network-claw-swap-net" = {
    description = "Create claw-swap-net Docker network";
    after = [ "docker.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      ${pkgs.docker}/bin/docker network inspect claw-swap-net >/dev/null 2>&1 || \
      ${pkgs.docker}/bin/docker network create claw-swap-net \
        --driver bridge \
        --subnet 172.22.0.0/24
    '';
  };

  # -- Containers ------------------------------------------------------------

  virtualisation.oci-containers.backend = "docker";

  # PostgreSQL 16
  virtualisation.oci-containers.containers.claw-swap-db = {
    image = "postgres:16-alpine";
    imageFile = postgresImage;

    environment = {
      POSTGRES_DB = "claw_swap";
      POSTGRES_USER = "claw";
    };

    environmentFiles = [
      config.sops.templates."claw-swap-db-env".path
    ];

    volumes = [
      "/var/lib/claw-swap/pgdata:/var/lib/postgresql/data"
    ];

    extraOptions = [
      "--read-only"
      "--tmpfs=/tmp:rw,noexec,nosuid"
      "--tmpfs=/run/postgresql:rw,noexec,nosuid"
      "--cap-drop=ALL"
      "--cap-add=CHOWN"
      "--cap-add=SETUID"
      "--cap-add=SETGID"
      "--cap-add=FOWNER"
      "--cap-add=DAC_OVERRIDE"
      "--security-opt=no-new-privileges"
      "--memory=512m"
      "--cpus=1.0"
      "--shm-size=128m"
      "--restart=on-failure:5"
      "--network=claw-swap-net"
    ];
  };

  # Claw-swap app (Hono + Node.js)
  virtualisation.oci-containers.containers.claw-swap-app = {
    image = "claw-swap:latest";
    imageFile = pkgs.callPackage (self + "/nix/claw-swap-app.nix") { src = self; };

    environment = {
      NODE_ENV = "production";
      PORT = "3000";
      APP_BASE_URL = "https://claw-swap.com";
      BASE_URL = "https://claw-swap.com";
      WORLD_ID_ACTION = "claw_swap_agent_verification";
      R2_BUCKET_NAME = "claw-swap-photos";
    };

    environmentFiles = [
      config.sops.templates."claw-swap-app-env".path
    ];

    extraOptions = [
      "--read-only"
      "--tmpfs=/tmp:rw,noexec,nosuid"
      "--cap-drop=ALL"
      "--security-opt=no-new-privileges"
      "--memory=512m"
      "--cpus=1.0"
      "--restart=on-failure:5"
      "--network=claw-swap-net"
    ];

    dependsOn = [ "claw-swap-db" ];
  };

  # Caddy reverse proxy
  virtualisation.oci-containers.containers.claw-swap-caddy = {
    image = "caddy:2-alpine";
    imageFile = caddyImage;

    volumes = [
      "${caddyfile}:/etc/caddy/Caddyfile:ro"
      "/var/lib/claw-swap/caddy-data:/data"
      "/var/lib/claw-swap/caddy-config:/config"
    ];

    ports = [
      "80:80"
      "443:443"
    ];

    extraOptions = [
      "--read-only"
      "--tmpfs=/tmp:rw,noexec,nosuid"
      "--cap-drop=ALL"
      "--cap-add=NET_BIND_SERVICE"
      "--security-opt=no-new-privileges"
      "--memory=256m"
      "--cpus=0.5"
      "--restart=on-failure:5"
      "--network=claw-swap-net"
    ];

    dependsOn = [ "claw-swap-app" ];
  };

  # -- Systemd Ordering ------------------------------------------------------

  systemd.services."docker-claw-swap-db" = {
    after = [ "docker-network-claw-swap-net.service" ];
    requires = [ "docker-network-claw-swap-net.service" ];
  };

  systemd.services."docker-claw-swap-app" = {
    after = [ "docker-network-claw-swap-net.service" ];
    requires = [ "docker-network-claw-swap-net.service" ];
  };

  systemd.services."docker-claw-swap-caddy" = {
    after = [ "docker-network-claw-swap-net.service" ];
    requires = [ "docker-network-claw-swap-net.service" ];
  };

  # -- Host Directories ------------------------------------------------------

  systemd.tmpfiles.rules = [
    "d /var/lib/claw-swap 0755 root root -"
    "d /var/lib/claw-swap/pgdata 0755 root root -"
    "d /var/lib/claw-swap/caddy-data 0755 root root -"
    "d /var/lib/claw-swap/caddy-config 0755 root root -"
  ];
}
```

### sops-nix Setup for claw-swap

`.sops.yaml` (in claw-swap repo):
```yaml
keys:
  - &admin_local age1vma7w9nqlg9da8z60a99g8wv53ufakfmzxpkdnnzw39y34grug7qklz3xz
  - &host_acfs   age1jgn7pqqf4hvalqdrzqysxtnsydd5urnuczrfm86umr7yfr8pu5gqqet2t3
creation_rules:
  - path_regex: secrets/claw-swap\.yaml$
    key_groups:
      - age:
        - *admin_local
        - *host_acfs
```

`secrets/claw-swap.yaml` (plaintext before encryption, for documentation):
```yaml
# Encrypted with sops -- plaintext shown for reference only
claw-swap-db-password: <generated-strong-password>
claw-swap-r2-account-id: 1a6c78c958369226b4fdb7a42baff586
claw-swap-r2-access-key-id: 20f5f15147f03e8a37a11b3f56d8da2a
claw-swap-r2-secret-access-key: <from-deploy/secrets/claw-swap.env>
claw-swap-world-id-app-id: app_69e5d2d8b8c90c82122276386f6778b2
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|-----------------|--------------|--------|
| Manual `docker run` commands on server | `virtualisation.oci-containers` with Nix declarations | Phase 3.1 (parts) established this | Declarative, reproducible, systemd-managed |
| Plaintext `.env` files in deploy/ | sops-nix encrypted secrets with `sops.templates` | Phase 3.1 established this | Encrypted at rest, atomic injection, restart-on-change |
| Docker Hub image pulls at deploy time | `dockerTools.pullImage` with digest pinning | Standard nixpkgs pattern | Reproducible, no registry dependency at deploy time |
| Manual Caddy container with volume mounts | NixOS module with `pkgs.writeText` Caddyfile | This phase introduces it | Caddyfile is version-controlled Nix, not a loose file on the server |
| No container resource limits | `--memory`, `--cpus` via extraOptions | Phase 9 research recommended for Phase 4 | Prevents runaway containers from starving host |

## Inventory: What Exists Today (Migration Reference)

### Current claw-swap Deployment on acfs (Manual Docker)

| Component | Current State | Migration Target |
|-----------|--------------|-----------------|
| App container | Manual `docker run` with Dockerfile build | `dockerTools.buildLayeredImage` + `oci-containers` |
| PostgreSQL | Manual `docker run` with data in `/var/lib/claw-swap/pgdata` (or similar) | `oci-containers` with `pullImage`, same data volume path |
| Caddy | Manual `docker run` with deploy/Caddyfile | `oci-containers` with `pullImage`, Caddyfile via `pkgs.writeText` |
| Secrets | Plaintext in `deploy/secrets/claw-swap.env` and `deploy/secrets/cloudflare.key` | sops-nix encrypted in `secrets/claw-swap.yaml` |
| Docker network | Likely default bridge or manual network | Declarative `claw-swap-net` via systemd oneshot |
| TLS certificates | Caddy auto-managed in `deploy/caddy-data/` | Persisted in `/var/lib/claw-swap/caddy-data` (migrate existing certs to avoid re-issuance) |

### Secrets Inventory (from deploy/secrets/claw-swap.env)

| Secret | Current Source | sops Key Name | Used By |
|--------|---------------|---------------|---------|
| DATABASE_URL (contains password) | claw-swap.env | `claw-swap-db-password` (extracted) | App container |
| R2_ACCOUNT_ID | claw-swap.env | `claw-swap-r2-account-id` | App container |
| R2_ACCESS_KEY_ID | claw-swap.env | `claw-swap-r2-access-key-id` | App container |
| R2_SECRET_ACCESS_KEY | claw-swap.env | `claw-swap-r2-secret-access-key` | App container |
| WORLD_ID_APP_ID | claw-swap.env | `claw-swap-world-id-app-id` | App container |
| WORLD_ID_ACTION | claw-swap.env | Not a secret (constant) | App container env |
| Cloudflare API key | cloudflare.key | Not needed (HTTP-01 challenge) | Was for DNS challenge |

### claw-swap App Dependencies (from package.json)

| Package | Type | Nix Build Impact |
|---------|------|-----------------|
| @hono/node-server | Pure JS | None |
| drizzle-orm, postgres | Pure JS | None |
| sharp | **Native addon (libvips)** | Requires `--ignore-scripts` + special handling OR removal from deps (currently unused in source) |
| @aws-sdk/* | Pure JS | None |
| zod, nanoid, nodemailer, resend | Pure JS | None |

## Open Questions

1. **Should sharp be removed from claw-swap's package.json?**
   - What we know: `sharp` v0.34.5 is in dependencies but grep finds zero imports in `src/`. It was likely added for planned image processing (photo uploads via R2) but never used.
   - What's unclear: Whether the user plans to add sharp usage soon.
   - Recommendation: Ask the user. If unused, remove it to simplify the Nix build significantly. If needed, the `--ignore-scripts` + `npm rebuild sharp` pattern with `pkgs.vips` in `nativeBuildInputs` will work.

2. **Existing PostgreSQL data migration**
   - What we know: claw-swap is currently running on the server with a PostgreSQL container and real data. The declarative migration needs to preserve this data.
   - What's unclear: The exact volume mount path of the current PostgreSQL data directory. The `deploy/secrets/claw-swap.env` shows `DATABASE_URL=postgres://claw:...@claw-swap-db:5432/claw_swap`.
   - Recommendation: Before switching, identify the current data volume path (likely via `docker inspect`). Point the new `oci-containers` declaration at the same path. The PostgreSQL data format is compatible -- no migration needed if the same PG major version (16) is used.

3. **Caddy TLS certificate migration**
   - What we know: Caddy currently stores certs in `deploy/caddy-data/caddy/` (root-owned). The new declaration uses `/var/lib/claw-swap/caddy-data`.
   - What's unclear: Whether we need to copy existing certs or let Caddy re-issue.
   - Recommendation: Copy existing `caddy-data` contents to `/var/lib/claw-swap/caddy-data` during migration to avoid hitting Let's Encrypt rate limits. If not possible, Caddy will re-issue automatically (rate limit is 5 duplicate certs per week, so a single re-issuance is fine).

4. **Database migration runner**
   - What we know: Drizzle SQL migration files exist in `drizzle/` and `src/db/migrations/`. The current database has all migrations applied.
   - What's unclear: Whether future schema changes need an automated migration runner or if manual `drizzle-kit migrate` is acceptable.
   - Recommendation: For v1, manual migration is acceptable. The database is already initialized with all current schemas. Future migrations can be run with `docker exec claw-swap-app npx drizzle-kit migrate` or a dedicated systemd oneshot. This is not Phase 4 scope.

## Sources

### Primary (HIGH confidence)
- Codebase inspection: `/data/projects/claw-swap/` -- Dockerfile, package.json, src/, deploy/secrets/, .planning/ examined directly
- Codebase inspection: `/data/projects/neurosys/` -- all modules, flake.nix, secrets, .sops.yaml examined directly
- Codebase inspection: `/data/projects/parts/` -- flake.nix, nix/module.nix, nix/parts-agent.nix, nix/parts-tools.nix examined directly (reference implementation)
- Phase 9 research: `09-RESEARCH.md` -- Docker container hardening executive summary with code patterns
- Phase 3.1 research: `03.1-RESEARCH.md` -- cross-flake module pattern, oci-containers, sops-nix integration
- [NixOS oci-containers module source](https://github.com/NixOS/nixpkgs/blob/master/nixos/modules/virtualisation/oci-containers.nix) -- capabilities, extraOptions, imageFile behavior
- [OWASP Docker Security Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Docker_Security_Cheat_Sheet.html) -- container hardening flags
- [Caddy automatic HTTPS documentation](https://caddyserver.com/docs/automatic-https) -- HTTP-01 challenge requirements
- [Caddy reverse proxy quick-start](https://caddyserver.com/docs/quick-starts/reverse-proxy) -- Caddyfile syntax
- [nixpkgs dockerTools documentation](https://ryantm.github.io/nixpkgs/builders/images/dockertools/) -- pullImage, buildLayeredImage parameters

### Secondary (MEDIUM confidence)
- [NixOS Discourse: Docker compose to oci-container migration](https://discourse.nixos.org/t/docker-compose-oci-container-how-to-migrate-docker-compose-sections/40657/2) -- extraOptions patterns
- [NixOS Discourse: Postgres in a container](https://discourse.nixos.org/t/postgres-in-a-container/42641) -- data volume persistence
- [Docker official docs: restart policies](https://docs.docker.com/engine/containers/start-containers-automatically/) -- on-failure:N syntax
- [sharp installation documentation](https://sharp.pixelplumbing.com/install/) -- prebuilt binaries, ignore-scripts behavior

### Tertiary (LOW confidence)
- PostgreSQL cap-add requirements: Derived from Docker PostgreSQL entrypoint analysis. The exact minimum set of capabilities needed may vary by PG version. Testing required.
- sharp v0.34.5 in Nix sandbox: Known to be problematic. The `--ignore-scripts` + `npm rebuild` pattern is proven for parts but not yet verified for sharp specifically.

## Metadata

**Confidence breakdown:**
- Cross-flake module pattern: HIGH -- identical to parts (proven in Phase 3.1, code verified)
- Container hardening: HIGH -- OWASP + Docker docs + Phase 9 research all confirm approach
- Caddy integration: HIGH -- standard Docker pattern, automatic HTTPS well-documented
- PostgreSQL container: HIGH -- standard Docker PostgreSQL pattern, data volume persistence straightforward
- buildNpmPackage for claw-swap: MEDIUM -- simpler than parts (no workspaces), but sharp dependency adds uncertainty
- PostgreSQL capabilities: MEDIUM -- cap-add list is derived analysis, needs testing

**Research date:** 2026-02-16
**Valid until:** 2026-03-16 (stable domain; NixOS patterns and Docker images change slowly)
