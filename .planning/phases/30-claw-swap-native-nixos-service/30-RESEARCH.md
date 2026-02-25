# Phase 30 Research: Claw-Swap Native NixOS Service

## Research Goal

What does a planner need to know to write a tight, correct, minimal plan to
replace claw-swap's Docker containers with native NixOS services?

---

## 1. Current State (What Exists Today)

### Where claw-swap runs

The `claw-swap` flake input is imported in `flake.nix` `commonModules`, so
`inputs.claw-swap.nixosModules.default` is applied to **both** hosts
(`neurosys` and `ovh`). The containers only serve traffic on OVH because
nginx (`modules/nginx.nix`) is only imported by `hosts/ovh/default.nix` and
proxies `claw-swap.com` to `127.0.0.1:3000`.

The Contabo host (`neurosys`) also starts the containers but has no public
nginx vhost pointing at them. Phase 30 targets OVH as the production host.

### What the module declares today

Source: `/data/projects/claw-swap/nix/module.nix`

**Secrets** (8 total, all pointing at `secrets/claw-swap.yaml`):
- `claw-swap-db-password` — restarts both docker units
- `claw-swap-r2-account-id`, `claw-swap-r2-access-key-id`, `claw-swap-r2-secret-access-key`
- `claw-swap-world-id-app-id`
- `claw-swap-smtp-user`, `claw-swap-smtp-pass`
- `claw-swap-admin-notify-email`

**sops templates** (2 env files for docker env injection):
- `claw-swap-db-env` — `POSTGRES_PASSWORD=<placeholder>`
- `claw-swap-app-env` — all 8 secrets rendered as `KEY=VALUE` lines

**Docker containers** (2):
- `claw-swap-db`: `postgres:16-alpine` with pgdata at `/var/lib/claw-swap/pgdata`
- `claw-swap-app`: built from `nix/claw-swap-app.nix`, port `127.0.0.1:3000:3000`

**Docker network**: `claw-swap-net` (bridge `172.22.0.0/24`)

**Systemd tmpfiles**: creates `/var/lib/claw-swap` and `/var/lib/claw-swap/pgdata`

### The app

- Hono/TypeScript on Node.js 22, built with `buildNpmPackage`
- Entry point: `dist/index.js` (TypeScript compiled via `npm run build`)
- Reads `DATABASE_URL` as a postgres connection string
- Reads 7 other env vars at runtime (R2, World ID, SMTP, email)
- Listens on `PORT` (default 3000), binds all interfaces unless constrained
- SIGTERM handler: closes HTTP server then closes Postgres pool, then exits 0
- Drizzle ORM migrations live at `src/db/migrations/` (6 SQL files, 0000–0005)

### Environment variables the app needs

| Variable | Secret? | Current source |
|---|---|---|
| `DATABASE_URL` | yes (password embedded) | `claw-swap-app-env` template |
| `R2_ACCOUNT_ID` | yes | `claw-swap-app-env` template |
| `R2_ACCESS_KEY_ID` | yes | `claw-swap-app-env` template |
| `R2_SECRET_ACCESS_KEY` | yes | `claw-swap-app-env` template |
| `WORLD_ID_APP_ID` | yes | `claw-swap-app-env` template |
| `SMTP_USER` | yes | `claw-swap-app-env` template |
| `SMTP_PASS` | yes | `claw-swap-app-env` template |
| `ADMIN_NOTIFY_EMAIL` | yes | `claw-swap-app-env` template |
| `NODE_ENV` | no | container `environment` block |
| `PORT` | no | container `environment` block |
| `APP_BASE_URL` | no | container `environment` block |
| `BASE_URL` | no | container `environment` block |
| `WORLD_ID_ACTION` | no | container `environment` block |
| `R2_BUCKET_NAME` | no | container `environment` block |

---

## 2. What Changes in Phase 30

### A. Postgres: Docker container → `services.postgresql`

Replace `virtualisation.oci-containers.containers.claw-swap-db` with:

```nix
services.postgresql = {
  enable = true;
  package = pkgs.postgresql_16;
  ensureDatabases = [ "claw_swap" ];
  ensureUsers = [
    {
      name = "claw";
      ensureDBOwnership = true;
    }
  ];
};
```

**Password injection problem**: `ensureUsers` uses peer authentication by
default — no password required when the system user matches the DB user.
However, the app connects via TCP with `DATABASE_URL=postgres://claw:<pass>@localhost:5432/claw_swap`.
Two options:

**Option A (recommended): pg_hba trust on loopback + no password in DATABASE_URL**
Set `authentication` to trust the local loopback connection from `claw` user:
```nix
services.postgresql.authentication = lib.mkOverride 10 ''
  local all postgres peer
  local claw_swap claw peer
  host  claw_swap claw 127.0.0.1/32 trust
'';
```
Then `DATABASE_URL=postgres://claw@127.0.0.1:5432/claw_swap` (no password).
Advantage: no secret in DATABASE_URL, no password injection complexity.
Risk: any local process that can reach 127.0.0.1:5432 as `claw` DB user can
connect without a password. On this single-tenant server this is acceptable.

**Option B: postStart ALTER ROLE password injection**
Use `systemd.services.postgresql.postStart` to run psql and set the password
from the sops secret file on every start:
```nix
systemd.services.postgresql.postStart = ''
  $PSQL -tAc "ALTER ROLE claw WITH PASSWORD '$(cat ${config.sops.secrets."claw-swap-db-password".path})'"
'';
```
Then keep DATABASE_URL with the password embedded via sops template.
Downside: password briefly in process arguments/environment during postStart.

The plan should choose one. Option A (local trust) is simpler and the project
security model already accepts that the server is single-tenant.

**Option C: SCRAM-SHA-256 hash in ensureClauses**
Pre-compute the hash and embed in Nix config. Requires running a Python
scramp script to generate. Not practical for sops-managed rotating secrets.

### B. App: Docker container → native systemd service

The app is already built as a Nix derivation inside `claw-swap-app.nix`.
Currently that file produces a Docker image via `pkgs.dockerTools.buildLayeredImage`.
For Phase 30 the **inner** `buildNpmPackage` derivation must be exposed
separately so the systemd service can reference it directly.

**Required change in `nix/claw-swap-app.nix`** (claw-swap repo):
The derivation currently returns the Docker image, not the npm package.
Two approaches:

1. **Split the file**: export both the package and the image from the file
   (the image can remain for backward compat during transition; remove later).
2. **Inline the package in module.nix**: use `pkgs.callPackage` on a new
   minimal nix file that just returns the buildNpmPackage result.

The flake already exposes:
```nix
packages.${system}.claw-swap-app = pkgs.callPackage ./nix/claw-swap-app.nix { src = self; };
```
…but this returns the Docker image, not the binary. The `module.nix` does
`pkgs.callPackage (self + "/nix/claw-swap-app.nix") { src = self; }` for the
imageFile of the container.

**Cleanest approach**: rename `claw-swap-app.nix` or add a `claw-swap-pkg.nix`
that returns just the `buildNpmPackage` result (already defined as
`claw-swap-app` local in the current file). Then use that as:
- `ExecStart = "${claw-swap-pkg}/lib/claw-swap/dist/index.js"` — wrong, Node.js binary needed
- `ExecStart = "${pkgs.nodejs_22}/bin/node ${claw-swap-pkg}/lib/claw-swap/dist/index.js"`

The working directory must be `${claw-swap-pkg}/lib/claw-swap` because
`app.ts` uses `serveStatic` with relative paths (`./public/...`).

**Systemd service template**:
```nix
systemd.services.claw-swap-app = {
  description = "Claw-Swap Hono API server";
  after = [ "network.target" "postgresql.service" "sops-nix.service" ];
  requires = [ "postgresql.service" ];
  wantedBy = [ "multi-user.target" ];
  serviceConfig = {
    ExecStart = "${pkgs.nodejs_22}/bin/node ${claw-swap-pkg}/lib/claw-swap/dist/index.js";
    WorkingDirectory = "${claw-swap-pkg}/lib/claw-swap";
    EnvironmentFile = config.sops.templates."claw-swap-app-env".path;
    Environment = [
      "NODE_ENV=production"
      "PORT=3000"
      "APP_BASE_URL=https://claw-swap.com"
      "BASE_URL=https://claw-swap.com"
      "WORLD_ID_ACTION=claw_swap_agent_verification"
      "R2_BUCKET_NAME=claw-swap-photos"
    ];
    User = "claw-swap";
    Group = "claw-swap";
    Restart = "on-failure";
    RestartSec = "5s";
    # Hardening
    PrivateTmp = true;
    ProtectSystem = "strict";
    ProtectHome = true;
    ReadWritePaths = [];   # no filesystem writes needed
  };
};
```

Note: `User = "claw-swap"` requires a matching `users.users.claw-swap` and
`users.groups.claw-swap` declaration. The `claw` postgresql user maps to the
OS user `claw-swap` via peer auth only if they share a name — with local trust
(Option A) the OS user name does not need to match.

### C. sops templates: simplification

The `claw-swap-db-env` template becomes unused (no Docker postgres container).
The `claw-swap-app-env` template needs revision:
- If Option A (local trust): remove `DATABASE_URL` from template (or update it
  to `postgres://claw@127.0.0.1:5432/claw_swap`)
- The `restartUnits` on all secrets change from `docker-*` unit names to
  `claw-swap-app.service`
- `claw-swap-db-password` secret becomes unused if Option A is chosen

### D. Removals

From `nix/module.nix` in the claw-swap repo:
1. `virtualisation.oci-containers.containers.claw-swap-db` block
2. `virtualisation.oci-containers.containers.claw-swap-app` block
3. `systemd.services."docker-network-claw-swap-net"` block
4. `systemd.services."docker-claw-swap-db"` ordering override
5. `systemd.services."docker-claw-swap-app"` ordering override
6. `postgresImage` let binding (the `pkgs.dockerTools.pullImage` call)
7. `sops.templates."claw-swap-db-env"` (unused after migration)

From `modules/docker.nix` in neurosys repo:
- The `docker0` trusted interface was added for container-to-container traffic.
  After Phase 30, only parts containers remain. `docker0` trust stays because
  parts still needs it.

From `modules/networking.nix` in neurosys repo:
- No changes needed (port 3000 is not in `internalOnlyPorts`, and the app
  still binds on `127.0.0.1:3000` or `0.0.0.0:3000` behind nginx).

### E. impermanence.nix: persistence

`/var/lib/claw-swap` is already in the persistence list. After Phase 30:
- `/var/lib/claw-swap/pgdata` is no longer needed (PostgreSQL manages its own
  data directory via `services.postgresql.dataDir`, which defaults to
  `/var/lib/postgresql`).
- `/var/lib/postgresql` must be added to impermanence persistence.
- The old `/var/lib/claw-swap/pgdata` directory entry can be removed.
- `/var/lib/claw-swap` can be removed entirely if no other app data lives
  there (currently only pgdata uses it).

### F. restic.nix: backup hook change

Currently `backupPrepareCommand` uses `docker exec claw-swap-db pg_dumpall`.
After Phase 30, use `pg_dumpall` directly as the postgres user:

```nix
backupPrepareCommand = ''
  ${pkgs.sudo}/bin/sudo -u postgres ${config.services.postgresql.package}/bin/pg_dumpall \
    -f /var/lib/postgresql/backup.sql 2>/dev/null || true
'';
backupCleanupCommand = ''
  rm -f /var/lib/postgresql/backup.sql
  # ... rest unchanged
'';
```

Or use the `services.postgresql.package` reference, or set up `postStart` to
do it. The key change: no docker exec, just direct `pg_dumpall` as postgres user.

### G. homepage.nix: update claw-swap entry

Currently references container `claw-swap-app` via docker widget:
```nix
"claw-swap" = {
  server = "local";
  container = "claw-swap-app";
};
```
After Phase 30, change to `siteMonitor`:
```nix
"claw-swap" = {
  href = "https://claw-swap.com";
  description = "Trading platform — nginx + Node.js + PostgreSQL.";
  siteMonitor = "http://localhost:3000/health";
  icon = "nginx";
};
```

---

## 3. Database Migration Handling

The app uses Drizzle ORM. Migrations are in `src/db/migrations/` (6 SQL files
0000–0005) and also copied to `$out/lib/claw-swap/migrations` in the install
phase.

**Current state**: The Docker container setup has no explicit migration runner.
Migrations appear to be applied manually via `npm run db:migrate` / `drizzle-kit migrate`.

**For Phase 30**: On first boot after migration, the PostgreSQL instance will be
empty. Need a one-time or idempotent migration strategy. Options:

1. **One-time manual step**: after deploying, SSH in and run
   `drizzle-kit migrate` against the new native PostgreSQL (with credentials).
   Acceptable for this project scale.

2. **systemd oneshot migration service**: a `claw-swap-migrate` oneshot service
   that runs before `claw-swap-app.service` and executes `drizzle-kit migrate`.
   Problem: `drizzle-kit` is a dev dependency not included in the production
   Nix derivation's `dist/` output.

3. **pg_restore from backup**: if migrating from Docker, dump from Docker
   postgres and restore into native postgres. Cleanest migration path for
   production data.

**Recommendation**: For production (OVH), the plan must include a data
migration step:
1. Dump data from Docker postgres: `docker exec claw-swap-db pg_dumpall -U claw > /tmp/claw-swap-dump.sql`
2. Deploy Phase 30 config (native postgres starts empty)
3. Restore: `psql -U claw -d claw_swap < /tmp/claw-swap-dump.sql`
4. Verify and start app

For Contabo (neurosys), Docker containers also run there but aren't in
production use, so the migration concern is primarily OVH.

---

## 4. Key NixOS Patterns to Use

### Native systemd service with sops EnvironmentFile

Proven by `modules/secret-proxy.nix` (Phase 22):
```nix
systemd.services.anthropic-secret-proxy = {
  after = [ "network.target" "sops-nix.service" ];
  wantedBy = [ "multi-user.target" ];
  serviceConfig = {
    ExecStart = "${binary}/bin/...";
    EnvironmentFile = config.sops.templates."template-name".path;
    User = "service-user";
    Restart = "on-failure";
    RestartSec = "5s";
  };
};
```

This is the exact pattern to follow for `claw-swap-app.service`.

### services.postgresql minimal config

```nix
services.postgresql = {
  enable = true;
  package = pkgs.postgresql_16;   # match Docker image version
  ensureDatabases = [ "claw_swap" ];
  ensureUsers = [{
    name = "claw";
    ensureDBOwnership = true;
  }];
};
```

### System user + group

```nix
users.users.claw-swap = {
  isSystemUser = true;
  group = "claw-swap";
};
users.groups.claw-swap = {};
```

---

## 5. Scope Boundaries

### In scope (Phase 30)

- `nix/module.nix` in **claw-swap repo**: remove containers/network, add
  `services.postgresql`, add `systemd.services.claw-swap-app`
- `nix/claw-swap-app.nix` in **claw-swap repo**: expose the buildNpmPackage
  result separately from the Docker image (or remove the Docker image wrapper)
- `modules/impermanence.nix` in **neurosys repo**: swap `/var/lib/claw-swap` for
  `/var/lib/postgresql`
- `modules/restic.nix` in **neurosys repo**: update `backupPrepareCommand`
- `modules/homepage.nix` in **neurosys repo**: update claw-swap widget
- Data migration on OVH (manual step in plan)

### Out of scope (Phase 30)

- `parts` containers — stay Docker, unaffected
- `modules/docker.nix` — stays mostly unchanged (parts still needs Docker)
  - The `virtualisation.oci-containers.backend = "docker"` line can be removed
    only if no containers remain; parts containers live in `parts` flake module,
    so `docker.nix` stays
- `modules/networking.nix` — no port changes needed; port 3000 is
  not in `internalOnlyPorts` (it's only accessible on 127.0.0.1 via nginx)
- nginx — unchanged, still proxies to 127.0.0.1:3000

---

## 6. Risks and Unknowns

### Risk 1: Which host actually runs claw-swap in production?

The `commonModules` in `flake.nix` includes `claw-swap` module for **both**
neurosys and OVH. After Phase 30:
- If both hosts should run native postgres, both get `services.postgresql`
- If only OVH should run it, the claw-swap module needs to be moved from
  `commonModules` to `hosts/ovh/default.nix` imports — a larger refactor

**Recommendation**: Keep module in commonModules; both hosts get postgresql
and the app. Neurosys already has /var/lib/claw-swap persisted.

### Risk 2: Nix derivation exposing the app binary

The current `claw-swap-app.nix` returns a Docker image. The `module.nix`
references it as `pkgs.callPackage (self + "/nix/claw-swap-app.nix") { src = self; }`.
The implementer must refactor this file to expose the raw npm package output
(not the layered image).

The safest approach: define two outputs from the file:
```nix
# nix/claw-swap-app.nix
{ pkgs, src, ... }:
let
  app = pkgs.buildNpmPackage { ... };    # the npm package
  image = pkgs.dockerTools.buildLayeredImage { ... };  # keep for reference
in
{ inherit app image; }
```
Then in `module.nix`:
```nix
let
  claw-swap-pkg = (pkgs.callPackage (self + "/nix/claw-swap-app.nix") { src = self; }).app;
in ...
```

But this is a **breaking change** to the flake's
`packages.${system}.claw-swap-app` since it currently returns the image.
Either update the flake output or add `claw-swap-pkg` as a separate output.

### Risk 3: Working directory for serveStatic

`app.ts` uses:
```ts
app.use('/favicon.ico', serveStatic({ path: './public/favicon.ico' }));
```
This resolves `./public` relative to the Node.js process working directory.
The install phase copies `public/` into `$out/lib/claw-swap/public`. So
`WorkingDirectory` in the systemd unit MUST be `${claw-swap-pkg}/lib/claw-swap`.
If working directory is wrong, static files will 404.

### Risk 4: Data migration on OVH (production)

There is live data in the Docker postgres container on OVH. The plan must
include explicit steps to:
1. Quiesce traffic (nginx can stay up, the app will be down briefly)
2. Dump from Docker postgres
3. Switch to native postgres
4. Restore the dump
5. Verify the app connects and responds

### Risk 5: `nix flake check` on both hosts

After the change, both `nixosConfigurations.neurosys` and `nixosConfigurations.ovh`
must pass `nix flake check`. The `claw-swap` module changes affect both.

### Risk 6: `postgresql` module on neurosys (Contabo) has no port exposure issue

Port 5432 is never added to `allowedTCPPorts` by `services.postgresql` by default
(it binds on Unix socket only unless `enableTCPIP` is set). But if `enableTCPIP`
is set for localhost connectivity, the firewall assertion in `networking.nix`
will not flag it (5432 is not in `internalOnlyPorts`). Safe as-is.

The DATABASE_URL for the app should use `127.0.0.1:5432` (TCP) and require
`services.postgresql.enableTCPIP = true`, OR use a Unix socket path like
`postgres:///claw_swap?host=/run/postgresql&user=claw` — Unix socket is cleaner
and avoids opening even localhost TCP.

**Using Unix socket DATABASE_URL**: `postgres://claw@/claw_swap?host=/run/postgresql`
The postgres.js connection string parser supports this. No `enableTCPIP` needed.
The app's OS user (`claw-swap`) must have access to `/run/postgresql` which is
owned by `postgres` user/group with 2775 permissions — the `claw-swap` user
must be in the `postgres` group, OR use `local` trust in `pg_hba.conf` for
the `claw` DB user.

---

## 7. Files to Change (Summary)

### claw-swap repo (`/data/projects/claw-swap`)

| File | Change |
|---|---|
| `nix/claw-swap-app.nix` | Separate the buildNpmPackage derivation from the Docker image wrapper; return the npm package directly (or a set) |
| `nix/module.nix` | Remove: 2 containers, docker network service, 2 ordering overrides, `claw-swap-db-env` template, `postgresImage` let binding. Add: `services.postgresql`, `systemd.services.claw-swap-app`, `users.users.claw-swap`, `users.groups.claw-swap`. Update: secret `restartUnits`, `claw-swap-app-env` template content |

### neurosys repo (`/data/projects/neurosys`)

| File | Change |
|---|---|
| `modules/impermanence.nix` | Replace `/var/lib/claw-swap` with `/var/lib/postgresql`; remove `/var/lib/claw-swap/pgdata` entry |
| `modules/restic.nix` | Update `backupPrepareCommand` from `docker exec` to direct `pg_dumpall` |
| `modules/homepage.nix` | Update claw-swap widget from `container` reference to `siteMonitor` |

### Possible neurosys repo cleanups (if no containers remain):
- `modules/docker.nix`: The `virtualisation.oci-containers.backend = "docker"` pin was added specifically for claw-swap (DOCK-03 decision). Parts containers still use oci-containers, so this stays.

---

## 8. Decisions the Planner Needs to Make

1. **Password strategy**: Local trust (no password in DATABASE_URL, simpler)
   vs. postStart ALTER ROLE (preserves the existing DB password secret)?
   Recommendation: local trust with Unix socket — removes one secret entirely.

2. **MODULE LOCATION**: Keep claw-swap module in commonModules (both hosts get
   PostgreSQL) or move to OVH-only? Recommendation: commonModules for now,
   add a note to move when neurosys is decommissioned.

3. **claw-swap-app.nix refactor strategy**: Return the package directly (breaking
   `packages.claw-swap-app` which currently returns the Docker image), or add a
   new separate file for the package? Recommendation: refactor `claw-swap-app.nix`
   to return the npm package directly, update the flake output.

4. **Data migration**: Is there live data on OVH to preserve? If yes, must
   include a pg_dumpall/restore step as a manual deploy-time operation.
   If no live data, can skip and let `ensureDatabases` create the empty DB.

5. **Port binding**: Unix socket (cleaner, no enableTCPIP) vs. TCP localhost
   (127.0.0.1:5432)? Recommendation: Unix socket with local trust pg_hba.

6. **`claw-swap-db-password` secret**: Retire it (if choosing local trust) or
   keep it? If retiring, update `secrets/claw-swap.yaml` (delete the key).

---

## 9. Reference: Similar Module Pattern (Phase 22)

The `modules/secret-proxy.nix` is the closest existing pattern for a native
systemd service with sops env injection. Key attributes reused for Phase 30:

```nix
# System user
users.users.secret-proxy = { isSystemUser = true; group = "secret-proxy"; };
users.groups.secret-proxy = {};

# Sops template owned by that user
sops.templates."secret-proxy-env" = {
  content = "KEY=${config.sops.placeholder."secret-name"}";
  owner = "secret-proxy";
};

# Service uses EnvironmentFile pointing at the rendered template
systemd.services.anthropic-secret-proxy = {
  after = [ "network.target" "sops-nix.service" ];
  wantedBy = [ "multi-user.target" ];
  serviceConfig = {
    ExecStart = "...";
    EnvironmentFile = config.sops.templates."secret-proxy-env".path;
    User = "secret-proxy";
    Restart = "on-failure";
    RestartSec = "5s";
  };
};
```

---

## 10. Estimated Plan Complexity

This phase touches two repos (claw-swap and neurosys) and requires a live data
migration on OVH. Suggested plan breakdown:

**Plan 30-01: Module rewrite + flake check**
- Rewrite `nix/claw-swap-app.nix` to expose npm package
- Rewrite `nix/module.nix` to use native postgresql + systemd service
- Update neurosys modules (impermanence, restic, homepage)
- Validate with `nix flake check` locally

**Plan 30-02: Deploy + data migration on OVH**
- Stop the Docker app container
- Dump Docker postgres data
- Deploy new config (native postgres starts empty)
- Restore the dump into native postgres
- Verify: `curl https://claw-swap.com` returns 200

Two plans, moderate complexity. The docker-to-native data migration is the
highest-risk step and warrants its own plan.
