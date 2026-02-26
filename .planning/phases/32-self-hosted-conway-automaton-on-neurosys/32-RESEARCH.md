# Phase 32: Self-Hosted Conway Automaton on Neurosys - Research

**Researched:** 2026-02-25
**Domain:** Conway Automaton runtime self-hosting / NixOS service packaging / pnpm workspace builds
**Confidence:** HIGH -- source code fully reviewed, all 10 key questions answered from primary sources

---

## Summary

The Conway Automaton (`@conway/automaton` v0.2.0) is a TypeScript agent runtime that runs as a persistent Node.js process. It uses `better-sqlite3` for state persistence, `pnpm` as its package manager, and targets Node.js >= 20. The framework is designed to run inside Conway Cloud Firecracker microVMs but includes explicit fallback logic for running without a sandbox (local mode). Self-hosting on NixOS is architecturally feasible with moderate effort. The main challenges are: (1) pnpm-based packaging for Nix (no `buildNpmPackage` equivalent -- must use `buildPnpmPackage` or `pnpm2nix`), (2) `better-sqlite3` native addon compilation, (3) the Anthropic API base URL being hardcoded to `https://api.anthropic.com` (requires a source patch or upstream PR to support the existing secret proxy), and (4) bypassing the interactive setup wizard with a pre-seeded configuration.

**Key recommendation:** Package the automaton using `pkgs.buildNpmPackage` after generating a `package-lock.json` from the `pnpm-lock.yaml` (or use `pnpm deploy` to create a flat install). Pre-seed the `~/.automaton/` state directory with `automaton.json`, `wallet.json`, `heartbeat.yml`, `SOUL.md`, and `constitution.md` via NixOS activation scripts. Patch `src/conway/inference.ts` to read `ANTHROPIC_BASE_URL` environment variable instead of hardcoding `https://api.anthropic.com`. Run as a systemd service under a dedicated `automaton` user with sops-nix secret injection.

---

## Answers to Key Questions

### Q1: Does the Automaton work without Conway Cloud sandbox?

**YES, with degraded Conway Cloud features.** The framework has explicit local-mode fallback throughout:

- **`src/setup/environment.ts`**: `detectEnvironment()` checks (in order): `CONWAY_SANDBOX_ID` env var, `/etc/conway/sandbox.json` file, `/.dockerenv`, then falls back to `process.platform`. When no sandbox is detected, it returns `{ type: "linux", sandboxId: "" }`.

- **`src/conway/client.ts`**: When `sandboxId` is empty, the `isLocal` flag is set to `true`. All sandbox operations (`exec`, `writeFile`, `readFile`) fall back to local execution (`execSync`, `fs.writeFileSync`, `fs.readFileSync`). Port exposure returns `http://localhost:<port>`.

- **What works without Conway Cloud:**
  - Agent loop (ReAct cycle) -- fully functional
  - Inference (BYOK keys for Anthropic/OpenAI/Ollama) -- fully functional
  - State persistence (SQLite) -- fully functional
  - Heartbeat daemon -- fully functional
  - Git state versioning -- fully functional (local git ops)
  - Self-modification -- fully functional (local file ops)
  - Skills system -- fully functional

- **What degrades without Conway Cloud:**
  - `createSandbox` / `deleteSandbox` / `listSandboxes` -- requires Conway API (child agent spawning broken)
  - `getCreditsBalance` / `getCreditsPricing` -- returns errors (caught, defaults to 0 credits)
  - `transferCredits` -- requires Conway API
  - `searchDomains` / `registerDomain` -- requires Conway API
  - `exposePort` -- works but returns localhost URL only
  - `registerAutomaton` -- Conway API call, fails silently (non-blocking)
  - Heartbeat `check_credits`, `heartbeat_ping` -- pings Conway API, fails gracefully
  - Social relay (`check_social_inbox`) -- requires Conway social relay server
  - USDC balance checks (`getUsdcBalance`) -- requires Base RPC node (works with public RPC)
  - Bootstrap topup -- requires Conway API, fails gracefully with warning

- **Survival tier impact:** Without Conway credits, the agent will read `creditsCents = 0` on every heartbeat check. After 1 hour grace period, it transitions to "dead" state. **Mitigation:** Either (a) patch the survival logic to always return "normal" tier when self-hosted, or (b) provide a Conway API key so credits can be checked/managed.

### Q2: Conway Cloud API authentication

The Conway API uses API keys provisioned via SIWE (Sign-In With Ethereum):

1. Automaton generates an EVM wallet (private key stored at `~/.automaton/wallet.json`)
2. Signs a SIWE message with domain `conway.tech`, chainId 8453 (Base)
3. Posts to `POST /v1/auth/verify` to get a JWT
4. Uses JWT to create API key via `POST /v1/auth/api-keys`
5. API key format: `cnwy_k_...` prefix
6. API key sent as `Authorization: <key>` header (no Bearer prefix) in all subsequent requests

**For self-hosted mode:**
- A Conway API key is only needed if agents want to USE Conway Cloud tools (sandboxes, domains, credits)
- The API key can be provisioned once via `automaton --provision` and stored
- If no API key is set, the automaton still runs but with limited functionality (see Q1)
- Env var override: `CONWAY_API_KEY` overrides config file

### Q3: Anthropic API base URL -- Can we use the secret proxy?

**NO, not without a source patch.** The `chatViaAnthropic()` function in `src/conway/inference.ts` hardcodes:

```typescript
const resp = await params.httpClient.request("https://api.anthropic.com/v1/messages", {
  method: "POST",
  headers: {
    "Content-Type": "application/json",
    "x-api-key": params.anthropicApiKey,
    "anthropic-version": "2023-06-01",
  },
  // ...
});
```

The URL `https://api.anthropic.com/v1/messages` is a string literal. There is no env var check, no config option, and no constructor parameter for the Anthropic base URL.

**Compare with OpenAI/Conway/Ollama backends:** These correctly use configurable URLs:
```typescript
const openAiLikeApiUrl =
  backend === "openai" ? "https://api.openai.com" :
  backend === "ollama" ? (ollamaBaseUrl as string).replace(/\/$/, "") :
  apiUrl;
```

**Resolution options (ordered by preference):**

1. **Patch `src/conway/inference.ts`** to read `ANTHROPIC_BASE_URL` env var:
   ```typescript
   const anthropicApiUrl = process.env.ANTHROPIC_BASE_URL || "https://api.anthropic.com";
   // Then use: `${anthropicApiUrl}/v1/messages`
   ```
   Also need to adjust header: when using proxy, use `x-api-key` with a placeholder key (the proxy injects the real key). The existing secret-proxy strips incoming `x-api-key` and injects the real one, so the placeholder value does not matter.

2. **Route Anthropic calls through Conway Compute API** instead of direct Anthropic -- set `inferenceModel` to a Claude model ID and rely on the Conway inference endpoint (which is OpenAI-compatible and uses the Conway API key). This requires Conway credits.

3. **Fork the secret proxy** to support the Anthropic message format natively (already done -- secret-proxy.nix forwards all methods to api.anthropic.com).

**Recommended: Option 1.** The patch is ~5 lines and enables `ANTHROPIC_BASE_URL=http://127.0.0.1:9091` with a placeholder `ANTHROPIC_API_KEY`. This exactly matches the existing `agent-compute.nix` pattern for claw-swap agents.

### Q4: Packaging for NixOS

**Build system:** pnpm 10.28.1 workspace with root package + `packages/cli/` sub-package.

**Critical details:**

| Property | Value |
|----------|-------|
| Package manager | pnpm 10.28.1 (via corepack) |
| Lockfile | `pnpm-lock.yaml` (64KB), also has minimal `package-lock.json` (757 bytes, typescript-only) |
| Entry point | `dist/index.js` (compiled from `src/index.ts`) |
| Build command | `tsc && pnpm -r build` |
| Node.js requirement | >= 20.0.0 |
| Native addons | `better-sqlite3` ^11.0.0 (C++ binding, requires node-gyp + Python + make) |
| Other notable deps | `viem` (large, pure JS), `openai` ^6.24.0, `siwe` ^2.3.0, `simple-git` |
| Build output | `dist/` directory (TypeScript compiled to ES2022 NodeNext modules) |
| Module type | ESM (`"type": "module"`) |

**Packaging approaches:**

**Option A: `buildNpmPackage` with converted lockfile (recommended)**
1. Convert `pnpm-lock.yaml` to `package-lock.json` using `pnpm import` (reverse direction) or generate npm lockfile
2. Use `buildNpmPackage` with the converted lockfile
3. Handle `better-sqlite3` native addon: `makeCacheWritable = true` + explicit `npm rebuild better-sqlite3` in buildPhase
4. Match existing claw-swap pattern

**Option B: `pnpm2nix` / `dream2nix`**
- `pnpm2nix` reads `pnpm-lock.yaml` directly
- Less proven in the neurosys codebase (no existing pnpm packages)
- May need `dream2nix` for better pnpm support

**Option C: Pre-built artifact (simplest, Docker-like)**
1. Clone repo, `pnpm install --frozen-lockfile && pnpm build` in a derivation
2. Copy `dist/` + `node_modules/` into the Nix store
3. Wrap with `pkgs.writeShellScriptBin` that sets `NODE_PATH` and runs `node dist/index.js`
4. Pros: avoids lockfile conversion complexity
5. Cons: larger closure, less reproducible

**Option D: OCI container (fallback)**
- Similar to spacebot.nix pattern
- Build a Docker image with the automaton and run via `virtualisation.oci-containers`
- Pros: simplest, no Nix packaging complexity
- Cons: doesn't match the "native NixOS service" goal of Phase 32

**Recommended: Option A** (consistent with claw-swap pattern). If lockfile conversion proves too painful, fall back to Option C.

**The `package-lock.json` in the repo is NOT usable** -- it only contains `typescript` as a dev dependency. The real dependency tree is in `pnpm-lock.yaml`. Must generate a proper npm lockfile or use pnpm-native tooling.

### Q5: Ports used

**The automaton does NOT expose any ports by default.** It is a CLI process that:
- Makes outbound HTTP requests (Conway API, Anthropic API, OpenAI API, Ollama, Base RPC for USDC)
- Uses a local SQLite database
- Runs a local git repo for state versioning

The only port-related functionality is `exposePort()` which calls Conway Cloud API to make sandbox ports publicly accessible. In local mode, this is a no-op that returns `http://localhost:<port>`.

**If the agent decides to run a web server** (e.g., an x402 API service), it would `exec("node server.js")` which runs on the host. Any such ports would need to be handled by the operator.

**For Phase 32:** No ports need to be opened or registered in `internalOnlyPorts`. The automaton is a headless background service making only outbound connections.

### Q6: Minimum configuration to run an agent

The `automaton.json` config file requires these fields (from `createConfig()` in `src/config.ts`):

```json
{
  "name": "my-agent",
  "genesisPrompt": "You are an autonomous agent on neurosys...",
  "creatorAddress": "0x<your-eth-address>",
  "registeredWithConway": false,
  "sandboxId": "",
  "conwayApiUrl": "https://api.conway.tech",
  "conwayApiKey": "",
  "anthropicApiKey": "<placeholder-or-real-key>",
  "inferenceModel": "claude-sonnet-4-6",
  "maxTokensPerTurn": 4096,
  "heartbeatConfigPath": "~/.automaton/heartbeat.yml",
  "dbPath": "~/.automaton/state.db",
  "logLevel": "info",
  "walletAddress": "0x<agent-wallet-address>",
  "version": "0.2.0",
  "skillsDir": "~/.automaton/skills",
  "maxChildren": 3,
  "treasuryPolicy": {
    "maxSingleTransferCents": 5000,
    "maxHourlyTransferCents": 10000,
    "maxDailyTransferCents": 50000,
    "minimumReserveCents": 5000,
    "maxX402PaymentCents": 500,
    "x402AllowedDomains": ["*"],
    "transferCooldownMs": 60000,
    "maxTransfersPerTurn": 3,
    "maxInferenceDailyCents": 5000,
    "requireConfirmationAboveCents": 1000
  }
}
```

**Additionally required files:**
- `~/.automaton/wallet.json` -- EVM private key (generated by `getWallet()`)
- `~/.automaton/heartbeat.yml` -- heartbeat schedule (generated by `writeDefaultHeartbeatConfig()`)
- `~/.automaton/SOUL.md` -- agent identity document (generated by setup wizard)
- `~/.automaton/constitution.md` -- immutable behavioral rules (copied from repo root)

**All of these can be pre-seeded** without running the interactive wizard. The wizard just fills in these files.

### Q7: Environment variables

The framework reads these environment variables (from source analysis):

| Variable | Used In | Purpose |
|----------|---------|---------|
| `HOME` | `identity/wallet.ts`, many | Base dir for `~/.automaton/` |
| `CONWAY_API_URL` | `index.ts --help`, `identity/provision.ts` | Override Conway API URL (default: `https://api.conway.tech`) |
| `CONWAY_API_KEY` | `index.ts --help` | Override Conway API key from config |
| `CONWAY_SANDBOX_ID` | `setup/environment.ts` | Mark as running in Conway sandbox |
| `OLLAMA_BASE_URL` | `index.ts` | Override Ollama URL from config |
| `SECRET_PROXY_PORT` | (not in automaton -- in neurosys secret-proxy) | Secret proxy listen port |

**NOT read from environment (only from config file):**
- `ANTHROPIC_API_KEY` -- only from `automaton.json` `anthropicApiKey` field
- `OPENAI_API_KEY` -- only from `automaton.json` `openaiApiKey` field

**This is a problem for the secret-proxy integration.** The standard neurosys pattern is `ANTHROPIC_BASE_URL` + `ANTHROPIC_API_KEY` env vars. The automaton reads these from its config file, not environment. Options:
1. Pre-seed `automaton.json` with the placeholder key and set `anthropicApiKey` field
2. Patch the source to also check env vars (recommended -- more flexible)

### Q8: Heartbeat network requirements

The heartbeat daemon runs these tasks on cron schedules:

| Task | Network? | External Service |
|------|----------|-----------------|
| `heartbeat_ping` | YES | Conway API (`getCreditsBalance`) -- cached from tick context |
| `check_credits` | YES | Conway API (`getCreditsBalance`) -- cached from tick context |
| `check_usdc_balance` | YES | Base RPC (public, `https://mainnet.base.org`) |
| `check_for_updates` | NO | Local git (`git fetch origin`) |
| `health_check` | YES (if sandbox) / NO (if local) | Conway API or local `echo alive` |
| `check_social_inbox` | YES (if configured) | Conway social relay |
| `soul_reflection` | NO | Local DB analysis |
| `refresh_models` | YES | Conway API / inference.conway.tech |
| `check_child_health` | YES | Conway API (sandbox health) |
| `report_metrics` | NO | Local metrics collection |

**Minimum network requirements:**
- Anthropic API (or proxy) for inference
- Base RPC node for USDC balance (optional, fails gracefully)
- Conway API for credits/sandbox management (optional, fails gracefully)

**Without Conway API key, all Conway-dependent heartbeats fail gracefully** -- they catch errors and return `{ shouldWake: false }`. The agent still operates.

### Q9: State directory layout

Default state directory: `~/.automaton/` (hardcoded in `src/identity/wallet.ts`):

```
~/.automaton/
  wallet.json          # EVM private key (generated once, never overwritten)
  config.json          # API key + wallet address (from provisioning)
  automaton.json       # Full agent configuration
  state.db             # SQLite database (turns, tools, heartbeats, memory, etc.)
  state.db-wal         # WAL journal
  state.db-shm         # Shared memory
  heartbeat.yml        # Heartbeat schedule configuration
  SOUL.md              # Agent identity/personality document
  constitution.md      # Immutable behavioral rules (read-only 0o444)
  skills/              # Skill definitions directory
    conway-compute/SKILL.md
    conway-payments/SKILL.md
    survival/SKILL.md
  .git/                # State versioning repo (tracks SOUL.md, heartbeat.yml, skills)
  .gitignore           # Excludes wallet.json, config.json, state.db, logs
```

**Can the state dir be moved?** Partially:
- `dbPath` is configurable in `automaton.json` (can point to `/var/lib/automaton/state.db`)
- `heartbeatConfigPath` is configurable in `automaton.json`
- `skillsDir` is configurable in `automaton.json`
- But `AUTOMATON_DIR` in `identity/wallet.ts` is hardcoded to `$HOME/.automaton/`
- The wallet and config files MUST be at `$HOME/.automaton/wallet.json` and `$HOME/.automaton/config.json`

**Recommended approach:** Set `HOME=/var/lib/automaton` for the systemd service. This makes `~/.automaton/` resolve to `/var/lib/automaton/.automaton/`. All state lives under `/var/lib/automaton/`.

### Q10: Node.js version requirement

**Node.js >= 20.0.0** (from `package.json` `engines` field).

CI tests against Node.js 20 and 22 (from `.github/workflows/ci.yml`).

TypeScript target is ES2022 with NodeNext module resolution.

NixOS 25.11 provides `nodejs_22` which satisfies this requirement.

---

## Architecture for Self-Hosted Automaton

### Proposed NixOS Integration

```
flake.nix
  inputs.automaton = { url = "github:Conway-Research/automaton"; flake = false; }

packages/automaton.nix     # buildNpmPackage or custom derivation
modules/automaton.nix      # systemd service definition
modules/secrets.nix        # Add conway-api-key secret (optional)
modules/networking.nix     # No changes needed (no ports exposed)
```

### Service Configuration

```nix
# modules/automaton.nix (sketch)
{ config, pkgs, ... }:
let
  automaton-pkg = pkgs.callPackage ../packages/automaton.nix {};
in {
  users.users.automaton = { isSystemUser = true; group = "automaton"; home = "/var/lib/automaton"; };
  users.groups.automaton = {};

  # Pre-seed state directory with activation script
  system.activationScripts.automaton-state = { ... };

  # Sops template for env file
  sops.templates."automaton-env" = {
    content = ''
      ANTHROPIC_API_KEY=${config.sops.placeholder."anthropic-api-key"}
      ANTHROPIC_BASE_URL=http://127.0.0.1:9091
    '';
    owner = "automaton";
  };

  systemd.services.conway-automaton = {
    description = "Conway Automaton agent runtime";
    after = [ "network-online.target" "anthropic-secret-proxy.service" "sops-nix.service" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      ExecStart = "${automaton-pkg}/bin/automaton --run";
      EnvironmentFile = config.sops.templates."automaton-env".path;
      User = "automaton";
      Group = "automaton";
      StateDirectory = "automaton";
      WorkingDirectory = "/var/lib/automaton";
      Environment = [ "HOME=/var/lib/automaton" "NODE_ENV=production" ];
      Restart = "on-failure";
      RestartSec = "30s";
      # Systemd hardening
      NoNewPrivileges = true;
      ProtectSystem = "strict";
      ReadWritePaths = [ "/var/lib/automaton" ];
    };
  };
}
```

---

## Risks and Mitigations

### Risk 1: pnpm packaging complexity (HIGH)

**Risk:** NixOS does not have a first-class `buildPnpmPackage`. The `package-lock.json` in the repo is a stub. Converting `pnpm-lock.yaml` to a usable npm lockfile may introduce dependency mismatches.

**Mitigations:**
- Use `pnpm deploy --prod` inside a Nix derivation to create a flat `node_modules` tree, then package the result
- Alternatively, use `npmConfigHook` with a generated `package-lock.json` from `pnpm import`
- Fallback: vendor `node_modules` as a fixed-output derivation with `fetchNpmDeps` on a generated lockfile
- Last resort: Docker container approach (like spacebot.nix)

### Risk 2: better-sqlite3 native compilation (MEDIUM)

**Risk:** `better-sqlite3` requires compiling a C++ addon with node-gyp. In Nix sandbox, this needs `python3`, `gcc`, `make`, and Node.js headers.

**Mitigations:**
- Known pattern: `buildNpmPackage` handles this with `makeCacheWritable = true` and explicit `npm rebuild better-sqlite3`
- Prior art in neurosys: MEMORY.md documents this exact pattern for claw-swap ("If code uses `better-sqlite3-multiple-ciphers`, you must `npm rebuild better-sqlite3-multiple-ciphers`")
- Nix provides `python3` and build tools via `nativeBuildInputs`

### Risk 3: Hardcoded Anthropic API URL (MEDIUM)

**Risk:** The Anthropic inference path hardcodes `https://api.anthropic.com/v1/messages`. Cannot use the existing neurosys secret proxy without a source patch.

**Mitigations:**
- Source patch in Nix `postPatch` phase: `sed -i 's|https://api.anthropic.com|${ANTHROPIC_BASE_URL:-https://api.anthropic.com}|' src/conway/inference.ts` (or cleaner: inject env var check)
- Alternatively, contribute the fix upstream (small, obviously useful)
- Alternatively, route all inference through Conway Compute (OpenAI-compatible endpoint, already configurable), but this requires Conway credits

### Risk 4: Survival tier deadlock (LOW)

**Risk:** Without Conway credits, the agent enters "dead" state after 1 hour (from `check_credits` task). Dead agents only check for funding every 5 minutes and use minimal compute.

**Mitigations:**
- Provide a Conway API key and fund the agent with credits (supports the self-sustaining design)
- OR patch `getSurvivalTier()` in `src/conway/credits.ts` to always return "normal" when `CONWAY_API_KEY` is empty (self-hosted mode override)
- OR set a large dummy credit balance in the DB at startup

### Risk 5: Interactive setup wizard (LOW)

**Risk:** `automaton --run` triggers the interactive setup wizard on first run if no config exists. This blocks in a systemd service.

**Mitigations:**
- Pre-seed all required files (`automaton.json`, `wallet.json`, `heartbeat.yml`, `SOUL.md`, `constitution.md`) via NixOS activation script
- The `loadConfig()` function returns the config from disk without wizard if files exist
- Generate `wallet.json` once via `automaton --init` during first deployment, then encrypt and store via sops

### Risk 6: Secret exposure -- agent wallet private key (LOW)

**Risk:** The EVM wallet private key at `~/.automaton/wallet.json` is a high-value secret if the agent holds real USDC.

**Mitigations:**
- Store wallet key in sops-nix and inject at activation time
- Set `0o600` permissions (already done by the framework)
- Systemd `ProtectHome=true` prevents other users from reading
- Amount risk is bounded by the funding amount

---

## Build Complexity Estimate

| Component | Effort | Notes |
|-----------|--------|-------|
| Nix package derivation | HIGH | pnpm lockfile conversion, better-sqlite3 native addon |
| Anthropic base URL patch | LOW | ~5 line patch in `src/conway/inference.ts` |
| NixOS module (systemd service) | MEDIUM | Follows secret-proxy.nix pattern, plus activation scripts for state seeding |
| State pre-seeding | MEDIUM | Generate wallet, config, heartbeat, SOUL.md, constitution.md |
| Secrets integration | LOW | Add automaton-env sops template, reuse existing anthropic-api-key |
| Networking changes | NONE | No ports exposed |
| Testing | MEDIUM | `nix flake check` + verify service starts and agent loop runs |

**Total estimated effort:** 2-3 planning iterations.

---

## Dependencies and Prerequisites

1. **Conway API key** (optional but recommended) -- provision via `automaton --provision` or create through Conway Cloud dashboard
2. **EVM wallet** -- generate once, store in sops
3. **Genesis prompt** -- user-provided agent personality/mission
4. **Creator Ethereum address** -- user's wallet address for ownership
5. **Anthropic API key** -- already exists in neurosys sops secrets (reuse via secret proxy)
6. **Node.js 22** -- already available in NixOS 25.11

---

## Existing Pattern Mapping

| Phase 32 Need | Existing Pattern | File |
|---------------|-----------------|------|
| TypeScript systemd service | anthropic-secret-proxy | `modules/secret-proxy.nix` |
| sops secret injection | spacebot env template | `modules/spacebot.nix` |
| State directory creation | spacebot tmpfiles rules | `modules/spacebot.nix` |
| Port protection assertion | internalOnlyPorts | `modules/networking.nix` |
| Secret proxy integration | claw-swap in agent-spawn | `modules/agent-compute.nix` |
| Flake input (non-flake repo) | `flake = false` input | (new, but standard Nix pattern) |
| Pre-built binary packaging | zmx.nix, cass.nix | `packages/zmx.nix` |
| Docker fallback | spacebot OCI container | `modules/spacebot.nix` |

---

## Decision Points for Planning

These require user input or explicit decisions before implementation:

1. **Packaging strategy:** `buildNpmPackage` with lockfile conversion vs. OCI container fallback? Recommend native build first, Docker fallback if packaging takes >1 day.

2. **Conway API key:** Will the agent have a Conway API key for credits/sandbox features, or run in pure self-hosted mode (inference-only)?

3. **Survival tier behavior:** Patch to always return "normal" in self-hosted mode, or fund with Conway credits for authentic survival pressure?

4. **Agent identity:** Pre-generate and sops-encrypt the wallet.json, or generate fresh on first boot and accept the bootstrapping complexity?

5. **Genesis prompt:** What is the agent's mission/personality? (User must provide or defer to planning phase.)

6. **Which host?** Deploy on neurosys (Contabo, 18 vCPU / 96 GB) or neurosys-prod (OVH)? Neurosys has more headroom.

7. **Inference model:** Use Anthropic Claude via secret proxy (free via BYOK), or Conway Compute (costs credits)?

8. **Number of agents:** Single agent MVP first, or multi-agent from the start? Recommend single agent first.

---

## Source References

All findings are from direct source code analysis of `https://github.com/Conway-Research/automaton` at `main` branch (commit as of 2026-02-25):

- `package.json` -- dependencies, build scripts, Node.js version requirement
- `src/config.ts` -- configuration loading, default values, config creation
- `src/types.ts` -- all type definitions, DEFAULT_CONFIG, DEFAULT_TREASURY_POLICY
- `src/index.ts` -- CLI entry point, run loop, signal handling
- `src/identity/wallet.ts` -- wallet generation, AUTOMATON_DIR constant
- `src/identity/provision.ts` -- SIWE-based API key provisioning
- `src/conway/client.ts` -- Conway API client, local mode fallback
- `src/conway/inference.ts` -- hardcoded Anthropic URL, provider routing
- `src/conway/x402.ts` -- USDC payments on Base
- `src/state/database.ts` -- SQLite schema, database operations
- `src/setup/wizard.ts` -- interactive setup wizard
- `src/setup/environment.ts` -- sandbox detection
- `src/setup/defaults.ts` -- SOUL.md generation, default skills
- `src/heartbeat/daemon.ts` -- heartbeat scheduler
- `src/heartbeat/config.ts` -- heartbeat YAML configuration
- `src/heartbeat/tasks.ts` -- all built-in heartbeat tasks
- `src/agent/loop.ts` -- core ReAct loop
- `src/agent/tools.ts` -- tool definitions
- `src/inference/router.ts` -- model selection and routing
- `src/observability/logger.ts` -- JSON structured logging to stdout
- `src/git/state-versioning.ts` -- git-based state versioning
- `src/survival/monitor.ts` -- resource monitoring
- `.github/workflows/ci.yml` -- CI build matrix (Node 20, 22)
- `pnpm-workspace.yaml` -- workspace definition
- `scripts/automaton.sh` -- install script
