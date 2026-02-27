# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-02-15)

**Core value:** One command to deploy a fully working development server with all services running, all tools installed, and all infrastructure repos cloned -- no manual setup steps.
**Current focus:** Phase 34 Plan 01 code validation complete — Home Assistant MCP + Tailscale Serve config is present and flake-validated. Awaiting human deploy/UI checkpoints (Tasks 34-01-E through 34-01-G).

## Current Position

Phase: 34 (Voice MCP — Claude Android app tools via Home Assistant) — PLAN 01 READY FOR HUMAN DEPLOY CHECKPOINT
Plan: 1 of 1 -- CODE VALIDATED (A-D complete; E-G are human-action checkpoints)
Status: Verified `modules/home-assistant.nix` contains `mcp_server`, `http.use_x_forwarded_for`, `http.trusted_proxies = [ "127.0.0.1" ]`, and `systemd.services.tailscale-serve-ha` oneshot (`after/wants tailscaled`, `wantedBy multi-user.target`). Ran `nix flake check` successfully for neurosys + ovh and wrote `.claude/.test-status`.
Last activity: 2026-02-27 - Executed 34-01 validation run; ready to pause at Task 34-01-E (deploy verification checkpoint)

Progress: Phase 34 plan 34-01 is checkpoint-ready (4/7 tasks complete, awaiting human deploy/UI actions). Phase 35 plan 35-01 remains complete on main (d598be4) with separate deployment/bootstrap checkpoint pending.

## Performance Metrics

**Velocity:**
- Total plans completed: 22
- Average duration: ~16.5min
- Total execution time: ~364 min

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

**Recent Trend:**
- Last 4 plans: 28-02 (~16min), 28-01 (~6min), 27-02 (~7min), 27-01 (~9min)
- Trend: Execution remains stable with short, bounded plan delivery.

*Updated after each plan completion*

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table.
Recent decisions affecting current work:

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

### Completed Phases

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

### Blockers/Concerns

- [RESOLVED]: CASS binary availability — v0.1.64 fetched and patched successfully
- [RESOLVED]: Contabo uses BIOS boot (i386-pc GRUB installed successfully), eth0 confirmed
- [RESOLVED]: Secrets deployed and decrypted — 15 secrets in /run/secrets/
- [RESOLVED]: Phase 2.1 scope creep — absorbed into Phase 9 after re-evaluation
- [NOTE]: Syncthing device IDs are placeholders — user must replace before deploy
- [NOTE]: home-manager ssh/git options show deprecation warnings (renamed options) — cosmetic, not blocking
- [NOTE]: OVH root SSH password auth failed during 27-01; recon succeeded via `ubuntu` after forced password-expiry rotation. Confirm preferred admin login path before 27-03 deploy steps.

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

Last session: 2026-02-27
Stopped at: Phase 34 plan 34-01 execution boundary. Tasks A-D complete (config verified in main + flake check passed). Waiting at Task 34-01-E checkpoint for human deploy/Tailscale Serve verification.
Next: Human runs Task 34-01-E deploy checks, then Tasks 34-01-F and 34-01-G (HA UI MCP setup + Claude Android connector tests).
