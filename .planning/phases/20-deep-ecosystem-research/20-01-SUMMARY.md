# Phase 20: Deep Ecosystem Research — What to Adopt for Neurosys

**Date:** 2026-02-20
**Method:** 10 parallel research agents, each deep-diving one topic area
**User goals:** Equal priority across agent compute, personal services, and dev environment. Big architectural changes welcome. All research areas including multi-node scaling.

---

## Executive Summary

Ten research agents surveyed 60+ projects across sandboxing, deployment, server hardening, impermanence, messaging, multi-node scaling, and reference NixOS configs. The findings below are organized as **concrete adoption recommendations** ranked by impact and effort.

### Top 5 Actions (Do Now)

| # | Action | Effort | Impact | Source Agent |
|---|--------|--------|--------|-------------|
| 1 | **Integrate srvos server profile** — ~20 hardening improvements neurosys is missing | Low (1 flake input + 1 import) | High (watchdog, OOM protection, emergency mode, scheduling) | srvos, Mic92 |
| 2 | **Add `--unshare-pid` and `--unshare-cgroup` to agent-spawn** | Trivial (2 flags) | Medium (hides host processes/cgroups from sandboxed agents) | nix-sandbox-mcp |
| 3 | **Add gVisor (runsc/systrap) as Docker OCI runtime** | Low (1 NixOS option) | High (user-space kernel for Docker containers, no KVM needed) | E2B/sandbox |
| 4 | **Add Telegram bot notification for agent reach-back** | Low (writeShellApplication + 2 sops secrets) | Medium (agents can notify operator) | MCP/OpenClaw |
| 5 | **Add deploy-rs for magic rollback** | Low (15-line flake addition) | Medium (auto-rollback on broken SSH — critical for Tailscale-only) | Deployment tools |

### Top 5 Actions (Do When Ready)

| # | Action | Effort | Impact | Trigger |
|---|--------|--------|--------|---------|
| 6 | **Impermanence (ephemeral root + btrfs rollback)** | High (redeploy required) | Very High (explicit state manifest, smaller backups, drift-proof) | Next major maintenance window |
| 7 | **Secret proxy pattern for agent sandboxes** | Medium (Go service + NixOS module) | High (API keys never enter sandboxes) | When agent security matters |
| 8 | **microvm.nix for agent isolation** | Medium (needs KVM) | Very High (full VM isolation per agent) | When migrating to KVM-capable host |
| 9 | **Multi-host split (Colmena + 2nd node)** | Medium (module refactor + Colmena) | High (capacity + KVM access) | When single VPS is insufficient |
| 10 | **OpenClaw for multi-channel messaging** | Medium (flake input + Home Manager) | Medium (Telegram + Signal + WhatsApp) | When multi-channel messaging needed |

---

## Research Findings by Topic

### 1. Server Hardening: srvos

**Source:** [nix-community/srvos](https://github.com/nix-community/srvos) (via srvos agent + Mic92 agent)

**What it is:** Battle-tested NixOS server defaults maintained by the nix-community. Used by Mic92, Numtide, and many production NixOS deployments.

**What neurosys is missing that srvos provides:**

| Setting | What it does | Risk of not having it |
|---------|-------------|----------------------|
| `systemd.settings.Manager.RuntimeWatchdogSec = "15s"` | Hardware reboot if systemd hangs | Hung system requires manual power cycle |
| `systemd.enableEmergencyMode = false` | Don't drop to shell on headless server | Unbootable until console access |
| `systemd.sleep.extraConfig = "AllowSuspend=no"` | Prevent accidental suspend | VPS goes offline |
| `nix.daemonCPUSchedPolicy = "batch"` | Builds don't starve services | Agent builds cause service latency |
| `nix.daemonIOSchedClass = "idle"` | Same for I/O | Builds cause disk contention |
| `systemd.services.nix-daemon.serviceConfig.OOMScoreAdjust = 250` | OOM kills builds before services | OOM kills Docker/HA instead |
| `nix.settings.min-free = 512MB` / `max-free = 3GB` | Auto-GC when disk is low | Disk fills up during builds |
| `nix.settings.connect-timeout = 5` / `fallback = true` | Fast fallback on cache miss | Builds hang on unreachable cache |
| `services.resolved.settings.Resolve.LLMNR = "false"` | Prevent LLMNR poisoning | Network attack vector |
| `networking.firewall.logRefusedConnections = false` | Reduce scanner noise in logs | Log pollution |
| `boot.tmp.cleanOnBoot = true` | Clean /tmp on boot | Stale files accumulate |
| `nix.channel.enable = false` | No legacy channels with flakes | Confusing dual-channel/flake state |
| `system.preSwitchChecks.update-diff` | `nvd diff` before switching | Blind deploy without seeing changes |
| `system.preSwitchChecks.detectHostnameChange` | Prevent deploying to wrong host | Accidental wrong-host deploy |
| `programs.ssh.knownHosts` for github.com, gitlab.com | No TOFU MITM risk | First git clone vulnerable |
| Documentation/fonts/XDG disabled | Smaller closure, faster eval | Wasted space/eval time |

**Integration:** Add `srvos` as flake input, import `srvos.nixosModules.server`. Remove ~15 redundant settings from `base.nix`, `users.nix`, `networking.nix`.

**Risk:** `networking.useNetworkd = true` (srvos default) may need testing with Contabo's static IP config. Override with `networking.useNetworkd = lib.mkForce false` if it breaks.

### 2. Agent Sandbox Hardening: nix-sandbox-mcp

**Source:** [secbear/nix-sandbox-mcp](https://github.com/secbear/nix-sandbox-mcp) + [jail.nix](https://sr.ht/~alexdavid/jail.nix)

**Key findings:** nix-sandbox-mcp's bubblewrap config is stricter than neurosys in several dimensions:

| Gap | nix-sandbox-mcp | neurosys agent-spawn | Recommendation |
|-----|----------------|---------------------|----------------|
| PID namespace | `--unshare-pid` | Not unshared | **Add** — hides host processes |
| Cgroup namespace | `--unshare-cgroup` | Not unshared | **Add** — hides host cgroup hierarchy |
| Network | `--unshare-net` (blocked) | Full access | **Keep** neurosys's approach (agents need API/git) |
| Nix store | Closure-only binding | Full `/nix/store` ro | **Defer** — high complexity, low risk for semi-trusted agents |
| `/proc` | Synthetic (`--proc /proc`) | Not explicitly set | **Verify** and add if missing |
| `--disable-userns` | Not used | **Used** | Neurosys is **better** here |

**Concrete change:** Add 2 flags to `BWRAP_ARGS` in `modules/agent-compute.nix`:
```bash
--unshare-pid
--unshare-cgroup
```

**What neurosys does better:** `--disable-userns` (prevents nested namespace attacks), systemd slice resource limits, audit logging.

### 3. gVisor for Docker Container Isolation

**Source:** E2B/Docker sandboxes research agent

**Key insight:** All microVM solutions (E2B, Firecracker, microsandbox, Arrakis, Kata Containers) require KVM, which Contabo VPS doesn't provide. **gVisor with systrap platform is the strongest isolation available without KVM.**

gVisor intercepts syscalls in user-space via a separate kernel (Sentry), providing near-VM isolation without hardware virtualization. The `systrap` platform uses seccomp traps — no KVM needed.

**Integration:**
```nix
virtualisation.docker.daemon.settings = {
  runtimes.runsc = {
    path = "${pkgs.gvisor}/bin/runsc";
    runtimeArgs = [ "--platform=systrap" ];
  };
};
```

Then run security-sensitive containers with `--runtime=runsc`.

**Isolation hierarchy (weakest to strongest):**
```
Plain process → Bubblewrap → Docker container → gVisor/systrap → microVM (KVM)
                [agents]     [services]          [VIABLE NOW]     [needs KVM]
```

### 4. Messaging: Telegram Bot + OpenClaw

**Source:** MCP messaging + OpenClaw agent

**Recommended architecture (phased):**

**Phase A — Telegram notification bot (minimal, do now):**
- `writeShellApplication` wrapping `curl` to Telegram Bot API
- 2 sops secrets: `telegram-bot-token`, `telegram-chat-id`
- Outbound HTTPS only — no inbound ports needed
- Accessible to agents via env var in sandbox

**Phase B — Bidirectional MCP server (later):**
- Wrap Telegram Bot API as an MCP server with `send_message` + `get_updates` tools
- Add to Claude Code's MCP config

**Phase C — OpenClaw multi-channel (if needed):**
- [OpenClaw](https://github.com/openclaw/openclaw) (213K stars) provides Gateway architecture with 22+ channel adapters
- [nix-openclaw](https://github.com/openclaw/nix-openclaw) provides Home Manager module for x86_64-linux
- Tailscale-native integration (`gateway.tailscale.mode: "serve"`)
- **Caution:** Cisco security audit found critical vulnerabilities. Only use vetted skills.

**What NOT to adopt from hyperion-hub:** Hyperion-hub itself is just a bash setup script for Debian. The MCP servers it references (telegram-mcp, signal-mcp) are worth evaluating individually, but hyperion-hub adds no value over neurosys's declarative approach.

### 5. Deployment: deploy-rs Magic Rollback

**Source:** Deployment tools comparison agent

**Key finding:** For a Tailscale-only server, **magic rollback is the single most important safety feature.** If a deploy breaks SSH/Tailscale/networking, deploy-rs auto-rolls back via inotify canary mechanism.

**Comparison:**

| Tool | Magic Rollback | Parallel | Effort | Recommendation |
|------|---------------|----------|--------|----------------|
| **deploy.sh** (current) | No | N/A | Zero | **Keep** for single-host |
| **deploy-rs** | **Yes** | Yes | Very Low | **Add** for safety net |
| **Colmena** | No | Yes (10x) | Low | **Add when multi-host** |
| **comin** | No | N/A | Medium | Skip (paradigm shift) |
| **Clan** | No | Yes | Very High | Skip (wholesale rewrite) |

**Integration:**
```nix
inputs.deploy-rs.url = "github:serokell/deploy-rs";

deploy.nodes.neurosys = {
  hostname = "neurosys";
  profiles.system = {
    user = "root";
    path = deploy-rs.lib.x86_64-linux.activate.nixos self.nixosConfigurations.neurosys;
  };
};
```

**deploy.sh evolves into a deploy-rs wrapper** keeping container health check, locking, and `nix flake update parts`:
```bash
nix flake update parts
deploy .#neurosys --confirm-timeout 120
# ... container health check ...
```

### 6. Impermanence: Ephemeral Root + Explicit State

**Source:** Misterio77/nix-config deep-dive agent

**What it is:** Wipe root filesystem on every boot. Only explicitly declared paths survive (bind-mounted from `/persist`). Everything else is ephemeral.

**Why it matters for neurosys:**
- **Drift-proof:** Undeclared state can't accumulate
- **Explicit state manifest:** `environment.persistence` declares every stateful path
- **Smaller backups:** Back up `/persist` instead of entire root
- **Simpler disaster recovery:** Restore `/persist` from restic → reboot → done

**Recommended approach (Misterio77 pattern):** BTRFS subvolumes + initrd rollback to blank snapshot.

```
/           → btrfs subvol "root"    (WIPED on boot)
/nix        → btrfs subvol "nix"     (persistent)
/persist    → btrfs subvol "persist" (persistent, neededForBoot=true)
```

**Critical migration steps:**
1. Re-point sops age key: `sops.age.sshKeyPaths = [ "/persist/etc/ssh/ssh_host_ed25519_key" ]`
2. SSH host key path: `services.openssh.hostKeys = [{ path = "/persist/etc/ssh/ssh_host_ed25519_key"; type = "ed25519"; }]`
3. Per-service persistence declarations in each module (distributed pattern)
4. Restic backup path changes from `/` to `/persist`

**Stateful paths audit (from research):**

| Path | Module | Must Persist |
|------|--------|-------------|
| `/etc/machine-id` | NixOS core | Yes |
| `/etc/ssh/ssh_host_ed25519_key` | secrets.nix | Yes (age key source) |
| `/var/lib/nixos` | NixOS core | Yes (UID/GID maps) |
| `/var/lib/systemd` | systemd | Yes (timers, journals) |
| `/var/log` | systemd | Yes (audit trail) |
| `/var/lib/tailscale` | networking.nix | Yes (node identity) |
| `/var/lib/docker` | docker.nix | Yes (container state) |
| `/var/lib/prometheus2` | monitoring.nix | Yes (90-day metrics) |
| `/var/lib/hass` | home-assistant.nix | Yes (HA database) |
| `/var/lib/esphome` | home-assistant.nix | Yes (device configs) |
| `/var/lib/fail2ban` | networking.nix | Yes (ban database) |
| `/var/lib/syncthing` | syncthing.nix | Yes (cert/keys) |
| `/home/dangirsh` | users.nix | Yes |
| `/data/projects` | repos.nix | Yes |

**Effort:** High — requires disk reprovisioning (nixos-anywhere redeploy). Plan as a dedicated phase with VM testing first.

### 7. Secret Proxy Pattern

**Source:** Netclode deep-dive agent

**The problem:** Agent sandboxes receive API keys as environment variables. A compromised agent can read them directly.

**Netclode's solution:** Two-tier proxy where real API keys never enter the sandbox:

```
Agent (inside sandbox)
  → sees ANTHROPIC_API_KEY=PLACEHOLDER
  → HTTP_PROXY=localhost:8080
  → auth-proxy adds bearer token, forwards to...
Secret-proxy (outside sandbox)
  → validates token via K8s TokenReview
  → replaces PLACEHOLDER in HTTP headers with real key
  → forwards to api.anthropic.com
```

**Key security properties:**
- Header-only injection (prevents reflection attacks)
- Per-session SDK-type allowlisting (Claude → anthropic.com only)
- Blocking on validation failure

**For neurosys:** A simplified single-instance version (no K8s). Systemd service holding real keys, agents talk through HTTP proxy. Inspired by [Fly's Tokenizer](https://github.com/superfly/tokenizer).

**Effort:** Medium — requires writing a small Go/Rust proxy service + NixOS module.

### 8. microvm.nix for Agent VMs

**Source:** microvm.nix agent + multi-node agent

**What it is:** [microvm.nix](https://github.com/microvm-nix/microvm.nix) builds NixOS systems as lightweight VMs using cloud-hypervisor/Firecracker/QEMU. Each agent gets its own kernel — full hardware isolation.

**Stapelberg's pattern (February 2026):**
- Per-agent ephemeral VMs: 8 vCPU, 4 GB RAM
- 4 virtiofs shares: `/nix/store` (ro), SSH keys, credentials, workspace (rw)
- Boots in seconds, self-replicating via Claude Skill

**Blocker:** Contabo VPS has no KVM. Options:
- **Contabo VDS** (~$46/month) — has KVM
- **Hetzner Dedicated AX42** (~$55/month) — bare metal, full KVM
- **QEMU-TCG fallback** — ~8x slower, impractical

**Patterns to adopt NOW (no KVM required):**
1. Modular per-agent config (instead of monolithic agent-spawn script)
2. Workspace isolation model (4-share pattern → formalize bind mounts as data structure)
3. systemd-nspawn as middle ground (stronger than bwrap, no KVM needed)

### 9. Multi-Node NixOS Scaling

**Source:** Multi-node scaling agent

**Three architecture options:**

| Option | Nodes | KVM | Cost/mo | Effort |
|--------|-------|-----|---------|--------|
| **A: Minimal (2 Contabo)** | Services + overflow compute | No | $63-71 | 2-3 phases |
| **B: Agent-optimized (Contabo + Hetzner dedicated)** | Services + KVM compute | Yes | $110-127 | 3-4 phases |
| **C: Full fleet (3+ nodes)** | Ingress + services + compute | Yes | $108+ | 5-6 phases |

**Recommendation:** Option B when agent isolation matters. Hetzner AX42/AX52 dedicated server for agent compute (KVM + 64 GB RAM), keep Contabo for services.

**Prerequisites (do now regardless):**
1. Split `modules/default.nix` into common/ vs service-specific imports
2. Parameterize host-specific values (e.g., hardcoded Tailscale IP in homepage.nix)
3. Template `.sops.yaml` for multi-host key groups

### 10. Reference Config Patterns: Mic92 + EmergentMind

**Source:** Mic92/EmergentMind deep-dive agent

**Worth adopting from Mic92:**
- srvos layered integration (common + server + mixins per host)
- `self` reference pattern (access inputs via `self.inputs.*` instead of specialArgs)
- Flake checks that build machine configs: `checks.x86_64-linux.nixos-neurosys = self.nixosConfigurations.neurosys.config.system.build.toplevel`
- treefmt-nix for consistent formatting (nixfmt + shellcheck + shfmt)

**Worth adopting from EmergentMind:**
- Private nix-secrets repo pattern (if repo goes public)
- Shared vs per-host sops YAML files
- Home-manager age key bootstrapping (derive HM-accessible age key from host sops secret)
- DevShell with sops + age + deploy tooling

**Skip:**
- Clan framework (heavy, opinionated, single-server doesn't benefit)
- Retiolum/tinc mesh (Tailscale is better for this use case)
- buildbot-nix CI (overkill for single server)
- EmergentMind's hostSpec options module (overengineered for single-host single-user)

---

## Adoption Roadmap

### Immediate (next session)

1. **srvos integration** — Add flake input, import server module, remove redundant settings
2. **Sandbox flags** — Add `--unshare-pid` and `--unshare-cgroup` to agent-spawn
3. **Flake checks** — Add `nixosConfigurations.neurosys` to flake checks output

### Short-term (next 1-2 phases)

4. **deploy-rs** — Add alongside deploy.sh for magic rollback safety
5. **gVisor** — Add as Docker OCI runtime for security-sensitive containers
6. **Telegram notify** — Minimal bot for agent reach-back
7. **DevShell** — sops + age + deploy tooling

### Medium-term (dedicated phases)

8. **Impermanence** — BTRFS rollback + explicit persistence (requires redeploy)
9. **Secret proxy** — API keys never enter agent sandboxes
10. **Module refactor** — Split common/ vs services/ for multi-host readiness

### Long-term (when needed)

11. **Multi-host** — Colmena + 2nd node (Hetzner dedicated for KVM)
12. **microvm.nix** — Per-agent VMs (requires KVM-capable host)
13. **OpenClaw** — Multi-channel messaging gateway

---

## Appendix: Research Agent Coverage

| # | Agent | Topic | Key Projects Analyzed |
|---|-------|-------|-----------------------|
| 1 | Netclode | Secret proxy + session management | [Netclode](https://github.com/nichochar/netclode) |
| 2 | nix-sandbox-mcp | Bubblewrap patterns + MCP | [nix-sandbox-mcp](https://github.com/secbear/nix-sandbox-mcp), [jail.nix](https://sr.ht/~alexdavid/jail.nix) |
| 3 | microvm.nix | Agent VM isolation | [microvm.nix](https://github.com/microvm-nix/microvm.nix), [Stapelberg blog](https://michael.stapelberg.ch/posts/2026-02-01-coding-agent-microvm-nix/) |
| 4 | Misterio77 | Impermanence pattern | [Misterio77/nix-config](https://github.com/Misterio77/nix-config), [nix-community/impermanence](https://github.com/nix-community/impermanence) |
| 5 | srvos + selfhostblocks | Server hardening + service modules | [srvos](https://github.com/nix-community/srvos), [selfhostblocks](https://github.com/ibizaman/selfhostblocks) |
| 6 | Mic92 + EmergentMind | Reference NixOS configs | [Mic92/dotfiles](https://github.com/Mic92/dotfiles), [EmergentMind/nix-config](https://github.com/EmergentMind/nix-config) |
| 7 | MCP messaging + OpenClaw | Agent reach-back + multi-channel | [OpenClaw](https://github.com/openclaw/openclaw), [telegram-mcp](https://github.com/chigwell/telegram-mcp), [ACFS](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup) |
| 8 | Deployment tools | deploy-rs, Colmena, comin, Clan | [deploy-rs](https://github.com/serokell/deploy-rs), [Colmena](https://github.com/zhaofengli/colmena), [comin](https://github.com/nlewo/comin) |
| 9 | Multi-node scaling | Fleet architecture + cost analysis | Colmena, NFS, JuiceFS, Hetzner/Contabo pricing |
| 10 | E2B + Docker Sandboxes | VM sandboxing platforms | [E2B](https://github.com/e2b-dev/E2B), [Docker Sandboxes](https://docs.docker.com/ai/sandboxes/), [microsandbox](https://github.com/zerocore-ai/microsandbox), [Arrakis](https://github.com/abshkbh/arrakis), [gVisor](https://gvisor.dev/) |

---

## Key Decisions Log

| ID | Decision | Rationale |
|----|----------|-----------|
| P20-01 | srvos over manual hardening | Community-maintained, covers 20+ settings neurosys is missing |
| P20-02 | gVisor over microVM (for now) | No KVM on Contabo VPS; gVisor systrap is the strongest no-KVM option |
| P20-03 | deploy-rs over Colmena (for now) | Magic rollback is critical for Tailscale-only SSH; Colmena for multi-host later |
| P20-04 | Impermanence via BTRFS (not tmpfs) | Server workloads need disk-backed root; 350 GB NVMe shouldn't waste RAM |
| P20-05 | Telegram Bot API (not Telethon user API) | Simple token, no account suspension risk, no interactive auth flow |
| P20-06 | OpenClaw deferred | 213K stars but Cisco security findings are real; overkill for current needs |
| P20-07 | selfhostblocks not recommended | Architectural mismatch (internet-facing + SSO vs Tailscale-only) |
| P20-08 | Clan not recommended | Wholesale rewrite required; Tailscale not natively supported |
| P20-09 | Secret proxy is the standout Netclode innovation | API keys should never enter sandboxes; header-only injection prevents reflection |
| P20-10 | Option B (Hetzner dedicated) for multi-host | Best balance of KVM access, cost ($110-127/mo), and capacity |
