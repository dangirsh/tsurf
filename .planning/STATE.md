# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-02-15)

**Core value:** One command to deploy a fully working development server with all services running, all tools installed, and all infrastructure repos cloned -- no manual setup steps.
**Current focus:** Phase 73 complete. Plan 73-02 added OVH live wrapper verification tests plus eval coverage for the audit tmpfiles rule. Next: Phase 72.1 planning/deploy validation.

## Current Position

Phase: 73 (OVH Agent Sandbox Enforcement) — COMPLETE
Plan: 73-02 — COMPLETE
Status: Plan 73-02 executed with 4 atomic commits (live BATS wrapper tests + eval audit-dir check + flake validation + docs/state updates). `nix flake check` passes including `agent-sandbox-ovh-enabled`, `agent-sandbox-module-has-bwrap`, and `agent-audit-dir`.
Last activity: 2026-03-11 - Phase 73-02 complete.

Progress: Phase 73 complete (2/2 plans, 73-01 and 73-02 complete). Phase 72 complete (3/3 plans). Phase 71 complete (2/2 plans). Phase 70 complete (3/3 plans). Phase 69 complete (3/3 plans). Phase 68 complete (3/3 plans). Phase 67 complete (1/1 plans). Phase 66 complete (3/3 plans). Phase 65 complete
(3/3 plans). Phase 64 complete (2/2 plans). Phase 63 complete (2/2 plans).
Phase 61 complete (2/2 plans). Phase 60 complete (2/2 plans). Phase 59
complete (2/2 plans). Phase 58 complete (1/1 plans). Phase 53 complete
(3/3 plans). Phase 51 plans 01-03 complete, plan 04 (validation) pending.
Phase 56 complete (research). Phase 57-01 complete (OVH rename).
Phase 57-02 pending.

## Performance Metrics

**Velocity:**
- Total plans completed: 41
- Average duration: ~19.6min
- Total execution time: ~784 min

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 1 | 2/2 | ~13min | ~6.5min |
| 2 | 1/2 | ~5min | ~5min |
| 3 | 2/2 | ~15min | ~7.5min |
| 3.1 | 3/3 | ~75min | ~25min |
| 4 | 2/2 | ~60min | ~30min |
| 5 | 2/2 | ~37min | ~18.5min |
| 6 | 2/2 | ~40min | ~20min |

| 10 | 2/2 | ~115min | ~57.5min |
| 14 | 2/2 | ~20min | ~10min |

| 16 | 2/2 | ~25min | ~12.5min |
| 17 | 4/4 | ~76min | ~19min |
| 19 | 1/1 | ~18min | ~18min |
| 20 | 1/1 | ~24min | ~24min |
| 25 | 1/1 | ~32min | ~32min |
| 21 | 1/2 | ~10min | ~10min |
| 27 | 2/5 | ~16min | ~8min |
| 28 | 2/4 | ~22min | ~11min |
| 37 | 3/3 | ~21min | ~7min |
| 39 | 1/2 | ~20min | ~20min |
| 40 | 1/2 | ~72min | ~72min |

| 60 | 2/2 | ~13min | ~6.5min |
| 63 | 2/2 | ~83min | ~41.5min |

**Recent Trend:**
- Last 4 plans: 66-03 (~8min), 66-02 (~3min), 66-01 (~53min), 65-03 (~5min)
- Trend: Work has shifted to proxy boundary hardening and modular NixOS integration.

*Updated after each plan completion*

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table.
Recent decisions affecting current work:

- [73-01]: SANDBOX-73-01: Added `modules/agent-sandbox.nix` with `services.agentSandbox.enable`; wrappers replace bare `claude`/`codex` via `meta.priority = 4` and enforce bubblewrap by default.
- [73-01]: SANDBOX-73-02: All wrapper launches append TSV audit records to `/data/projects/.agent-audit/agent-launches.log` (timestamp, user, pid, mode, workdir, binary, args).
- [73-01]: SANDBOX-73-03: `--no-sandbox` path requires `AGENT_ALLOW_NOSANDBOX=1`; otherwise wrapper exits 1. Secret-proxy env vars are only injected when `secretProxyPort` is configured.
- [73-02]: Added `tests/live/agent-sandbox.bats` with six OVH-only `${HOST}:` tests validating wrapper presence, bwrap reference, source-level mount exclusions, `--no-sandbox` rejection messaging, and audit-dir permissions.
- [73-02]: Added eval check `agent-audit-dir` in `tests/eval/config-checks.nix` to ensure `.agent-audit` tmpfiles rule remains declared in OVH config.

- [71-01]: README rewritten as canonical entry point for the API key placeholder substitution proxy pattern with explicit Stanislas Polu Netclode attribution.
- [71-01]: Added docs set: `architecture.md` (pattern, trust model, Netclode comparison), `deployment-nixos.md`, `deployment-docker.md`, and `deployment-systemd.md`.
- [71-01]: Standardized placeholder guidance on `sk-ant-api03-placeholder` for Anthropic SDK compatibility and documented Docker host-network workaround for loopback bind.
- [71-02]: Added `docs/known-issues.md` with 12 code-verified entries (2 BLOCKING, 4 DEGRADED, 6 INFORMATIONAL) and explicit Phase 72 mitigation queue.

- [69-01]: Per-host repo lists: OVH gets 13 dev repos (10 standard + 3 custom-target), Contabo gets 4 service repos. `repos.nix` removed from `commonModules`.
- [69-01]: `services.secretProxy.services.dev` declared in `ovhModules` (port 9091) for sandboxed agent API key injection on dev host.
- [69-01]: Activation script `clone-repos` depends on `setupSecrets` (not just `users`) so sops-decrypted `github-pat` is available at clone time.
- [69-02]: deploy.sh supports `--node all` for parallel deployment of both hosts with independent processes and per-node log files.
- [69-02]: OVH deploy health checks include `secret-proxy-dev` alongside `syncthing` and `tailscaled`.
- [69-03]: Eval checks added: `secret-proxy-dev-service`, `ovh-clone-repos`, `secret-proxy-dev-user`, `ovh-no-agentd` (locked decision: no agentd on OVH).

- [68-01]: Extracted secret-proxy crate into standalone repo `/data/projects/nix-secret-proxy` with independent git history and root-level Cargo/Nix files.
- [68-01]: Standalone package derivation uses `src = ./.` and `cargoLock.lockFile = ./Cargo.lock` so flake root is crate root.
- [68-01]: Standalone module adds `services.secretProxy.package` (default `pkgs.callPackage ./package.nix {}`) and sets `secretProxyPkg = cfg.package` for downstream overrides.
- [68-01]: Standalone flake exports `packages`, `nixosModules.default`, and `overlays.default`; `nix build /data/projects/nix-secret-proxy#secret-proxy --no-link` passes.

- [66-02]: Rewrote `modules/secret-proxy.nix` into a generic `services.secretProxy.services` attrsOf submodule with per-service users, units, and read-only `bwrapArgs`.
- [66-02]: Per-service TOML config is generated as a Nix store path via `pkgs.writeText`; runtime secrets remain file-backed via `secretFile` paths.
- [66-02]: Removed hardcoded `internalOnlyPorts."9091"` mapping; proxy ports are loopback-only and duplicate-port validation now lives in module assertions.
- [66-03]: Private overlay now declares `services.secretProxy.services.claw-swap` (port `9091`) with `config.sops.secrets."anthropic-api-key".path` as `secretFile`.
- [66-03]: `anthropic-api-key` remains owned by `dangirsh` while adding `group = "secret-proxy"` and `mode = "0440"` so `secret-proxy-claw-swap` can read it safely.
- [66-03]: Public eval suite gained `has-secret-proxy-option`; private eval suite gained `secret-proxy-claw-swap-service`; legacy private `anthropic-secret-proxy` references were migrated to `secret-proxy-claw-swap`.
- [66-01]: Built new Rust `secret-proxy` binary (`axum` + `reqwest`) with plain HTTP localhost ingress and HTTPS upstream forwarding.
- [66-01]: Upstream destination is fixed to `allowed_domains[0]` for the matched secret; incoming `Host` must match that secret's allowlist or request is denied with HTTP 403.
- [66-01]: [Rule 3 - Blocking] Nix package needed `pkg-config` + `openssl` build inputs to satisfy `openssl-sys` during `nix build`.

- [65-01]: Moved 4 personal modules (automaton, matrix, openclaw, dm-guide) and 4 package files to private overlay. Import paths rewritten from `${inputs.neurosys}/modules/...` to local `./modules/...`.
- [65-02]: Stripped personal service references from all core modules: 13 impermanence paths, 12 internalOnlyPorts entries, 10 secret declarations, 2 package exports, 1 eval check removed from public repo. All moved to private overlay.
- [65-02]: Private overlay gets `impermanence-private.nix` (13 persist paths), expanded `secrets-contabo.nix` (6 openclaw tokens + cloudflare + matrix), and emptied `secrets-ovh-overrides.nix`.
- [65-03]: README updated with 14-module table, 5 example use cases, core-only networking table, removed nixosModules.default reference.

- [58-01]: CANVAS-01/02/03: Added `services.agentCanvas` module with
  stdlib-only `writePython3Bin` server, DynamicUser+StateDirectory
  service model, and network-layer-only access policy (internal/Tailscale).
- [58-01]: Implemented panel APIs (`POST/GET/PATCH/DELETE /api/panels`,
  `GET /api/panels/{id}`, `POST /api/panels/{id}/data`) plus `GET
  /api/events` SSE for `panel-created`, `panel-updated`, `panel-deleted`.
- [58-01]: Integrated canvas into neurosys host and safety checks:
  `internalOnlyPorts."8083" = "agent-canvas"`, dashboard entry
  `services.dashboard.entries.canvas`, and eval check `canvas-enabled`.

- [63-01]: MCP-63-01/02/03: Added `google_auth.py` using `google-auth` + `httpx`, with env-driven config, `/google/auth` + `/google/callback`, and persisted tokens at `/var/lib/neurosys-mcp/google-tokens.json` with auto-refresh.
- [63-01]: MCP-63-04/05: Added `gmail.py` register pattern with five Gmail MCP tools and centralized auth gate; tools return `{\"ok\": false, \"error\": \"google_auth_required\"}` when OAuth is missing/invalid.
- [63-01]: MCP-63-06: `server.py` now composes Starlette routes for Google OAuth only when Google OAuth env vars are configured; otherwise falls back to plain `mcp.run(streamable-http)`.
- [63-01]: [Rule 3 - Blocking] `nix build .#neurosys-mcp` initially failed because `google.auth.transport.requests` requires `requests`; fixed by adding `requests` to `pyproject.toml` and `python3Packages.requests` to `packages/neurosys-mcp.nix`.
- [63-02]: CAL-01/02/03: Added `calendar_tools.py` using `httpx` + shared bearer-token auth path from `google_auth`; scope intentionally limited to the primary calendar; module named to avoid stdlib shadowing.
- [63-02]: Added six Calendar MCP tools (`calendar_list`, `calendar_search`, `calendar_free_busy`, `calendar_create`, `calendar_update`, `calendar_delete`) with shared auth-gate behavior returning `{\"ok\": false, \"error\": \"google_auth_required\"}` when OAuth tokens are unavailable/expired.
- [63-02]: Updated package metadata and checks for Calendar support (`pyproject` module list/version/description, Nix `pythonImportsCheck`, package version `0.3.0`), validated via `nix build .#neurosys-mcp` and `nix flake check`.
- [60-01]: MTX-06: Enabled provisioning API fields for WhatsApp/Signal/Telegram in public matrix module with placeholder `shared_secret = "disable"` for private overlay override.
- [60-01]: MTX-07: Chose a single shared provisioning secret for all three bridges in this internal-only MVP.
- [60-01]: DMG-01: Added standalone `dm-guide` Python stdlib server on port 8086 with in-module HTML UI and client-side QR rendering.
- [60-01]: [Rule 3 - Blocking] Added encrypted `dm-provisioning-secret` key to `secrets/neurosys.yaml` so sops manifest validation passes during `nix flake check`.
- [60-02]: DMG-05: Added backup import pipeline to dm-guide with local-only processing and JSON output in `/var/lib/dm-guide/imports`.
- [60-02]: Manual multipart boundary parser implemented using Python stdlib (no `cgi.FieldStorage`) for Python 3.13 compatibility.
- [60-02]: Signal decrypt path uses `${pkgs.signalbackup-tools}/bin/signalbackup-tools` with 300s timeout and graceful missing-binary handling.
- [59-02]: LOGSEQ-04: Vault path hardcoded to `/home/dangirsh/Sync/logseq` in private overlay (user-confirmed Syncthing location; stable, single vault on server).
- [59-02]: LOGSEQ-05: `ProtectHome = "read-only"` required (not `true`) — `true` makes /home fully inaccessible even with ReadOnlyPaths; "read-only" allows listed paths while keeping rest of /home read-only.
- [59-02]: logseq-agent-suite repo (dangirsh/logseq-agent-suite, private) created with triage/graph-maintenance/review instruction files. Cloned to /data/projects on activation.
- [59-01]: LOGSEQ-01: Selected `orgparse` for Logseq org-mode parsing in `neurosys-mcp`; extracts TODO state/tags/properties/timestamps and file tree traversal, with `#+title`/`#+tags` parsed via regex from root body.
- [59-01]: LOGSEQ-02: Scope is read-only for initial rollout (`logseq_get_todos`, `logseq_search_pages`, `logseq_get_page`); write/mutation tools deferred to a later phase.
- [59-01]: LOGSEQ-03: Logseq vault path is configured through `LOGSEQ_VAULT_PATH`; tools return structured `ok=false` errors when unset or invalid.
- [52-01]: OpenClaw public runtime moved from `virtualisation.oci-containers` to six native `systemd.services` (`openclaw-mark` .. `openclaw-tal-claw`) with per-instance users and env template ownership (`owner = openclaw-<name>`).
- [52-01]: OpenClaw packaged from npm registry tarball (`openclaw@2026.3.1`) with pinned source hash + npm deps hash; flake now exports `packages.x86_64-linux.openclaw`.
- [52-01]: Docker service no longer required by public neurosys eval checks; dedicated `openclaw-services-neurosys` check added; trusted-interface check now supports both docker-enabled and docker-disabled hosts.
- [52-02]: Private overlay migrated `openclaw-auto-approve` from `docker exec` to direct `${openclaw-pkg}/bin/openclaw` calls using per-instance ws ports (`:18793`, `:18794`) and native `openclaw-*.service` ordering.
- [52-02]: Homepage OpenClaw widgets now use siteMonitor-only health (no Docker container status keys), while Spacebot Docker widget + homepage docker socket/group access remain intentionally enabled.
- [52-02]: Private eval checks replaced OpenClaw container assertions with native `systemd.services` and per-instance user checks; Spacebot container assertion retained.
- [57-01]: OVH/public hostname standardized from `neurosys-prod` to `neurosys-dev` in host config, deploy node, bootstrap/deploy scripts, test helpers, and docs. `test-live` CLI selector and `is_ovh()` predicate updated to match.
- [56-01]: VOICE-56-01: LiveKit Agents + Anthropic Plugin recommended as primary voice interface for neurosys HA control. Ranked top 3: (1) LiveKit Agents — self-hosted WebRTC, localhost HA API, 900-1400ms TTFB, (2) Pipecat+Daily — SaaS WebRTC transport, same pipeline quality, (3) Vapi — lowest complexity but internet-routed tool calls add 200-400ms each. Claude App+MCP is blocked (Anthropic-side). ClawdTalk/Telnyx is supplementary (PSTN UX mismatch). No Anthropic Realtime API exists. STT: Deepgram Nova-3, TTS: Cartesia Sonic-3. Phase 57 skeleton: 2 plans (infra + app), ~4-6 days.
- [37-01]: Public flake now exports `nixosModules.default` and removes private inputs/services from default imports.
- [37-01]: Username, SSH keys, and git identity are sanitized to template-safe placeholders (`myuser`, placeholder key comments, generic name/email).
- [37-01]: Private service bindings moved behind private overlay boundaries; public config passes `nix flake check` without private-module assumptions.
- [37-02]: Private overlay pattern documented in docs/private-overlay.md — complete flake.nix skeleton using nixosModules.default as base layer with follows pins.
- [37-03]: README rewritten from 391→98 lines; agent tooling is primary differentiator; all personal identifiers removed.
- [38-01]: `modules/default.nix` now exports only shared modules; host-specific `homepage`/`restic` and `repos` imports moved to `hosts/*/default.nix`.
- [38-01]: `scripts/deploy.sh` service health checks are node-conditional (`neurosys`: parts/postgresql/claw-swap; `ovh`: prometheus/syncthing/tailscaled).
- [38-01]: Parts update/revision and Cachix push paths are guarded for neurosys-only deploys; OVH deploys no longer touch parts-specific logic.
- [40-01]: Public flake now includes `agentd` input (`github:dangirsh/agentd`) and overlay; lock pinned to fork commit with configurable `-agent-user` flag.
- [40-01]: Added `modules/agentd.nix` with `services.agentd.agents` schema, jcard rendering, per-agent bwrap `agent` wrapper generation, and `agentd-<name>` / `agentd-proxy-<name>` systemd service generation.
- [40-01]: Shared `sops.templates."agentd-env"` now renders only `ANTHROPIC_API_KEY`; public repo keeps `services.agentd.agents = {}` (no live agents) for cross-host-safe evaluation.

- [06-01]: Syncthing GUI binds 0.0.0.0:8384, restricted via trustedInterfaces (not IP binding)
- [06-01]: allowUnfreePredicate for claude-code added to base.nix (pre-existing Phase 5 issue)
- [06-02]: CASS v0.1.64 binary via fetchurl + autoPatchelfHook
- [06-02]: Repo cloning is clone-only (never pull/update) to protect dirty working trees
- [06-02]: mkOutOfStoreSymlink for whole-directory ~/.claude and ~/.codex symlinks
- [Phase quick-001]: Use fetchurl of pre-built zmx static binary instead of flake input (zig2nix bwrap incompatible with apparmor)
- [10-01]: Manual deploy only — no CI/CD, NixOS handles incrementality
- [10-01]: Full nixos-rebuild switch every deploy — no partial/container-only path
- [10-01]: Container health polling (30s) — no app-level health checks
- [10-01]: No auto-commit of flake.lock — print reminder instead
- [10-02]: Port 22 must NOT be in allowedTCPPorts; SSH is Tailscale-only via trustedInterfaces + assertion
- [10-02]: PermitRootLogin = prohibit-password required for nixos-rebuild --target-host
- [10-02]: Root authorized keys managed in users.nix
- [11-01]: agent-spawn defaults to bubblewrap sandbox; --no-sandbox is explicit bypass
- [11-01]: Podman enabled with dockerCompat=false (conflicts with Docker); sandbox-local docker→podman symlink instead
- [11-01]: Metadata endpoint 169.254.169.254 blocked in nftables output chain
- [11-01]: API keys are read pre-sandbox from sops secret files and injected via env vars
- [11-02]: NIX_REMOTE=daemon required inside sandbox (user namespace blocks direct store access)
- [11-02]: daemon-socket needs rw bind (Unix socket connection requires write permission)
- [11-02]: zmx binary must be extracted from tarball (dontUnpack was installing gzip as binary)
- [11-02]: Audit log dir pre-created via systemd.tmpfiles (dangirsh can't write to root-owned /data/projects)
- [quick-002]: Home Assistant as native NixOS service, not Docker (HA-01)
- [quick-002]: HA GUI accessible via Tailscale only, same trustedInterfaces pattern as Syncthing (HA-02)
- [13-01]: ntfy ADOPTED — foundational notification layer (Android push urgent, email non-urgent)
- [13-01]: Prometheus+Grafana ADOPTED — minimal monitoring stack, Tailscale-only dashboards
- [13-01]: CrowdSec ADOPTED — collaborative sharing enabled, for public-facing services (claw-swap)
- [13-01]: Agent Teams ADOPTED — env var config change, quick task
- [13-01]: MCP-NixOS EVALUATE — local .mcp.json only, test and remove if noisy
- [13-01]: TKA (Tailnet Key Authority) ADOPTED — self-custody Tailscale signing keys, quick task
- [13-01]: Uptime Kuma DEFERRED — Grafana covers status dashboards
- [13-01]: endlessh-go REJECTED — minimal value with Tailscale-primary SSH
- [13-01]: Headscale REJECTED — TKA covers key sovereignty concern
- [13-01]: Caddy, Authelia, Loki+Alloy DEFERRED — not needed until services are internet-facing or specific log search needs arise
- [14-01]: Monitoring baseline implemented with Prometheus 15s scrape + 90d retention and node_exporter collectors (systemd/processes/tcpstat)
- [14-01]: Alert routing standardized as Alertmanager -> alertmanager-ntfy -> local ntfy topic `alerts`
- [14-01]: Grafana credentials sourced from sops secrets via file provider (not hardcoded in Nix store)
- [14-02]: Deploy notifications run from local deploy script via SSH + server-local ntfy POST to `deploys`
- [14-02]: Deploy notification delivery is best-effort (`|| true`) so ntfy outages cannot break deploy pipeline
- [14-02]: Generic server-side `scripts/notify.sh` introduced for reusable notifications (agents, cron, future restic hooks)
- [quick-005]: MON-05: Alertmanager, ntfy, Grafana removed -- agents query Prometheus /api/v1/alerts directly
- [quick-005]: fail2ban reverts to default ban action (no ntfy notification)
- [quick-006]: ESPHome binds 0.0.0.0:6052 with openFirewall=false (Tailscale-only, same pattern as HA and Syncthing)
- [34-01]: HA-04: Home Assistant trusts localhost proxy headers (`use_x_forwarded_for = true`, `trusted_proxies = [ "127.0.0.1" ]`) for Tailscale Serve reverse proxying.
- [34-01]: HA-05: `systemd.services.tailscale-serve-ha` declaratively applies `tailscale serve --bg --https=443 http://127.0.0.1:8123` with readiness wait on `BackendState == "Running"`.
- [17-01]: zmx removed from base module and kept in agent-compute package set; duplicate package declaration eliminated
- [17-01]: git-lfs and podman-compose removed as unused features/packages
- [17-01]: stale `parts-agent@vm` SSH key removed from `dangirsh` and `root` authorized keys
- [17-01]: deploy local lock moved from `/tmp` to project-local `tmp/` path
- [17-01]: kernel sysctl hardening enabled (dmesg/kptr restrictions, unprivileged bpf off, redirects off, martian logging on)
- [17-01]: homepage Tailscale IP centralized in a single `let` binding for one-line updates
- [17-01]: `llm-agents.inputs.nixpkgs` now follows root `nixpkgs`; lock update and flake checks passed
- [17-02]: Port 22 removed from public firewall; SSH accessible only via Tailscale (trustedInterfaces)
- [17-02]: Build-time assertion prevents port 22 from being re-added to allowedTCPPorts
- [17-02]: Repo cloning uses git credential.helper store (no PAT in URLs, process args, or .git/config)
- [17-02]: .git/config added to restic excludes to prevent backing up leaked tokens
- [17-03]: CLAUDE.md updated with Security Conventions, Simplicity Conventions, Module Change Checklist
- [17-03]: Accepted Risks documented: SEC3, SEC5, SEC9, SEC11
- [17-04]: Docker audit: claw-swap fully hardened, parts containers lack all hardening (tracked for remediation)
- [17-04]: Sandbox escape vectors confirmed and documented (SEC5 settings.json, SEC6 Docker socket, cross-project read, no network sandbox)
- [17-04]: Audit log gets journald dual-logging via systemd-cat for tamper resistance
- [16-01]: RESTIC-04: Back up SSH host key (sops-nix age chain), Docker bind mounts (/var/lib/claw-swap, /var/lib/parts), Tailscale state (/var/lib/tailscale); pg_dumpall pre-hook for PostgreSQL consistency
- [16-01]: Deploy SSH uses Tailscale MagicDNS (`root@neurosys`) with public port 22 closed
- [16-02]: Recovery runbook at docs/recovery-runbook.md — 4-phase flow, RTO < 2hr, RPO 24hr
- [19-01]: README.md finalized as single operator entry point; overview/deploy sections tightened for first-time deploy readability
- [19-01]: Design decision and accepted-risk tables constrained to source-grounded IDs; stale-content checks and source cross-validation rerun clean
- [19-01]: Added deploy-script decision rows and explicit 7-input flake validation note in README after checklist verification
- [25-01]: Deploy activation moved from `nixos-rebuild` to pinned `nix run .#deploy-rs` with flake-level `deploy.nodes.neurosys`
- [25-01]: Magic rollback enabled by default with `confirmTimeout = 120`; explicit `--first-deploy` and `--no-magic-rollback` bypass flags added
- [25-01]: Existing local+remote deploy locking and post-deploy container health polling retained around deploy-rs
- [21-01]: IMP-01: BTRFS subvolume rollback (not tmpfs) -- server workloads need disk-backed root
- [21-01]: IMP-02: Docker on own @docker subvolume (not impermanence bind-mount) -- avoids overlay2 nested mount conflicts
- [21-01]: IMP-03: Persist whole /home/dangirsh (not per-file) -- simpler for server, covers Syncthing data + config
- [21-01]: IMP-04: /var/lib/private covers DynamicUser services (ESPHome, future services)
- [21-01]: RESTIC-05 updated: Back up /persist subvolume instead of blanket / with --one-file-system
- [24-01]: srvos server module imported first; host overrides force `networking.useNetworkd = false` and `boot.initrd.systemd.enable = false`, with docs + command-not-found enabled.
- [24-01]: agent-spawn bubblewrap now unshares PID and cgroup namespaces to hide host process/cgroup visibility from sandboxes.
- [24-01]: treefmt-nix formatter and devShell tooling added; formatting enforcement in `checks` deferred to avoid large unrelated repo-wide churn this phase.
- [27-01]: OVH recon confirmed `/dev/sda`, `ens3`, DHCP `/32` (`135.125.196.143/32`) with gateway `135.125.196.1`, and BIOS boot mode.
- [27-01]: Generated pre-deploy OVH SSH host key and derived `host_ovh` age recipient (`age1rkve23z2ywug6ugwdcrtcpemq7j9y2980azveanhx0x6w3etp9eqn50l9g`) for sops-nix bootstrap.
- [27-01]: `.sops.yaml` now has per-host creation rules for both `secrets/neurosys.yaml` and `secrets/ovh.yaml` with `admin + host` recipient scoping.
- [27-01]: `secrets/ovh.yaml` mirrors neurosys secret schema; `tailscale-authkey` is intentionally a replace-before-deploy placeholder.
- [27-01]: Prepared `tmp/ovh-host-keys/persist/etc/ssh/ssh_host_ed25519_key` for nixos-anywhere `--extra-files` injection into impermanence-backed `/persist/etc/ssh`.
- [27-02]: Added `mkHost` + `commonModules` in `flake.nix` and split host evaluation to `nixosConfigurations.neurosys` and `nixosConfigurations.ovh` without double-importing `./modules`.
- [27-02]: Added `deploy.nodes.ovh` (`hostname = neurosys-prod`) alongside existing neurosys node for deploy-rs multi-target activation.
- [27-02]: Moved host-specific values out of shared modules (`sops.defaultSopsFile`, NAT external interface, GRUB device, homepage host identity) into host defaults.
- [27-02]: `scripts/deploy.sh` now supports `--node` (`neurosys` default, `ovh` optional) with node-aware default SSH target/lock paths and flake selector (`$FLAKE_DIR#$NODE`).
- [28-01]: External `dangirsh-site` migrated from pinned `default.nix` (`nixpkgs-20.03`) to flake pinned to `nixos-25.11`, exposing `packages.x86_64-linux.default` for neurosys nginx root consumption.
- [28-01]: `generator/site.cabal` `pandoc` bound widened from `< 3.6` to `< 3.8` to match nixos-25.11 `haskellPackages.pandoc` (`3.7.0.2`) while keeping `hakyll` bound unchanged (`4.16.x` compatible).
- [28-01]: Verified `nix build` output includes full `_site` artifact set (`index.html`, `css/`, `posts/`, static directories) and pushed upstream as `dangirsh/dangirsh.org@c309419`.
- [28-02]: Added `dangirsh-site` input to neurosys flake and introduced `modules/nginx.nix` with ACME-backed virtualHosts for `dangirsh.org`, `www.dangirsh.org`, and `claw-swap.com`.
- [28-02]: Enforced HOST-01 by importing nginx only in `hosts/ovh/default.nix`; verified `services.nginx.enable` evaluates `true` for OVH and `false` for neurosys.
- [28-02]: Removed Docker Caddy from `claw-swap` module and secrets; `claw-swap-app` now binds `127.0.0.1:3000:3000` for host nginx proxying (pushed `claw-swap@e3289f4`).
- [28-02]: Persisted `/var/lib/acme` for impermanence, updated homepage metadata (`nginx` + `dangirsh.org`), and added `dangirsh/dangirsh.org` to repo bootstrap list.
- [28-02]: [Rule 3 - Blocking] Resolved existing OVH `services.openssh.openFirewall` conflict by using `lib.mkForce true`, unblocking `nix flake check`.
- [22-01]: PROXY-22-01: `ANTHROPIC_BASE_URL` approach (not HTTP_PROXY/TLS MITM) — SDK makes plain HTTP to proxy; proxy speaks HTTPS upstream; no cert injection needed
- [22-01]: PROXY-22-02: `x-api-key` header injection (not `Authorization: Bearer`) — Anthropic API only accepts `sk-ant-api03-*` via `x-api-key`
- [22-01]: PROXY-22-03: `pkgs.writers.writePython3Bin` runs flake8 with PEP8 enforcement (E501 79-char, E305 2-blank-lines) — Python must be formatted
- [22-01]: PROXY-22-04: `socketserver.ThreadingTCPServer.allow_reuse_address = True` required to survive NixOS service restart race (EADDRINUSE on deploy)
- [22-01]: PROXY-22-05: `.strip()` on API key from sops template EnvironmentFile — trailing newlines cause 401
- [22-01]: PROXY-22-06: Keep `Content-Length` in response pass-through; only strip `Transfer-Encoding` + `Connection` — stripping Content-Length causes HTTP/1.1 clients to hang
- [30-01]: Claw-swap runtime migrated from oci-containers to native services (`services.postgresql` + `systemd.services.claw-swap-app`) with sops `EnvironmentFile` injection.
- [30-01]: PostgreSQL auth for claw-swap uses Unix socket trust (`local claw_swap claw trust`) because OS user `claw-swap` and DB role `claw` do not satisfy peer auth username matching.
- [30-01]: Added encrypted placeholder `google-api-key` and `xai-api-key` entries in both `secrets/neurosys.yaml` and `secrets/ovh.yaml` to satisfy sops manifest validation during `nix flake check`.
- [32-01]: Added non-flake `automaton` input (`github:Conway-Research/automaton`) and exported `packages.x86_64-linux.automaton` from repo `flake.nix`.
- [32-01]: Packaged Conway Automaton with `buildNpmPackage` + vendored converted lockfile (`packages/automaton-package-lock.json`) and fixed `npmDepsHash`.
- [32-01]: Patched `src/conway/inference.ts` endpoint to use `ANTHROPIC_BASE_URL` and forced native `better-sqlite3` compile via `npm rebuild better-sqlite3`.
- [32-02]: Created `modules/automaton.nix` with dedicated `automaton` system user, activation pre-seeding (automaton.json, wallet, heartbeat.yml, SOUL.md, constitution.md, git init), `conway-automaton` systemd service (NOT wantedBy — user must enable manually after API key provisioning).
- [32-02]: `sops.secrets."conway-api-key"` with explicit `sopsFile = ../secrets/neurosys.yaml` (avoids OVH eval failure); `sops.templates."automaton-env"` for BYOK proxy env vars.
- [32-02]: Service configured with `ProtectSystem = strict`, `ReadWritePaths = ["/var/lib/automaton"]`, `ANTHROPIC_BASE_URL=http://127.0.0.1:9091` for existing secret proxy on port 9091.
- [35-01]: Added `modules/matrix.nix` with Conduit (`services.matrix-conduit`) + mautrix-telegram (`services.mautrix-telegram`) using private `server_name = "neurosys.local"` and federation disabled.
- [35-01]: Added Matrix secrets (`telegram-api-id`, `telegram-api-hash`, `matrix-registration-token`) with explicit `lib.mkForce sopsFile = ../secrets/neurosys.yaml` to override upstream `parts` secret definitions and avoid OVH eval conflicts.
- [35-01]: Added internal-only ports `6167`, `29317`, `29318`, `29328`; persisted `/var/lib/mautrix-telegram`; allowlisted `olm-3.2.16` narrowly for neurosys Matrix stack to pass nixpkgs insecure-package gate.
- [35-02]: Enabled `services.mautrix-whatsapp` (Go bridge, WA Web protocol) on appservice port `29318` with sqlite URI `sqlite:////var/lib/mautrix-whatsapp/mautrix-whatsapp.db`.
- [35-02]: Enabled `services.mautrix-signal` (Go bridge, signal-cli backend) on appservice port `29328` with sqlite URI `sqlite:////var/lib/mautrix-signal/mautrix-signal.db`; set `MemoryDenyWriteExecute = false` for libsignal JIT.
- [35-02]: Added MTX-03/MTX-04/MTX-05 decision annotations and persisted `/var/lib/mautrix-whatsapp` + `/var/lib/mautrix-signal` in impermanence.
- [39-01]: DASH-08/09/10 implemented by creating standalone private repo `dangirsh/conway-dashboard` (`flake = false` target) for Conway dashboard app code.
- [39-01]: Dashboard server uses Python stdlib only on port 9093; `/api/status` aggregates SQLite state (`kv`, `turns`, `inference_costs`, `goals`, `task_graph`, `tool_calls`, `identity`) with graceful per-query degradation.
- [39-01]: Dashboard UI is a single self-contained HTML file polling `/api/status` every 5 seconds with status-color mapping, financial/activity panels, recent tool calls, and journald log view.
- [44]: Phase 44 added — Android CO2 alert via HA automation in home-assistant-config. Trigger: `sensor.apollo_air_1_5221b0_co2 > 1000 ppm`, notify Pixel 10 Pro, 30min cooldown, recovery notification on drop below 900 ppm. Single plan (44-01).
- [44-01]: Task A complete — appended `co2_alert_high` and `co2_alert_recovery` to `/data/projects/home-assistant-config/automations.yaml` and validated syntax with `python3 -c "import yaml; yaml.safe_load(open('automations.yaml'))"`.
- [44-01]: Task B complete — pushed `home-assistant-config` commit `4c3679a` to `origin/main`; updated `.claude/.test-status` to `pass|0|<epoch>` for neurosys no-Nix-change gate.
- [45-01]: MCP server source (`src/neurosys-mcp/server.py`) with 5 HA tools (get_states, get_state, call_service, list_services, search_entities) using FastMCP Streamable HTTP transport, packaged via `packages/neurosys-mcp.nix` with pinned PyPI hashes. Port 8400 in internalOnlyPorts.
- [45-02]: MCP-05: Localhost-only binding (127.0.0.1:8400); public access via Tailscale Funnel on port 8443 (MCP-11). OAuth 2.1 via `NeurosysOAuthProvider` subclass with HTML login form. 5 Matrix tools with graceful degradation. Private overlay NixOS module with DynamicUser + ProtectSystem=strict (MCP-06), sops EnvironmentFile for all secrets (MCP-07).
- [47-01]: SEC47-01: Port 22 public SSH is deliberate for bootstrap/recovery, not temporary. NET-01 annotation updated.
- [47-01]: SEC47-08: Mosh removed — programs.mosh.enable deleted, closing UDP 60000-61000.
- [47-01]: NET-10/NET-11/NET-12/NET-13: @decision annotations for all public ports and SSH hardening.
- [47-02]: SEC47-13: --no-sandbox agent = effective root. Documented as inherent design tradeoff.
- [47-02]: Systemd hardening added to secret-proxy (16 directives), Prometheus, node-exporter, tailscale-serve-ha.
- [47-03]: SEC47-34: On-demand API key loading via load-api-keys shell function. GH_TOKEN stays auto-loaded.
- [47-03]: SEC47-18: wget removed from system packages.
- [47-03]: SEC47-21: Syncthing insecureSkipHostcheck set to false (Docker bridge comment was outdated).
- [47-03]: SEC47-15: Cross-project read access documented in agentd.nix as deliberate.
- [48-01]: TEST-48-01: Two-layer test strategy adopted — offline Nix eval checks + live SSH BATS suites.
- [48-01]: Added 20 eval checks (`tests/eval/config-checks.nix`) wired into `checks.x86_64-linux` with deploy-rs checks preserved.
- [48-01]: Added flake `packages.test-live` and `apps.test-live` entry point (`nix run .#test-live -- neurosys|ovh`) with BATS runtime deps.
- [48-01]: Added `scripts/run-tests.sh` for eval/live orchestration and `.claude/.test-status` pass/fail stamping.
- [48-02]: Added 5 deep live suites (`agentd`, `monitoring`, `impermanence`, `sandbox`, `networking`) for 25 additional host-runtime assertions.
- [48-02]: `scripts/run-tests.sh --json` emits one JSON object per TAP test (`name`, `status`, `error`) for agent-parseable failure handling.
- [48-02]: Added `.github/workflows/test.yml` to run `nix flake check` and `nix build .#test-live` on push/PR without SSH live tests.
- [48-02]: Expanded flake shellcheck check to include `scripts/run-tests.sh` and all live BATS files (BATS lint non-blocking).
- [48-02]: Documented private overlay test extension pattern in `tests/eval/config-checks.nix` and `CLAUDE.md`.
- [49-01]: SEC49-01: Bootstrap passwords in git history accepted as minimal risk (ephemeral, Ubuntu wiped by nixos-anywhere).
- [49-01]: Contabo password uses bash `:?` operator (required env var) instead of `:-` default value.
- [49-01]: OVH password uses `openssl rand -base64 16` (runtime generation) instead of hardcoded string.
- [49-01]: Matrix/OpenClaw/Spacebot/mautrix ports added to internalOnlyPorts for comprehensive 23-port coverage.
- [52-01]: OCL-PKG-01: OpenClaw packaged from npm registry tarball (v2026.3.1) via `buildNpmPackage` with vendored package-lock.json. node-llama-cpp stripped.
- [52-01]: OCL-01→OCL-14: Module rewritten from Docker OCI containers to native systemd services with parametric `instances` map, per-instance system users, `.openclaw -> .` symlink for state path compatibility, trustedProxies reduced to `127.0.0.1` only.
- [52-02]: HP-02 updated: Docker group retained only for Spacebot container status. OpenClaw homepage widgets use siteMonitor-only.
- [52-02]: SEC47-21: Syncthing `insecureSkipHostcheck` set to `false` — Docker bridge access pattern removed.
- [53-01]: PROMPT-01: Atomic write via os.rename() for automaton.json prompt updates. HIST-01: JSONL prompt history capped at 50 entries.
- [53-01]: TOKEN-01: apiUrl() helper extracts ?token= from URL, appends to all dashboard fetch() calls for nginx auth proxy compatibility.
- [53-02]: PORT-53-02: Port 9093 (automaton-dashboard) added to internalOnlyPorts in networking.nix.
- [53-03]: DASH-04: ReadWritePaths for /var/lib/automaton/.automaton (prompt editing), ReadOnlyPaths for parent directory.
- [53-03]: DASH-05: Sudoers rule for automaton user — 3 lifecycle commands (start/stop/restart conway-automaton) with absolute paths, NOPASSWD.
- [53-03]: DASH-06: `security.sudo.execWheelOnly = lib.mkForce false` — NixOS asserts when non-wheel users in sudo.extraRules while execWheelOnly is true.
- [53-03]: WEB-14: conway.dangirsh.org vhost with ACME DNS-01 (Cloudflare), token auth via nginx map $arg_token, limit_req 10r/s burst=20.

### Completed Phases

- **Phase 68: Extract secret-proxy into standalone nix-secret-proxy flake** (3/3 plans, completed 2026-03-09)
  - 68-01: Standalone `nix-secret-proxy` flake created at `/data/projects/nix-secret-proxy` with `packages.secret-proxy`, `nixosModules.default`, `overlays.default`, `checks.build` exports. `package.nix` uses `src = ./.`; `module.nix` adds `services.secretProxy.package` option.
  - 68-02: neurosys consumes `nix-secret-proxy` as `path:` flake input with `inputs.nixpkgs.follows = "nixpkgs"`; `nix-secret-proxy.nixosModules.default` in `commonModules`; `modules/secret-proxy.nix` and `packages/secret-proxy/` deleted from neurosys.
  - 68-03: private-neurosys pins via `follows = "neurosys/nix-secret-proxy"`; `modules/secret-proxy-generic.nix` (180-line Python reimplementation) deleted; `nix flake check` passes on both repos.
  - README.md added to nix-secret-proxy with sops-nix/agenix/plain-file integration examples.

- **Phase 65: Open Source Cleanup v2 — Minimal Forkable Skeleton** (3/3 plans, completed 2026-03-04)
  - 65-01: Moved 4 personal modules and 4 package files to private overlay; updated import paths from `${inputs.neurosys}/modules/...` to local `./modules/...`.
  - 65-02: Stripped all personal references from core modules (impermanence, networking, secrets, host imports, eval checks, flake packages). Created `impermanence-private.nix` and expanded `secrets-contabo.nix` in private overlay.
  - 65-03: Updated README with 14-module table, 5 example use cases, core-only networking table.
  - All 19 nix flake check assertions pass. Zero personal service names in `modules/`, `hosts/`, `packages/`.

- **Phase 63: Google OAuth + Gmail/Calendar MCP Tools** (2/2 plans, completed 2026-03-02)
  - 63-01: Restored public `neurosys-mcp` modules (`server.py`, `auth.py`, `pyproject.toml`, `packages/neurosys-mcp.nix`) and added `google_auth.py` + `gmail.py` with five Gmail tools and callback routes.
  - 63-02: Added `calendar_tools.py` with six Calendar tools and shared OAuth token handling; wired Calendar registration in `server.py`; updated package metadata/import checks.
  - Flake export/package checks green: `nix build .#neurosys-mcp` + `nix flake check` pass, Python syntax checks pass for all `src/neurosys-mcp/*.py`.
  - Added planning artifacts: `.planning/phases/63-google-oauth-gmail-calendar-mcp-tools/63-DEPLOY.md` and `.planning/phases/63-google-oauth-gmail-calendar-mcp-tools/63-02-SUMMARY.md`.

- **Phase 59: Logseq PKM Agent Suite** (2/2 plans, completed 2026-03-02)
  - 59-01: Public repo — `logseq.py` with 3 read-only MCP tools (`logseq_get_todos`, `logseq_search_pages`, `logseq_get_page`); `orgparse` added to Nix package; `nix flake check` passes.
  - 59-02: Private overlay — `LOGSEQ_VAULT_PATH=/home/dangirsh/Sync/logseq` env var, `ProtectHome="read-only"` + `ReadOnlyPaths`; `dangirsh/logseq-agent-suite` GitHub repo with triage/graph-maintenance/review instruction files; cloning added to repos.nix.

- **Phase 53: Conway Dashboard Auth + Prompt Editor** (3/3 plans, completed 2026-03-02)
  - 53-01: Dashboard backend — prompt save/history/restore API, lifecycle control API, service status enrichment, token-forwarding dashboard UI.
  - 53-02: Public repo — port 9093 added to internalOnlyPorts security assertion.
  - 53-03: Private overlay — conway.dangirsh.org nginx vhost with ACME TLS + token auth, sops secret + template, ReadWritePaths + sudoers, 3 eval checks. nix flake check passes (18 checks).

- **Phase 56: Voice Interface Research — Low-Latency Parts Assistant** (1 plan, completed 2026-03-02)
  - 56-01: Research-only conclusion. 5 approaches evaluated (LiveKit Agents, Pipecat+Daily, Vapi, ClawdTalk/Telnyx, Claude App+MCP). LiveKit Agents recommended (Rank 1). docs/VOICE-RESEARCH.md deliverable created. Phase 57 skeleton drafted.

- **Phase 52: Nativize the Lobster Farm (Docker-free Contabo)** (2/2 plans, completed 2026-03-02)
  - 52-01: Public neurosys OpenClaw runtime migrated from OCI containers to 6 native systemd services; OpenClaw package exported from flake; eval checks updated.
  - 52-02: Private overlay aligned with native OpenClaw runtime (`openclaw-auto-approve` CLI migration, homepage OpenClaw widget Docker key removal, private eval check migration, Syncthing host check hardening).

- **Phase 50: Coherence & Simplicity Audit** (2 plans, completed 2026-03-01)
  - 50-01: Public repo module improvements — backported .git clone check, added conway-api-key secret, documented mkForce/owner patterns (SEC-03/SEC-04), AGENTD-40-03 annotation, sorted firewall port eval checks, deleted stale fleet-status.sh.
  - 50-02: Private overlay consolidation — deleted 3 duplicate modules (automaton, openclaw, spacebot), rewrote matrix.nix as 21-line override, added AGENT-50-02 annotation, restored HA hardening, removed unnecessary mkForce, fixed sopsFile priority (mkOverride 40), created 8 private eval checks, documented SEC50-01/SEC50-02.

- **Phase 49: Security Hardening Follow-up** (1 plan, completed 2026-03-01)
  - 49-01: Removed hardcoded passwords from bootstrap scripts (Contabo `:?` required env var, OVH `openssl rand`), expanded internalOnlyPorts to 23 entries, documented SEC49-01 accepted risk. Private overlay follow-ups (Matrix registration, Docker image pinning) documented for separate session.

- **Phase 48: Test Automation Infrastructure** (2/2 plans, completed 2026-03-01)
  - 48-01: Added two-layer validation stack: 20 flake eval checks + 39 BATS live tests, `nix run .#test-live` entry point, and `scripts/run-tests.sh` wrapper.
  - 48-02: Added 5 deep live suites (+25 tests), `--json` output mode, CI eval workflow, private overlay testing docs, and expanded shellcheck coverage.

- **Phase 47: Comprehensive Security Review** (3 plans, completed 2026-03-01)
  - 47-01: Network hardening — port audit, Mosh removed (1001 UDP ports closed), SSH hardened (X11 off, MaxAuthTries 3, LoginGraceTime 30, keepalive), internalOnlyPorts updated, port 22 documentation contradiction resolved
  - 47-02: Service isolation — systemd hardening (secret-proxy, Prometheus, node-exporter, tailscale-serve-ha), blast radius documentation for sandboxed vs unsandboxed agents
  - 47-03: Secret scoping — on-demand API key loading (load-api-keys function), wget removed, Syncthing hostcheck re-enabled, cross-project read documented, accepted risks updated

- **Phase 45: Neurosys MCP Server** (2 plans, completed 2026-03-01)
  - 45-01: FastMCP Streamable HTTP server with 5 HA tools, Nix package from PyPI (fastmcp 2.12.4 + mcp 1.26.0), port 8400 registered in internalOnlyPorts
  - 45-02: OAuth 2.1 (NeurosysOAuthProvider with HTML login form), 5 Matrix/Conduit tools, private overlay NixOS module (systemd + Tailscale Funnel 8443 + sops template), deployment checkpoint pending

- **Phase 37: Open Source Prep** (3 plans, completed 2026-02-27)
  - 37-01: Privacy audit — personal identifiers, private inputs, private service bindings removed; `nix flake check` passes
  - 37-02: Private overlay guide — docs/private-overlay.md with complete annotated flake skeleton
  - 37-03: README rewrite — 391→98 lines; principle-first; agent tooling as primary differentiator; zero personal identifiers

- **Phase 36: Research stereOS Ecosystem** (1 plan, completed 2026-02-27)
  - 36-01: Source-level analysis of all 6 papercomputeco repos (agentd, masterblaster, stereosd, stereOS, tapes, flake-skills). Recommendation: **Partial Adoption** (KVM blocks full stereOS on Contabo; sops-nix superior for persistent VPS). Top actions: adopt agentd as NixOS service (→ Phase 40), steal Harness interface + jcard.toml config schema. agentd reconciliation-loop daemon replaces one-shot agent-spawn.

- **Phase 1: Flake Scaffolding + Pre-Deploy** (2 plans, completed 2026-02-13)
- **Phase 2: Bootable Base System** (2/2 plans, completed 2026-02-15)
- **Phase 2.1: Base System Fixups** — Absorbed into Phase 9
- **Phase 3: Networking + Secrets + Docker Foundation** (2 plans, completed 2026-02-15)
- **Phase 3.1: Parts Integration** (3 plans, completed 2026-02-15)
- **Phase 8: Review Old Neurosys + Doom.d** (1 plan, completed 2026-02-15)
- **Phase 9: Audit & Simplify** (2 plans, completed 2026-02-15)
- **Phase 4: Docker Services** (2 plans, completed 2026-02-16)
- **Phase 5: User Environment + Dev Tools** (2 plans, completed 2026-02-16)
- **Phase 6: User Services + Agent Tooling** (2 plans, completed 2026-02-16)
  - 06-01: Syncthing declarative module (4 devices, 1 folder, staggered versioning, Tailscale-only GUI)
  - 06-02: CASS binary + timer, repo cloning activation, agent config symlinks
- **Phase 10: Parts Deployment Pipeline** (2 plans, completed 2026-02-17)
- **Phase 11: Agent Sandboxing** (2 plans, completed 2026-02-17)
- **Phase 13: Research Similar Projects** (1 plan, completed 2026-02-18)
  - 13-01: Presented 11 ideas, user cherry-picked 5 adoptions (ntfy, Prometheus+Grafana, CrowdSec, Agent Teams, TKA), 1 evaluate (MCP-NixOS), 2 rejected, 4 deferred
- **Phase 14: Monitoring + Notifications** (2 plans, completed 2026-02-18)
  - 14-01: Prometheus + Alertmanager + ntfy + Grafana baseline with 6 alert rules and sops-managed Grafana secrets
  - 14-02: Deploy outcome notifications + generic `notify.sh` helper + full `nix flake check` validation
- **Phase 16: Disaster Recovery & Backup Completeness** (2 plans, completed 2026-02-19)
  - 16-01: Backup gap closure — SSH host key, Docker bind mounts, Tailscale state, pg_dumpall pre-hook; deployed and verified with dry-run restore
  - 16-02: Recovery runbook (docs/recovery-runbook.md) — 4-phase recovery flow, RTO < 2hr, RPO 24hr
- **Phase 17: Hardcore Simplicity & Security Audit** (4 plans, completed 2026-02-19)
  - 17-01: Simplicity cleanup + kernel hardening + llm-agents nixpkgs follow
  - 17-02: SSH hardening (Tailscale-only), credential leak fix, restic backup excludes
  - 17-03: CLAUDE.md guardrails — security conventions, simplicity rules, module checklist
  - 17-04: Docker container audit, sandbox escape assessment, audit log journald dual-logging
- **Phase 19: Generate Project README** (1 plan, completed 2026-02-20)
  - 19-01: Comprehensive README.md with all modules, services, security, deployment, operations, decisions, risks
- **Phase 20: Deep Ecosystem Research** (1 plan, completed 2026-02-20)
  - 20-01: 10 parallel research agents → unified adoption report covering srvos, sandbox hardening, gVisor, deploy-rs, impermanence, secret proxy, microvm.nix, multi-node scaling, messaging, reference configs
- **Phase 24: Server Hardening + DX** (1 plan, completed 2026-02-23)
  - 24-01: srvos hardening baseline + PID/cgroup sandbox isolation + treefmt formatter/devShell integration
- **Phase 21: Impermanence (Ephemeral Root)** (2 plans, completed 2026-02-24)
  - 21-01: BTRFS 5-subvolume disko layout, impermanence module (17 dirs + 2 files), initrd rollback, restic /persist targeting, recovery runbook Appendix 12
  - 21-02: nixos-anywhere redeploy of Contabo VPS with BTRFS impermanence; resolved sops key rotation (parts, claw-swap), tailnet lock bootstrap, first-boot race conditions; all services running
- **Phase 25: Deploy Safety (deploy-rs)** (1 plan, completed 2026-02-21)
  - 25-01: deploy-rs input + deploy node + deployChecks, deploy.sh migration with rollback flags, recovery runbook Appendix 11
- **Phase 22: Secret Proxy (Netclode Pattern)** (1 plan, completed 2026-02-24)
  - 22-01: Python stdlib proxy via `pkgs.writers.writePython3Bin`; `ANTHROPIC_BASE_URL` approach (no TLS MITM); dedicated `secret-proxy` system user + sops template; claw-swap projects get placeholder key + proxy URL; port 9091 in `internalOnlyPorts`

### Roadmap Evolution

- Phase 10 added: Parts Deployment Pipeline — Research + Implementation (understand current parts deployment, implement neurosys-owned deploy flow)
- Phase 11 added: Agent Sandboxing — Default-on bubblewrap (srt) isolation for all coding agents. Research: evaluated Daytona, E2B, Firecracker, gVisor, nsjail, Docker, systemd-nspawn. bubblewrap selected for zero overhead, NixOS-native, proven by Claude Code's own sandbox. VPS: Contabo Cloud VPS 60 NVMe (18 vCPU, 96GB RAM) — no KVM, rules out microVMs.
- Phase 12 added: Security audit — review all modules for hardening gaps, secret handling, network exposure, sandbox escape vectors, and supply chain risks
- Phase 13 added: Research similar personal server projects — 11 ideas surveyed, 5 adopted, 1 evaluated, 2 rejected, 4 deferred
- Phase 14 added: Monitoring + Notifications — Prometheus + node_exporter + Grafana + ntfy (from Phase 13 research adoptions)
- Phase 15 added: CrowdSec Intrusion Prevention — collaborative threat intelligence with community sharing (from Phase 13 research)
- Phase 16 added: Disaster Recovery & Backup Completeness — audit stateful paths, complete restic coverage, create tested recovery runbook (< 2hr recovery from git + B2)
- Phase 17 added: Hardcore Simplicity & Security Audit — critical line-by-line review of all modules, services, secrets, networking, Docker, firewall, deployment for over-engineering/YAGNI and security gaps. Establish repo guardrails for future agentic development.
- Phase 19 added: Generate comprehensive project README — concise, skimmable README.md with all features, goals, constraints, deployment quick-start, operating details, design decisions, accepted risks
- Phase 20 added: Deep Ecosystem Research — 10 parallel agents surveying sandboxing, deployment, hardening, impermanence, messaging, multi-node scaling, and reference configs
- Phase 21 added: Impermanence (Ephemeral Root) — wipe root on every boot via nix-community/impermanence, BTRFS subvolumes + initrd rollback, explicit /persist state manifest (from ecosystem research item 6)
- Phase 22 added: Secret Proxy (Netclode Pattern) — two-tier proxy where real API keys never enter agent sandboxes, header-only injection, per-session allowlisting (from ecosystem research item 7)
- Phase 23 added: Tailscale Security & Self-Sovereignty — TKA (Tailnet Key Authority), ACL hardening, device approval, auth key rotation, self-custodied signing keys (from Phase 13 adoption + ecosystem research)
- Phase 24 added: Server Hardening + DX — srvos server profile, sandbox PID+cgroup isolation, gVisor Docker runtime, flake check toplevel, devShell, treefmt-nix (from ecosystem research items 1, 2, 3 + reference patterns)
- Phase 25 added: Deploy Safety (deploy-rs) — magic rollback via inotify canary, evolve deploy.sh into wrapper (from ecosystem research item 5)
- Phase 26 added: Agent Notifications (Telegram Bot) — Bot API integration, 2 sops secrets, agent reach-back mechanism (from ecosystem research item 4)
- Phase 27 added: OVH VPS Production Migration — multi-host refactor, OVH bootstrap, staged service migration, production cutover
- Phase 28 added: dangirsh.org Static Site on Neurosys — migrate dangling legacy Hakyll build to flake output and wire neurosys nginx to Nix store artifact
- Phase 22 executed: secret proxy deployed — `anthropic-secret-proxy` on port 9091; ANTHROPIC_BASE_URL approach (simpler than TLS MITM); claw-swap agents get placeholder key; real key never enters sandbox env
- Phase 29 added: Agentic Dev Maxing — batteries-included platform with all major CLI coding agents (gemini-cli, opencode, aider, etc.) and API keys for all major providers (XAI, OpenRouter, Gemini, Groq, Mistral)
- Phase 24 executed: srvos server defaults adopted with explicit host overrides, agent sandbox PID/cgroup isolation enabled, treefmt formatter + devShell shipped
- Phase 25 executed: deploy-rs integrated with 120s confirm timeout, version-pinned CLI passthrough, deployChecks, and recovery runbook rollback procedures
- Phase 27 progressing: 27-01 recon/secrets bootstrap and 27-02 multi-host flake + deploy node refactor executed
- Phase 28 progressing: 28-01 flake migration + 28-02 OVH nginx integration completed; ready for 28-03 DNS cutover and live certificate issuance.
- Phase 30 added: Claw-Swap Native NixOS Service — replace Docker containers with services.postgresql + systemd service for Node.js app; remove oci-containers/custom bridge; native sops-nix secret injection; Docker stays for parts
- Phase 31 added: Conway Automaton — Single Agent MVP — restored from removed Phase 27 Automaton Fleet; reduced from 4 agents to 1; seed hypothesis #1 (x402 APIs); fleet-status.sh monitoring script
- Phase 32 added: Self-Hosted Conway Automaton on Neurosys — package automaton as a Nix derivation first (32-01 complete), then wire the systemd service module (32-02 pending)
- Phase 33 added: Research spacebot security: prompt injection defenses + ironclaw integration feasibility — investigate how spacebot guards against prompt injection (sandboxing, input validation, context isolation, published threat model) and how hard it would be to wire ironclaw as the LLM backend/agent executor behind spacebot's UI layer
- Phase 34 added: Voice MCP — Claude Android app tools via Home Assistant — enable HA native MCP integration (HA 2024.11+), expose via Tailscale Serve HTTPS, connect Claude Android voice mode to control lights and query CO2/sensors without public internet exposure
- Phase 35 added: Unified Messaging Bridge — Signal + WhatsApp + Telegram → AI — Conduit homeserver + mautrix bridges (all in nixpkgs); mautrix-telegram most stable (official API), mautrix-whatsapp medium risk (WA ban), mautrix-signal medium stability (signal-cli); AI access via Matrix bot + CS API; historical data ingested one-time to Spacebot LanceDB (bridges only sync forward)
- Phase 36 added: Research stereOS ecosystem (stereOS, masterblaster, stereosd, agentd) — study all repos, generate a report on what to learn/steal for neurosys, recommend whether to switch from NixOS to stereOS
- Phase 36 executed: Partial adoption — KVM blocks full stereOS on Contabo. agentd daemon model (reconciliation loop, restart policy, HTTP API) is top adoption. stereosd/masterblaster/VM model not applicable. Phase 40 added: agentd integration to replace agent-spawn.
- Phase 40 updated: expanded to research-first — validate agentd vs. systemd supervision + s6/supervisord alternatives before building; 2-plan structure (research + implementation).
- Phase 41 added: Agent user isolation — curated buildEnv PATH + sudo denial (stereos-agent-shell pattern); research-first to validate threat model gap vs. bwrap alone.
- Phase 42 added: masterblaster VM-based agent isolation — KVM-conditional; research-first (OVH KVM check + Firecracker/Kata comparison); highest security ceiling if validated.
- Phase 43 added: tapes agent session telemetry — research-first (gap vs. Spacebot LanceDB + LangFuse/Helicone alternatives + privacy model); semantic search of agent conversations.
- Phase 38 added: Dual-host role separation — Contabo = services host (HA, Spacebot, Matrix, monitoring, claw-swap), OVH = dev-agent host (agent-compute, Claude/Codex, sandbox, agent-spawn). Audit current module allocation, migrate misplaced services/modules, ensure deploy.sh covers both targets, verify Tailscale MagicDNS reachability for both.
- Phase 39 added: Conway Automaton monitoring dashboard — lightweight Tailscale-only web UI showing live agent status (state, credits, turns, goal progress, tool calls, spend rate), linked from homepage dashboard.
- Phase 39 progressing: 39-01 completed — private `dangirsh/conway-dashboard` repo created with `server.py` and `dashboard.html`; ready for 39-02 neurosys integration.
- Phase 45 added: Interrogate design principles and rewrite README principles section — discussion-first phase to nail down exact principles (agents-first, secure defaults, minimal untracked state, headless/long-running), then rewrite README Design Principles section to reflect them accurately.
- Phase 47 added: Comprehensive Security Review — end-to-end audit of public + private neurosys components. Three focus areas: (1) network attack surface hardening (ports, firewall, Tailscale ACLs), (2) intrusion blast radius containment (lateral movement limits, isolation boundaries, secrets compartmentalization), (3) attack surface minimization (unnecessary packages/services/privileges). Covers both hosts, all services, Docker, agent sandbox, sops secrets, deployment pipeline.
- Phase 48 added: Test Automation Infrastructure — comprehensive e2e/integration test suite for all neurosys components (public modules, private overlay, agentd fleet, secrets, network, Docker services, MCP server, homepage, deploy pipeline). Agent-runnable tests with maximal feedback. Minimalism for prod, maximalism for test infra.
- Phase 49 added: Security Hardening Follow-up — Fix HIGH priority issues from Phase 47 audit: (1) remove hardcoded passwords from bootstrap scripts, (2) complete internalOnlyPorts coverage for OpenClaw/Spacebot/Matrix ports, (3) verify Matrix Conduit registration token enforcement, (4) pin Docker container images to SHA256 digests.
- Phase 50 added: Coherence & Simplicity Audit — holistic review of public + private neurosys for architectural coherence, threat model consistency, over-engineering, code smells, surprising non-standard decisions, feature conflicts, and design inconsistencies. Cross-cutting analysis of all modules, services, secrets, deployment, and private overlay layering.
- Phase 51 added: Conway Automaton profitability research — deep investigation into why the agent loop is ineffective (goal churn, worker timeouts, placeholder wallet, no real deployment/exposure) and how to reconfigure it to actually generate revenue. Research x402 viability, agent task sizing, deployment gaps, and produce a concrete reconfiguration plan.
- Phase 53 added: Conway Dashboard Auth + Prompt Editor — token-based auth for public internet access (bearer token via sops-nix + nginx HTTPS) so dashboard works outside Tailscale; UI to edit genesis prompt and restart automaton agent without NixOS rebuild. Changes span conway-dashboard repo + private-neurosys overlay.
- Phase 59 added: Logseq PKM Agent Suite — private repo (`logseq-agent-suite`) + neurosys private overlay component. Datalog query library, agent instruction files (todo triage, graph maintenance, review flows), NixOS module exposing vault path to agentd agents, and parts-agent interface for reading/writing the personal graph. Vault already in Syncthing.
- Phase 56 executed: Research-only conclusion. Voice interface for HA control evaluated across 5 approaches. LiveKit Agents + Anthropic Plugin recommended (self-hosted WebRTC, localhost tool calls, 900-1400ms TTFB). Phase 57 implementation skeleton drafted (2 plans: infrastructure + application). docs/VOICE-RESEARCH.md created as project-level reference.
- Phase 60 added: Dashboard DM Pairing & Backup Decrypt Guide — homepage dashboard links to a self-hosted guide for pairing DM bridge services (Signal/WhatsApp/Telegram mautrix) and uploading & decrypting message backups for historical import.
- Phase 63 added/executed: Google OAuth + Gmail MCP tools — restored public neurosys-mcp server package, added interactive Google authorization routes, token persistence/refresh, and five Gmail tools.
- Phase 61 added: Nix-Derived Dynamic Dashboard — investigate generating a live dashboard directly from NixOS module expressions (tree view with status/links), replacing manually-maintained homepage config. May use module annotations (e.g., `meta.dashboard`). Goal: dashboard always reflects deployed Nix source, zero drift.
- Phase 64 added: Repo Layout Simplification — rename hosts/neurosys→services, hosts/ovh→dev; remove beads, logseq, docs/, spacebot port; delete modules/default.nix hub (explicit imports per host); merge small home modules inline; inline small packages; inline repos.nix; update flake.nix + CLAUDE.md.
- Phase 66 added: Secret Placeholder Proxy Module — extract the secret-proxy trick (Phase 22) into a generic, well-tested NixOS module. Research ironclaw, gondolin (earendil-works), and all relevant NixOS secret management approaches. Design: placeholder tokens → proxy re-injects real secrets with per-secret allowed-domain lists blocking exfiltration. Decouple from secret backend (sops/agenix) and sandbox (bwrap) where possible. Goal: prompt-injected agents can't exfiltrate but operate seamlessly.
- Phase 67 added: Review and document the secret proxy — read all source, tests, and module code; produce an executive summary of key design features, limitations, and improvement areas
- Phase 68 added: Extract secret-proxy into standalone nix-secret-proxy flake — new public GitHub repo with flake.nix (packages.secret-proxy + nixosModules.default), README with sops-nix/agenix/plain-file integration examples, neurosys consumes it as a flake input instead of carrying local copies
- Phase 70 added: Deployment Lockout Prevention — OOB recovery runbook (Contabo KVM + OVH rescue mode), break-glass emergency SSH key (hardcoded, independent of sops), strengthened pre-deploy assertions, SSH canary systemd timer with auto-rollback, hardened watchdog reliability in deploy.sh, NixOS VM test that validates SSH before prod deploy
- Phase 73 added: OVH Agent Sandbox Enforcement — aliases and shell-level interception so `claude`/`codex` always run sandboxed on OVH by default; hard block on `--no-sandbox` without explicit override (`AGENT_ALLOW_NOSANDBOX=1`); audit logging of sandboxed/unsandboxed invocations; NixOS `agent-compute.nix` changes for OVH; secret-proxy placeholder wired into sandboxed sessions
- Phase 72.1 inserted after Phase 72: OVH Secret Proxy — Deploy Phase 72 & Live Acceptance Tests (URGENT) — deploy Phase 72 nix-secret-proxy features (/health, large-body, JSON 502, graceful shutdown) to OVH; add BATS live tests for all new behaviors; verify end-to-end agent-proxy connectivity; prerequisite foundation for Phase 73 sandbox enforcement
- Phase 74 added: Open Source Release Prep v3 — final hardcore cleanup for public release: remove personal/sensitive/unnecessary content (move to private or gitignore), reset git history, rewrite README for impact, hardcore minimalism pass on all code with user confirmation on each major removal

### Blockers/Concerns

- [RESOLVED]: CASS binary availability — v0.1.64 fetched and patched successfully
- [RESOLVED]: Contabo uses BIOS boot (i386-pc GRUB installed successfully), eth0 confirmed
- [RESOLVED]: Secrets deployed and decrypted — 15 secrets in /run/secrets/
- [RESOLVED]: Phase 2.1 scope creep — absorbed into Phase 9 after re-evaluation
- [NOTE]: Syncthing device IDs are placeholders — user must replace before deploy
- [NOTE]: home-manager ssh/git options show deprecation warnings (renamed options) — cosmetic, not blocking
- [NOTE]: OVH root SSH password auth failed during 27-01; recon succeeded via `ubuntu` after forced password-expiry rotation. Confirm preferred admin login path before 27-03 deploy steps.
- [NOTE]: private-neurosys currently pins `neurosys` input to github `af29add`; until that pin is advanced to include Phase 66 commits, private eval requires `--override-input neurosys /data/projects/neurosys`.

### Quick Tasks Completed

| # | Description | Date | Commit | Directory |
|---|-------------|------|--------|-----------|
| 001 | Replace tmux with zmx (github.com/neurosnap/zmx) | 2026-02-16 | d3e0209 | [001-replace-tmux-with-zmx](./quick/001-replace-tmux-with-zmx/) |
| 002 | Add Home Assistant as native NixOS service | 2026-02-17 | 6a95e07 | [002-add-home-assistant-as-native-nixos-servi](./quick/002-add-home-assistant-as-native-nixos-servi/) |
| 003 | Add homepage dashboard linking all services | 2026-02-18 | 48b0182 | [3-add-a-nixos-native-homepage-dashboard-li](./quick/3-add-a-nixos-native-homepage-dashboard-li/) |
| 004 | Add concurrent deploy lock to deploy.sh | 2026-02-18 | ef1fc65 | [4-add-concurrent-deploy-lock-to-deploy-sh](./quick/4-add-concurrent-deploy-lock-to-deploy-sh/) |
| 005 | Minimize monitoring stack to Prometheus-only | 2026-02-18 | c5fa13b | [5-minimize-monitoring-notification-stack-t](./quick/5-minimize-monitoring-notification-stack-t/) |
| 006 | Add Hue and ESPHome extraComponents to Home Assistant | 2026-02-18 | 8512fa9 | [6-add-hue-and-esphome-extracomponents-to-h](./quick/6-add-hue-and-esphome-extracomponents-to-h/) |
| 007 | Configure restic backups to Backblaze B2 | 2026-02-19 | 1536d80 | [7-configure-restic-backups-to-backblaze-b2](./quick/7-configure-restic-backups-to-backblaze-b2/) |
| 008 | Switch restic to blanket root backup with exclusions | 2026-02-19 | 6483029 | [8-switch-restic-backups-from-hard-coded-pa](./quick/8-switch-restic-backups-from-hard-coded-pa/) |
| 009 | Research similar projects to neurosys (dev env + VPS + agentic dev) | 2026-02-20 | 2a91200 | [9-research-similar-projects-to-neurosys-fo](./quick/9-research-similar-projects-to-neurosys-fo/) |

### Quick Tasks Pending (from Phase 13)

| Task | What | Effort |
|------|------|--------|
| Agent Teams env var | Add `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=true` to agent-spawn | Minutes |
| MCP-NixOS evaluate | Add to `.mcp.json`, test in sessions, remove if context-polluting | Minutes |
| Tailnet Key Authority | Run `tailscale lock init` + sign nodes | Minutes |

## Session Continuity

Last session: 2026-03-10
Stopped at: Completed Phase 70 — deployment lockout prevention (break-glass key, SSH canary, systemd-run watchdog, VM test, OOB runbook, 6 new eval assertions).
Next: TBD.
