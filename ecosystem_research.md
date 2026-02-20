# Neurosys Ecosystem Research

Deep research across 60+ projects to identify tools, patterns, and libraries worth adopting. Conducted 2026-02-20 via 10 parallel research agents. Full detailed report at `.planning/phases/20-deep-ecosystem-research/20-01-SUMMARY.md`.

## Do Now (high impact, low effort)

### 1. srvos Server Profile

**What:** [nix-community/srvos](https://github.com/nix-community/srvos) — battle-tested NixOS server defaults.

**Why:** Neurosys is missing ~20 hardening improvements:

| Setting | What it does |
|---------|-------------|
| `RuntimeWatchdogSec = "15s"` | Hardware reboot if systemd hangs |
| `systemd.enableEmergencyMode = false` | Don't drop to shell on headless server |
| `AllowSuspend=no` | Prevent accidental suspend |
| `nix.daemonCPUSchedPolicy = "batch"` | Builds don't starve services |
| `nix.daemonIOSchedClass = "idle"` | Same for I/O |
| `OOMScoreAdjust = 250` (nix-daemon) | OOM kills builds before services |
| `min-free = 512MB` / `max-free = 3GB` | Auto-GC when disk is low |
| `LLMNR = "false"` | Prevent LLMNR poisoning |
| `logRefusedConnections = false` | Reduce scanner noise |
| `boot.tmp.cleanOnBoot = true` | Clean /tmp on boot |
| `nix.channel.enable = false` | No legacy channels with flakes |
| `preSwitchChecks.update-diff` | `nvd diff` before switching |
| `preSwitchChecks.detectHostnameChange` | Prevent deploying to wrong host |
| `knownHosts` for github.com, gitlab.com | No TOFU MITM risk |
| Documentation/fonts/XDG disabled | Smaller closure, faster eval |

**Effort:** Add `srvos` as flake input, import `srvos.nixosModules.server`, remove ~15 redundant settings.

**Risk:** `networking.useNetworkd = true` (srvos default) needs testing with Contabo static IP. Override with `lib.mkForce false` if it breaks.

### 2. Sandbox PID + Cgroup Isolation

**What:** Add `--unshare-pid` and `--unshare-cgroup` to agent-spawn bubblewrap flags.

**Why:** Currently sandboxed agents can see all host processes via `/proc` and inspect the host cgroup hierarchy. nix-sandbox-mcp ([secbear/nix-sandbox-mcp](https://github.com/secbear/nix-sandbox-mcp)) via [jail.nix](https://sr.ht/~alexdavid/jail.nix) unshares all six namespaces by default.

**What neurosys does better:** `--disable-userns` (prevents nested namespace attacks) — nix-sandbox-mcp doesn't use this.

**Effort:** 2 flags added to `BWRAP_ARGS` in `modules/agent-compute.nix`.

### 3. gVisor for Docker Containers

**What:** Add [gVisor](https://gvisor.dev/) (runsc) with systrap platform as a Docker OCI runtime.

**Why:** All microVM solutions (E2B/Firecracker, Kata, microsandbox, Arrakis) require KVM which Contabo VPS doesn't have. gVisor with systrap intercepts syscalls in user-space — a separate kernel without hardware virtualization. Under 3% overhead.

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

**Isolation hierarchy:**
```
Bubblewrap     →  gVisor/systrap     →  microVM (KVM)
(namespaces)      (user-space kernel)    (separate kernel)
[agents now]      [VIABLE NOW]           [needs $46-55/mo extra]
```

### 4. Telegram Bot for Agent Notifications

**What:** Minimal Telegram Bot API integration so agents can notify the operator.

**Why:** Currently no agent reach-back mechanism. ACFS has the same gap — agents can't proactively notify users.

**Integration:**
```nix
notify-telegram = pkgs.writeShellApplication {
  name = "notify-telegram";
  runtimeInputs = [ pkgs.curl pkgs.jq ];
  text = ''
    TOKEN="$(cat /run/secrets/telegram-bot-token)"
    CHAT_ID="$(cat /run/secrets/telegram-chat-id)"
    curl -s -X POST "https://api.telegram.org/bot$TOKEN/sendMessage" \
      -d chat_id="$CHAT_ID" -d text="$1"
  '';
};
```

- Bot API (not Telethon user API) — simple token, no account suspension risk
- Outbound HTTPS only — no inbound ports
- 2 sops secrets: `telegram-bot-token`, `telegram-chat-id`

**Later:** Wrap as MCP server for bidirectional messaging. Then [OpenClaw](https://github.com/openclaw/openclaw) (213K stars, [nix-openclaw](https://github.com/openclaw/nix-openclaw) flake) for multi-channel (Telegram + Signal + WhatsApp + 19 more). Has first-class Tailscale integration.

### 5. deploy-rs Magic Rollback

**What:** [deploy-rs](https://github.com/serokell/deploy-rs) alongside existing deploy.sh.

**Why:** For a Tailscale-only server, a misconfigured firewall or networking change locks you out. deploy-rs auto-rolls back via inotify canary if the deployer can't SSH back within the confirmation timeout.

**How it works:**
1. Activates new profile on target
2. Creates canary file, starts inotify watcher
3. Deployer must SSH back and delete canary within timeout (default 30s)
4. If canary isn't deleted → automatic rollback to previous generation

**Integration (15 lines):**
```nix
inputs.deploy-rs.url = "github:serokell/deploy-rs";

deploy.nodes.neurosys = {
  hostname = "neurosys";
  profiles.system = {
    user = "root";
    path = deploy-rs.lib.x86_64-linux.activate.nixos
      self.nixosConfigurations.neurosys;
  };
};
```

deploy.sh evolves into a wrapper: `nix flake update parts && deploy .#neurosys --confirm-timeout 120 && <container health check>`.

**Comparison:**

| Tool | Magic Rollback | Multi-host | Recommendation |
|------|---------------|-----------|----------------|
| deploy.sh (current) | No | No | Keep for single-host |
| deploy-rs | **Yes** | Yes | Add for safety |
| Colmena | No | Yes (10x parallel) | Add when multi-host |
| comin (GitOps) | No | N/A | Skip (paradigm shift) |
| Clan | No | Yes | Skip (wholesale rewrite) |

---

## Do When Ready (dedicated phases)

### 6. Impermanence (Ephemeral Root)

**What:** [nix-community/impermanence](https://github.com/nix-community/impermanence) — wipe root filesystem on every boot. Only explicitly declared paths survive via bind-mounts from `/persist`.

**Why:**
- **Drift-proof** — undeclared state can't accumulate
- **Explicit state manifest** — `environment.persistence` declares every stateful path
- **Smaller backups** — back up `/persist` instead of entire root
- **Simpler disaster recovery** — restore `/persist` from restic, reboot, done

**Recommended approach** (from [Misterio77/nix-config](https://github.com/Misterio77/nix-config)): BTRFS subvolumes + initrd rollback to blank snapshot (not tmpfs — server workloads need disk-backed root).

```
/       → btrfs subvol "root"    (WIPED on boot)
/nix    → btrfs subvol "nix"     (persistent)
/persist → btrfs subvol "persist" (persistent, neededForBoot=true)
```

**Critical steps:**
- Re-point sops age key to `/persist/etc/ssh/ssh_host_ed25519_key`
- Per-service persistence declarations in each module (distributed pattern)
- Restic backup path: `/` → `/persist`

**Effort:** High — requires disk reprovisioning (nixos-anywhere redeploy). Test in VM first.

### 7. Secret Proxy (Netclode Pattern)

**What:** Two-tier proxy where real API keys never enter agent sandboxes. From [Netclode](https://github.com/nichochar/netclode), inspired by [Fly's Tokenizer](https://github.com/superfly/tokenizer).

**How it works:**
```
Agent (inside sandbox)
  → sees ANTHROPIC_API_KEY=PLACEHOLDER, HTTP_PROXY=localhost:8080
  → auth-proxy adds bearer token, forwards to...
Secret-proxy (outside sandbox)
  → validates agent identity
  → replaces PLACEHOLDER in HTTP headers only (not body — prevents reflection)
  → forwards to api.anthropic.com
```

**Key properties:**
- Header-only injection (prevents reflection attacks)
- Per-session SDK-type allowlisting (Claude → anthropic.com only)
- Blocking on validation failure (placeholder never leaks)

**Effort:** Medium — small Go/Rust proxy service + NixOS module.

### 8. microvm.nix Agent VMs

**What:** [microvm.nix](https://github.com/microvm-nix/microvm.nix) — NixOS systems as lightweight VMs. Each agent gets its own kernel.

**Reference:** [Stapelberg's blog post](https://michael.stapelberg.ch/posts/2026-02-01-coding-agent-microvm-nix/) (Feb 2026) — per-agent ephemeral VMs with 8 vCPU, 4 GB RAM, 4 virtiofs shares (`/nix/store` ro, SSH keys, credentials, workspace rw).

**Blocker:** No KVM on Contabo VPS. Options:
- Contabo VDS (~$46/mo) — has KVM
- Hetzner Dedicated AX42 (~$55/mo) — bare metal, full KVM

**Adopt patterns now (no KVM needed):**
- Modular per-agent config (replace monolithic agent-spawn)
- Formalize 4-share workspace isolation model as data structure
- Consider systemd-nspawn as middle ground (stronger than bwrap, no KVM)

### 9. Multi-Host with Colmena

**What:** [Colmena](https://github.com/zhaofengli/colmena) — stateless multi-host NixOS deployment with tag-based filtering and parallel deploys.

**Architecture options:**

| Option | Nodes | KVM | Cost/mo | Effort |
|--------|-------|-----|---------|--------|
| A: Minimal (2 Contabo) | Services + overflow | No | $63-71 | 2-3 phases |
| **B: Agent-optimized** | Contabo + Hetzner dedicated | **Yes** | $110-127 | 3-4 phases |
| C: Full fleet (3+) | Ingress + services + compute | Yes | $108+ | 5-6 phases |

**Recommended:** Option B when agent isolation matters.

**Prerequisites (do now regardless):**
1. Split `modules/default.nix` into common/ vs service-specific
2. Parameterize host-specific values (hardcoded Tailscale IP in homepage.nix)
3. Template `.sops.yaml` for multi-host key groups

### 10. OpenClaw Multi-Channel Messaging

**What:** [OpenClaw](https://github.com/openclaw/openclaw) (213K stars) — Gateway architecture connecting 22+ messaging platforms. [nix-openclaw](https://github.com/openclaw/nix-openclaw) provides Home Manager module for x86_64-linux.

**Channels:** Telegram, WhatsApp, Signal, Discord, Slack, iMessage, Matrix, IRC, LINE, Google Chat, + 12 plugins.

**Tailscale integration:** First-class — `gateway.tailscale.mode: "serve"` for tailnet-only HTTPS.

**Caution:** Cisco security audit found critical vulnerabilities (data exfiltration, prompt injection, command injection). Only use vetted skills.

**When:** After neurosys has a concrete need for multi-channel messaging beyond Telegram.

---

## Skip

| Project | Why Skip |
|---------|----------|
| [selfhostblocks](https://github.com/ibizaman/selfhostblocks) | Designed for internet-facing services with SSO/nginx/OIDC. Neurosys is Tailscale-only. Patches nixpkgs, tracks unstable. |
| [Clan](https://github.com/clan-lol/clan-core) | Requires wholesale flake rewrite. Tailscale not natively supported. 148 stars, immature. |
| [E2B self-hosted](https://github.com/e2b-dev/E2B) | Nomad/Consul/Terraform — designed for multi-tenant cloud platforms, overkill for single-tenant. |
| Docker AI Sandboxes | microVM mode needs Docker Desktop (not Engine). Linux support experimental, single-user only. |
| comin (GitOps) | 60s polling latency. Server needs GitHub repo access. `nix flake update parts` workflow doesn't map to pull model. |
| Retiolum/tinc | Tailscale is strictly better (NAT traversal, MagicDNS, identity-based ACLs). |
| buildbot-nix | Overkill for single server. GitHub Actions + `nix flake check` suffices. |

---

## Reference Config Patterns

From [Mic92/dotfiles](https://github.com/Mic92/dotfiles) and [EmergentMind/nix-config](https://github.com/EmergentMind/nix-config):

**Worth adopting:**
- srvos layered integration (common + server + mixins per host)
- Flake checks that build machine configs: `checks.x86_64-linux.nixos-neurosys = self.nixosConfigurations.neurosys.config.system.build.toplevel`
- DevShell with sops + age + deploy tooling
- treefmt-nix for consistent formatting (nixfmt + shellcheck)
- `self` reference pattern (access inputs via `self.inputs.*` instead of specialArgs)

**Useful when growing:**
- Private nix-secrets repo (if repo goes public)
- Shared vs per-host sops YAML files
- Separate installer sub-flake for fast bootstrapping
- flake-parts architecture for multi-concern decomposition

---

## Key Decisions

| ID | Decision | Rationale |
|----|----------|-----------|
| P20-01 | srvos over manual hardening | Community-maintained, covers 20+ missing settings |
| P20-02 | gVisor over microVM (for now) | No KVM on Contabo; systrap is strongest no-KVM option |
| P20-03 | deploy-rs over Colmena (for now) | Magic rollback critical for Tailscale-only SSH |
| P20-04 | Impermanence via BTRFS (not tmpfs) | Server workloads need disk-backed root |
| P20-05 | Telegram Bot API (not Telethon) | Simple token, no account suspension risk |
| P20-06 | OpenClaw deferred | Cisco security findings are real; overkill for current needs |
| P20-07 | selfhostblocks skip | Architectural mismatch with Tailscale-only model |
| P20-08 | Secret proxy is standout innovation | API keys should never enter sandboxes |
| P20-09 | Option B for multi-host | Best balance: Hetzner dedicated for KVM ($110-127/mo) |
| P20-10 | gVisor upgrade path | bubblewrap → gVisor/systrap → microvm.nix (when KVM available) |
