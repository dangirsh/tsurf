# Phase 36: stereOS Ecosystem Research — Pre-Planning

**Researched:** 2026-02-27
**Purpose:** Give the planner enough information to write a tight PLAN.md for the execution agent that will do the deep-dive research and produce the final report.

---

## 1. GitHub Repos to Study

All repos live under the **papercomputeco** GitHub organization.
Creator: **John McBride** (`jpmcb`, johncodes.com) — sole contributor to stereOS/agentd/stereosd/masterblaster. Secondary contributor `bdougie` on tapes and masterblaster.

### Primary (must read deeply)

| Repo | Stars | Commits | Language | License | Created | Description |
|------|-------|---------|----------|---------|---------|-------------|
| [papercomputeco/agentd](https://github.com/papercomputeco/agentd) | 25 | 26 | Go 95% / Nix 4% | AGPL-3.0 | 2026-02 | Agent lifecycle daemon — starts, monitors, restarts agents in tmux sessions |
| [papercomputeco/masterblaster](https://github.com/papercomputeco/masterblaster) | 43 | 32 | Go 98% | AGPL-3.0 | 2026-02 | CLI + daemon for VM lifecycle, image pulling, secret injection, SSH |
| [papercomputeco/stereosd](https://github.com/papercomputeco/stereosd) | 20 | 22 | Go 92% / Nix 3% | AGPL-3.0 | 2026-02 | In-guest system daemon — secrets, mounts, SSH keys, lifecycle, shutdown |
| [papercomputeco/stereOS](https://github.com/papercomputeco/stereOS) | 232 | 25 | Nix 80% / Shell 10% / Go 6% | Not specified | 2026-02-04 | NixOS-based OS image builder — modules, mixtapes, profiles, formats |

### Secondary (skim for ideas)

| Repo | Stars | Commits | Language | Description |
|------|-------|---------|----------|-------------|
| [papercomputeco/tapes](https://github.com/papercomputeco/tapes) | 164 | 96 | Go 88% / JS 7% | Agent telemetry: durable sessions, semantic search, replay, checkpointing |
| [papercomputeco/flake-skills](https://github.com/papercomputeco/flake-skills) | 3 | — | Nix | Nix flake framework for distributing/sharing agent skills |
| [papercomputeco/skills](https://github.com/papercomputeco/skills) | 1 | — | Nix | Concrete skill definitions using flake-skills |

### Not in scope

- `daggerverse` (CI modules, not agent-related)
- `.github` / `agent-api` (description-only, no visible code)
- `tapes-ai-sdk-example` (SDK demo)

---

## 2. Key Files to Read Per Repo

### agentd (highest priority per phase context)

| File/Dir | Why |
|----------|-----|
| `main.go` | Entry point, CLI flags, config paths |
| `agentd/` (whole dir) | Core daemon: reconciliation loop, manager, harness system |
| `pkg/` (whole dir) | Shared packages — tmux wrapper, API server, types |
| `jcard.toml` | Example config showing all agent options |
| `flake.nix` | NixOS module export pattern |
| `AGENTS.md` | Development guidelines, testing framework (Ginkgo/Gomega) |

**Architecture highlights already known:**
- Reconciliation loop re-reads `jcard.toml` + secrets dir periodically
- Pluggable `Harness` interface: `Name() string`, `BuildCommand(prompt string) (bin, args)`
- Built-in harnesses: claude-code, opencode, gemini-cli, custom
- tmux sessions on dedicated socket `/run/agentd/tmux.sock`
- Restart policies: no / on-failure / always, with backoff (3s between attempts)
- Graceful shutdown: SIGINT → grace period (default 30s) → force destroy
- Read-only HTTP API on Unix socket (`/run/stereos/agentd.sock`) with `/v1/health`, `/v1/agents`, `/v1/agents/{name}`
- Secrets from `/run/stereos/secrets/` (filename=env var name, content=value)
- NixOS module: `services.agentd.enable`, `.package`, `.extraArgs`

### masterblaster (highest priority per phase context)

| File/Dir | Why |
|----------|-----|
| `main.go` | Entry point, command registration |
| `cmd/` (whole dir) | All CLI commands (pull, init, up, down, status, destroy, ssh, list, serve) |
| `pkg/daemon/` | Long-lived daemon with RWMutex-protected VM map |
| `pkg/vm/` | `Backend` interface + QEMU + Apple Virt implementations |
| `pkg/vmhost/` | Control protocol between daemon ↔ vmhost child processes |
| `pkg/vsock/` | Host-side vsock client for stereosd communication |
| `pkg/config/` | jcard.toml parsing, validation, defaults |
| `pkg/mbconfig/` | Config dir resolution (Viper-based) |
| `jcard.toml` | Example config |
| `install.sh` | Installer script (for understanding distribution) |
| `vz.entitlements` | Apple Virtualization codesigning |
| `AGENTS.md` | Architecture docs, dev guidelines |

**Architecture highlights already known:**
- Three-tier: CLI (JSON-RPC over `$config-dir/mb.sock`) → daemon (`mb serve`) → vmhost child process per VM
- Each vmhost holds hypervisor handle + control socket; survives daemon restart
- Backends: QEMU (HVF on macOS, KVM on Linux), Apple Virt (Vz.framework)
- vsock (Linux/KVM) or TCP (macOS/HVF user-mode) for guest communication
- VM state in `~/.config/mb/vms/<name>/` (state.json, disk, sockets, logs)
- Mixtape images pulled from registry, stored locally
- jcard.toml: resources (cpus/memory/disk), network (nat/bridged/none + egress allowlist), shared dirs, secrets, agent config
- `${ENV_VAR}` interpolation in secrets and paths
- 11 releases, latest v0.0.1-rc.10 (2026-02-24)

### stereosd

| File/Dir | Why |
|----------|-----|
| `main.go` | Entry point |
| All Go source dirs | State machine, NDJSON wire protocol, subsystems |
| `flake.nix` | NixOS module pattern |

**Architecture highlights already known:**
- State machine: booting → ready → healthy/degraded → shutdown
- NDJSON over vsock/TCP, 1MB message limit
- Message types: ping, get_health, set_config, inject_secret, inject_ssh_key, mount, shutdown, lifecycle
- Subsystems: SecretManager (atomic writes to tmpfs, memory zeroing), SSHKeyManager, MountManager (virtiofs/9p), LifecycleManager, AgentdClient (polls agentd every 5s), ShutdownCoordinator
- Secrets in `/run/stereos/secrets/` (tmpfs, 0700, root:root), never persisted to disk
- Mount validation: prevents overlay of system dirs (/nix, /etc, /bin, /boot, /dev, /proc, /sys, /run)
- NixOS module: `services.stereosd.enable`, `.package`, `.listenMode` (auto/vsock/tcp), `.extraArgs`

### stereOS (the OS image builder)

| File/Dir | Why |
|----------|-----|
| `flake.nix` | Inputs (nixpkgs, flake-parts, dagger, agentd, stereosd), outputs, nixosConfigurations |
| `modules/default.nix` | Module aggregator: base.nix, boot.nix, services/{stereosd,agentd}.nix, users/{agent,admin}.nix |
| `modules/base.nix` | System identity, SSH (key-only, no root), Nix access control (agent excluded), system packages, firewall (SSH only), kernel hardening (ptrace=2, kptr hidden, dmesg restricted, cores off) |
| `modules/boot.nix` | Sub-3s boot optimization: systemd initrd, virtio modules only, no getty, volatile journal (32M), tight timeouts |
| `modules/users/agent.nix` | **Critical:** Curated PATH via `stereos-agent-shell` wrapper, all Nix vars nuked, sudo explicitly denied, workspace at `/home/agent/workspace` |
| `modules/users/admin.nix` | Three-tier privilege model: root > admin > agent |
| `modules/services/agentd.nix` | stereOS-specific overrides: after/requires stereosd, DynamicUser=false |
| `modules/services/stereosd.nix` | stereOS-specific: runtime dirs, firewall port 1024 (TCP fallback), kernel module ordering |
| `profiles/base.nix` | Shared profile importing image format modules |
| `profiles/dev.nix` | SSH key injection for dev builds |
| `lib/default.nix` | `mkMixtape` helper: assembles nixosSystem from modules + overlays + features |
| `lib/dist.nix` | `mkDist`: builds distribution packages with zstd compression + SHA-256 manifests |
| `formats/raw-efi.nix` | Raw EFI disk image (canonical artifact) |
| `mixtapes/opencode/base.nix` | Pattern: `stereos.agent.extraPackages = [ pkgs.opencode ]` |
| `mixtapes/claude-code/base.nix` | Same pattern for claude-code |

### tapes (secondary)

| File/Dir | Why |
|----------|-----|
| `README.md` | Understand telemetry model, session durability, semantic search |
| `cli/` | CLI commands for chat, search, checkout |
| `proxy/` | Proxy that intercepts LLM traffic for recording |
| `api/` | API for session management |

### flake-skills (secondary)

| File/Dir | Why |
|----------|-----|
| `README.md` + source | Skill distribution via Nix flakes — `mkSkillsFlake`, `mkSkillsHook`, composition model |

---

## 3. Specific Questions the Report Must Answer

### Agent Orchestration (Priority 1)

1. **How does agentd's reconciliation loop compare to neurosys's `agent-spawn`?** agentd is a persistent daemon that watches config changes and manages restarts; agent-spawn is a one-shot script that creates a bwrap sandbox + zmx session. What are the tradeoffs?
2. **Is agentd's harness abstraction portable?** Could we use the Harness interface concept (Name/BuildCommand) in agent-spawn without adopting the full daemon model?
3. **How does agentd handle multi-agent scenarios?** Can it run multiple agents simultaneously? (jcard appears to define a single `[agent]` block)
4. **What does the tmux-based session management offer over zmx?** agentd uses tmux with dedicated socket + sudo for session ownership; neurosys uses zmx.
5. **How does the agentd restart policy compare to systemd Restart= directives?** Could neurosys achieve the same via systemd service units instead of a custom daemon?

### System Configuration (Priority 2)

6. **How does stereOS's module structure compare to neurosys's?** Both are NixOS + flakes. stereOS has a simpler module tree (6 files vs. neurosys's 15+). What is gained/lost?
7. **Is stereOS's agent user model (`stereos-agent-shell` with curated PATH) stronger than neurosys's bubblewrap sandbox?** stereOS: user-level isolation via restricted shell + sudo denial + separate user. Neurosys: namespace isolation via bwrap (PID, IPC, UTS, cgroup, user). Different threat models?
8. **How does stereOS's `stereos.agent.extraPackages` pattern compare to neurosys's approach?** stereOS builds a `pkgs.buildEnv` with curated binaries; neurosys puts everything in system PATH and restricts via bwrap bind mounts.
9. **Is stereOS's boot optimization (sub-3s with systemd initrd, no getty, virtio-only) useful for neurosys?** Neurosys runs on a persistent VPS, not ephemeral VMs — boot time is less critical, but the hardening patterns might apply.

### Deployment Mechanics (Priority 3)

10. **How does masterblaster's CLI + daemon + vmhost architecture compare to deploy-rs?** Fundamentally different: mb manages VM lifecycle; deploy-rs manages NixOS activation. But the daemon pattern and state tracking have design lessons.
11. **Can neurosys adopt masterblaster for agent sandboxing instead of bwrap?** Full VM isolation vs. namespace isolation. Tradeoff: security strength vs. overhead and KVM requirement.
12. **Does stereOS's image distribution model (mixtapes via registry + SHA-256 manifests) offer advantages over neurosys's `nixos-rebuild switch`?** Immutable images vs. mutable system activation.

### Self-Hosting Philosophy (Priority 4)

13. **What is stereOS's secrets management model vs. neurosys's sops-nix?** stereOS: secrets injected over vsock at boot into tmpfs, never on disk. Neurosys: sops-nix decrypts at activation into `/run/secrets/`.
14. **How does stereOS handle network egress control?** jcard supports `egress_allow` domain/CIDR allowlist. Neurosys has no agent network sandboxing (noted as accepted risk).
15. **Is tapes (agent telemetry) something neurosys should adopt?** Session durability, semantic search, replay — could improve agent observability.
16. **Is flake-skills useful for neurosys's agent skill distribution?** Currently neurosys uses `.claude/skills/` directly; flake-skills adds Nix-mediated distribution.

### Switch Recommendation

17. **Can stereOS run on Contabo VPS (no KVM/nested virtualization)?** This is a potential deal-breaker. stereOS requires full VM support (QEMU+KVM). Contabo VPS does not expose KVM. The OVH VPS status is unknown.
18. **What would partial adoption look like?** Adopting agentd + stereosd patterns without full VM isolation — running them on the host NixOS directly.
19. **What are the non-negotiable gaps?** Declarative system config (stereOS is NixOS-based, so parity), encrypted secrets (vsock injection vs. sops-nix — different model), agent sandboxing (VM vs. bwrap), minimal cloud dependency (self-hosted), rollback safety (stereOS is image-based disposable VMs — different rollback concept).

---

## 4. Recommended Report Structure

```
# stereOS Ecosystem Research Report

## Executive Summary
- One-paragraph verdict: Switch / Partial adoption / Stay
- Key finding highlights (3-5 bullets)

## 1. Ecosystem Overview
- Organization maturity (single-developer, <1 month old, pre-release)
- Component diagram (mb → vmhost → [stereOS VM: stereosd → agentd → agent])
- Comparison table: stereOS components vs. neurosys equivalents

## 2. Deep Dive: Agent Orchestration (agentd)
- Architecture analysis with code references
- Harness abstraction
- Lifecycle management (start/monitor/restart/stop)
- API surface
- Comparison to agent-spawn

## 3. Deep Dive: System Daemon (stereosd)
- State machine and wire protocol
- Secret injection model
- Mount management
- Comparison to sops-nix + systemd activation

## 4. Deep Dive: CLI Orchestrator (masterblaster)
- Three-tier architecture
- VM backend abstraction
- jcard configuration model
- Comparison to deploy-rs + agent-spawn

## 5. Deep Dive: OS Image Builder (stereOS)
- Module structure comparison with neurosys
- Agent user isolation (restricted shell vs. bwrap)
- Boot optimization and hardening
- Mixtape build pipeline

## 6. Secondary Components
- tapes (telemetry)
- flake-skills (skill distribution)

## 7. Adoption Table
| Concept | What It Is | Why It Matters for Neurosys | Adoption Difficulty | Decision |
(concrete rows for each stealable idea)

## 8. Switch Recommendation
- Non-negotiable evaluation (5 criteria with pass/fail)
- KVM blocker analysis
- Tier recommendation with justification

## 9. Action Items
- Concrete new phases or TODOs if adoption warranted
- Priority ordering
```

---

## 5. Repo Maturity Signals

| Signal | Assessment |
|--------|------------|
| **Age** | All repos created February 2026 — less than 1 month old |
| **Stars** | stereOS: 232, tapes: 164, masterblaster: 43, agentd: 25, stereosd: 20 |
| **Contributors** | Essentially single-developer (jpmcb = John McBride). bdougie on tapes/masterblaster only |
| **Release maturity** | masterblaster at v0.0.1-rc.10 (11 releases in 6 days, Feb 18-24). Pre-release quality |
| **Commit volume** | Low total commits (22-32 per repo). Rapid iteration but limited history |
| **Test coverage** | AGENTS.md mentions Ginkgo/Gomega (Go BDD). Hurl files visible in stereosd (HTTP API tests) |
| **Documentation** | README quality is good. AGENTS.md serves as architecture docs. No external docs site |
| **CI/CD** | Dagger-based CI. GitHub Actions visible. Automated releases |
| **License** | AGPL-3.0 across all repos (copyleft — important for adoption decisions) |
| **Community** | Discord server exists. HN post appeared 2026-02-27 (very fresh). No visible issues/discussions beyond 4 open issues on stereOS |

**Assessment:** Very early-stage project with solid engineering fundamentals (NixOS-native, clean Go code, good README docs) but pre-release maturity. Single-developer risk is high. AGPL-3.0 license means any modifications to stereOS code must be open-sourced if distributed.

---

## 6. External Resources

### Official

- **Website:** https://stereos.ai/
- **Company:** https://papercompute.com/ — "Durable AI Agent Infrastructure" — Oakland, CA
- **Discord:** https://discord.gg/T6Y4XkmmV5
- **Install script:** https://mb.stereos.ai/install

### Hacker News

- [Stereos.ai](https://news.ycombinator.com/item?id=47173998) — posted 2026-02-27 by `hasheddan`, 4 points (very fresh, minimal discussion)

### Related Reading (comparison context)

- [Coding Agent VMs on NixOS with microvm.nix](https://michael.stapelberg.ch/posts/2026-02-01-coding-agent-microvm-nix/) — Michael Stapelberg's approach: microVMs on NixOS for agent isolation
- [How to sandbox AI agents in 2026: MicroVMs, gVisor & isolation strategies](https://northflank.com/blog/how-to-sandbox-ai-agents) — Northflank overview of isolation tiers
- [A thousand ways to sandbox an agent](https://michaellivs.com/blog/sandbox-comparison-2026/) — Comparative analysis of sandboxing approaches
- [I Built a Reasonably Secure OpenClaw Box with NixOS and microVMs](https://dev.to/ryoooo/i-built-a-reasonably-secure-openclaw-box-with-spare-pc-parts-nixos-and-microvms-2177) — Community build with microvm.nix

### Creator

- **John McBride** (`jpmcb`) — https://johncodes.com — sole developer of stereOS/agentd/stereosd/masterblaster

---

## 7. Critical Blockers for Neurosys

### KVM Requirement

stereOS's entire isolation model depends on hardware-accelerated VMs (QEMU + KVM on Linux, HVF on macOS). The neurosys Contabo VPS **does not support KVM/nested virtualization** (documented in MEMORY.md: "No nested virtualization (KVM) — Contabo VPS doesn't expose it"). This means:

- `mb up` cannot launch VMs on the current neurosys server
- The OVH VPS KVM status is unknown and should be checked
- This is a hard blocker for full stereOS adoption but does NOT block adopting design patterns, the agentd daemon concept, or the harness abstraction

### AGPL-3.0 License

All stereOS repos are AGPL-3.0. If neurosys were to modify and distribute stereOS code, those modifications must be open-sourced. For a private server config repo this is unlikely to matter (server-side use is generally not "distribution" under AGPL), but it's worth noting if any stereOS code were to be incorporated into neurosys's codebase.

---

## 8. Planning Guidance

The execution agent should:

1. **Clone all 4 primary repos** into `tmp/` for local source reading (faster than GitHub web fetching)
2. **Read source files** in priority order: agentd internals → masterblaster internals → stereosd internals → stereOS modules
3. **Run `nix flake show`** on each repo to understand the flake output surfaces
4. **Focus comparison on:** agentd's harness/reconciliation vs. agent-spawn, stereosd's secret injection vs. sops-nix, stereOS's agent user isolation vs. bwrap, masterblaster's egress control vs. neurosys's lack thereof
5. **Produce the adoption table** with concrete difficulty ratings (trivial/moderate/hard/impractical)
6. **Address the KVM blocker explicitly** in the switch recommendation
7. **Check OVH VPS KVM support** if possible (`grep -c vmx /proc/cpuinfo` or `kvm-ok`)
8. **Time budget:** ~60min for source reading across 4 repos + ~30min for report writing

### Suggested Plan Shape

- **Plan 36-01** (single plan): Read all repos, write the report, produce adoption table and switch recommendation
- No implementation work — pure research output
- Output file: `.planning/phases/36-research-stereos-ecosystem/36-REPORT.md`
