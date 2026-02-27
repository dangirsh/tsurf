# stereOS Ecosystem Research Report

**Phase:** 36-research-stereos-ecosystem
**Plan:** 36-01
**Date:** 2026-02-27
**Researcher:** Implementation agent
**Repos studied:** agentd, masterblaster, stereosd, stereOS, tapes, flake-skills (all shallow clones from papercomputeco GitHub org)

---

## Executive Summary

**Tier: Partial Adoption** — the stereOS ecosystem contains several high-quality patterns worth stealing, but full migration from neurosys to stereOS is blocked by the KVM requirement on Contabo and by the pre-release maturity of the project.

**Key findings:**

- agentd's reconciliation-loop daemon model is a concrete, well-engineered upgrade over neurosys's one-shot `agent-spawn` script; it is adoptable as a NixOS service without requiring VMs.
- stereosd's NDJSON wire protocol and secret injection model is purpose-built for VM-based secret delivery; neurosys's sops-nix activation model is architecturally superior for a persistent VPS.
- stereOS's `stereos-agent-shell` (restricted PATH, sudo denial, separate `agent` user) provides user-level isolation that is complementary to, not stronger than, bubblewrap namespace isolation.
- masterblaster requires KVM (QEMU + hardware virtualization) — this is a hard blocker for Contabo VPS (no nested virtualization).
- The jcard.toml config schema and Harness abstraction are both portable ideas worth stealing even without adopting the full stack.
- All repos are pre-release (created February 2026, sole developer), which means production adoption carries significant upstream risk.

**KVM blocker impact:** `mb up` cannot function on Contabo VPS, eliminating full stereOS VM-based isolation as an option. The OVH VPS (neurosys-prod) KVM status is unverified but likely available since OVH typically exposes hardware virtualization in their cloud offerings.

---

## 1. Ecosystem Overview

### Organization Maturity

| Signal | Assessment |
|--------|------------|
| Age | All repos created February 2026 — less than 4 weeks old |
| Stars | stereOS: 232, tapes: 164, masterblaster: 43, agentd: 25, stereosd: 20 |
| Contributors | Essentially single-developer: John McBride (jpmcb). bdougie contributed to tapes/masterblaster only |
| Release maturity | masterblaster at v0.0.1-rc.10 (11 releases in 6 days, Feb 18-24). Pre-release quality |
| Commit volume | 22-32 commits per repo. Rapid iteration, limited history |
| Test coverage | Ginkgo/Gomega BDD framework. Hurl integration tests in stereosd. Real unit tests in agentd/manager_test.go |
| License | AGPL-3.0 across all repos (copyleft — relevant if distributing modifications) |
| Community | Discord server. HN post 2026-02-27 (very fresh, minimal discussion) |

**Assessment:** Very early stage. Engineering quality is high (clean Go, good docs, test coverage, flakes). Single-developer risk is real. Production adoption would mean coupling to an upstream that may pivot, stall, or break APIs without notice.

### Component Architecture

```
Host machine
└── mb (CLI) ──JSON-RPC──> mb serve (daemon) ──socket──> vmhost (child process per VM)
                                                              │
                                                              └── QEMU/KVM ──> stereOS VM
                                                                        │
                                                                        ├── stereosd (guest daemon)
                                                                        │    ├── vsock wire protocol (NDJSON)
                                                                        │    ├── SecretManager (tmpfs)
                                                                        │    └── MountManager (virtiofs/9p)
                                                                        │
                                                                        └── agentd (agent daemon)
                                                                             ├── reconciliation loop (5s)
                                                                             ├── Harness interface
                                                                             ├── tmux session management
                                                                             └── HTTP API (Unix socket)
```

### Comparison Table: stereOS vs. neurosys

| stereOS Component | neurosys Equivalent | Notes |
|---|---|---|
| masterblaster (`mb`) | deploy.sh | mb = VM lifecycle; deploy.sh = NixOS activation. Different problems |
| stereosd | sops-nix activation | Secrets: vsock injection vs. age decryption at activation |
| agentd | agent-spawn script | Daemon vs. one-shot. agentd has restart policy + API; agent-spawn does not |
| stereOS modules | neurosys/modules/ | Both NixOS-native; stereOS simpler (6 files vs. 15+), purpose-built for VMs |
| stereos-agent-shell | bubblewrap sandbox | User isolation vs. namespace isolation. Different threat models |
| jcard.toml | agent-spawn CLI args | jcard = declarative config; agent-spawn = imperative args |
| tapes | (no equivalent) | Agent telemetry/session recording not implemented in neurosys |
| flake-skills | .claude/skills/ direct | Nix-mediated distribution vs. direct filesystem skills |

---

## 2. Deep Dive: agentd (Agent Orchestration)

**Q1, Q2, Q3, Q4, Q5 addressed here.**

agentd is the highest-value repo in the stereOS ecosystem for neurosys. It is a thoughtfully engineered Go daemon with clean interfaces, real tests, and a clear design philosophy.

### Architecture and Core Design

**Entry point** (`main.go`): Minimal — parses four flags (`-config`, `-api-socket`, `-secret-dir`, `-tmux-socket`, `-debug`) and delegates to `agentd.NewDaemon()`. Signal handling via `signal.NotifyContext` for `SIGINT`/`SIGTERM`.

**Daemon struct** (`agentd/agentd.go:64-82`): Holds config/secret paths, reconcile interval, and guarded runtime state (`mu sync.Mutex`, `manager *manager.Manager`, `tmux *tmux.Server`, `apiServer *api.Server`). Two hash fields (`lastConfigHash`, `lastSecretHash`) track whether config or secrets have changed since the last reconciliation.

**Q1: Reconciliation loop vs. agent-spawn**

agentd runs `reconcileLoop()` (agentd/agentd.go:200-215) which ticks every 5 seconds (configurable via `DefaultReconcileInterval = 5 * time.Second`). On each tick, `reconcile()` (agentd/agentd.go:220-311):

1. Reads jcard.toml from disk as raw bytes
2. Reads all files from `/run/stereos/secrets/` into a `map[string]string`
3. Computes SHA-256 hashes of config bytes and secret contents
4. If hashes unchanged and manager exists: returns (no-op)
5. If changed: stops the old manager, creates a new one

This is fundamentally different from neurosys's `agent-spawn`:

| Property | agentd | agent-spawn |
|---|---|---|
| Lifecycle model | Long-running daemon | One-shot bash script |
| Restart policy | `no` / `on-failure` / `always` with configurable max restarts | None (manual re-run) |
| Config watching | Hash-based reconciliation every 5s | Static at launch time |
| Secret updates | Detected by hash, agent restarted | Static at launch time |
| Multi-agent | No (single `[agent]` block per jcard.toml) | Yes (multiple zmx sessions, separate invocations) |
| Supervision | Polls tmux `has-session` every 2s | No supervision after launch |
| API | HTTP over Unix socket `/run/stereos/agentd.sock` | No API surface |
| Session type | tmux (dedicated socket `/run/agentd/tmux.sock`) | zmx |
| Sandboxing | None (runs as `agent` user) | bubblewrap namespaces |

**Q2: Harness abstraction portability**

The `Harness` interface (`pkg/harness/harness.go:12-20`) is minimal and portable:
```go
type Harness interface {
    Name() string
    BuildCommand(prompt string) (bin string, args []string)
}
```
Registry of built-in harnesses (`pkg/harness/harness.go:23-28`): `claude-code`, `opencode`, `gemini-cli`, `custom`. ClaudeCode implementation (`pkg/harness/claudecode.go`): `BuildCommand` returns `claude` with `-p <prompt>` when prompt non-empty, bare `claude` for interactive mode.

The Harness interface concept is directly portable to agent-spawn as a conceptual model. Neurosys could adopt the idea of a typed harness registry without adopting the full daemon — currently `agent-spawn` uses `case "$AGENT" in` to pick the command, which is the bash equivalent.

**Q3: Multi-agent scenarios**

agentd manages a single agent (one `[agent]` block per jcard.toml). The `AgentStatuses()` method (`agentd/agentd.go:127-138`) explicitly notes "currently at most one":
```go
return []api.AgentStatus{d.manager.Status()}  // single item slice
```
Multi-agent scenarios in stereOS require multiple jcard.toml files and separate `mb up` invocations per VM. In neurosys, `agent-spawn` is stateless and can be called multiple times to create multiple zmx sessions — already superior for multi-agent.

**Q4: tmux vs. zmx**

agentd's tmux management (`pkg/tmux/tmux.go`):
- Dedicated socket at `/run/agentd/tmux.sock` (isolated from user tmux sessions)
- Sessions run as `agent` user via `sudo -u agent tmux` (tmux enforces UID socket ownership)
- `CreateSession` creates a bare shell, then uses `send-keys` to type the command — this means if the command exits, the shell stays alive for inspection
- Admin attaches via `sudo tmux -S /run/agentd/tmux.sock attach`
- Socket permissions: 0770, group `admin`

zmx (neurosys's choice) is a lighter terminal multiplexer. The tmux approach gives richer session introspection (admin can attach and observe). For neurosys, zmx works fine but switching to tmux would gain the admin-attach pattern via dedicated socket.

**Q5: systemd Restart= vs. agentd restart policy**

agentd's restart policy (`pkg/manager/manager.go:289-314`) implements `no` / `on-failure` / `always` with `MaxRestarts` cap and 3-second backoff. The `shouldRestart()` function acknowledges a known limitation: tmux `has-session` exit code does not distinguish exit 0 from non-zero, so `on-failure` effectively behaves like `always`.

Could systemd replace this? Yes, with caveats:
- `systemd.services.agent.Restart = "on-failure"` handles restarts natively
- systemd `RestartSec` covers the backoff
- systemd `StartLimitIntervalSec` / `StartLimitBurst` cap restart attempts
- BUT systemd would restart the entire process, not just the tmux session

agentd's reconciliation-loop adds config/secret watching — not something systemd does natively. If config or secrets change, agentd restarts the agent automatically. With systemd you'd need a separate inotify-based service or external trigger.

**Q5 verdict:** Systemd can replace agentd's restart policy, but not its config-watching reconciliation. For a persistent VPS with static config, systemd alone suffices. For dynamic config/secret updates, agentd adds value.

### HTTP API

API server (`pkg/api/api.go`):
- Unix socket at `/run/stereos/agentd.sock` (0660, group `admin`)
- `GET /v1/health` → `{"state": "running", "uptime_seconds": N}`
- `GET /v1/agents` → `[{"name": ..., "running": bool, "session": ..., "restarts": N, "error": ...}]`
- `GET /v1/agents/{name}` → single agent status or 404

This API surface is valuable for monitoring integration. neurosys could query it from Prometheus (with a custom exporter) or from scripts. The API is clean and Prometheus-ready.

### NixOS module

agentd's NixOS module (`flake.nix:22-58`):
- `services.agentd.enable`, `.package`, `.extraArgs`
- `DynamicUser = true` (sandboxes agentd itself in systemd)
- `path = [ pkgs.tmux pkgs.sudo ]` (runtime dependencies)
- `Restart = "always"` (daemon restarts if it crashes)

**Notable tension:** The stereOS-specific override in stereOS modules (`modules/services/agentd.nix`) sets `DynamicUser = false` because agentd needs to be a specific user to own the tmux socket. The base flake uses `DynamicUser = true` which assigns a random UID — incompatible with tmux socket ownership requirements.

---

## 3. Deep Dive: masterblaster (CLI + VM Orchestrator)

**Q10, Q11, Q12, Q14 addressed here.**

### Three-Tier Architecture

masterblaster implements a three-tier architecture:

```
mb (CLI) ──JSON-RPC over Unix socket──> mb serve (daemon) ──control socket──> vmhost (child process per VM)
```

**Tier 1: CLI** (`main.go`) — cobra-based, 11 commands: `serve`, `init`, `up`, `down`, `status`, `destroy`, `ssh`, `list`, `mixtapes`, `pull`, `version`. All CLI commands connect to the daemon via `mbconfig.ConfigDir` which resolves to `~/.config/mb/`.

**Tier 2: Daemon** (`pkg/daemon/daemon.go`): Long-lived process (`mb serve`), RWMutex-protected `vms map[string]*managedVM`. Each VM entry has an `inst` (VM instance), `backend` string, `client` (connection to vmhost.sock), and `pid`. The daemon routes CLI requests to the appropriate vmhost.

**Tier 3: vmhost** (`cmd/vmhost/`): One child process per VM. Holds the hypervisor handle (QEMU process). Survives daemon restart — if `mb serve` dies, running VMs continue running.

### VM Backend Interface

`pkg/vm/backend.go` defines the `Backend` interface:
- `Up(ctx, inst)` — create and start VM from image
- `Start(ctx, inst)` — reboot existing stopped VM
- `Down(ctx, inst, timeout)` — graceful shutdown via vsock → ACPI → force kill
- `ForceDown(ctx, inst)` — immediate termination
- `Destroy(ctx, inst)` — stop + remove all on-disk resources
- `Status(ctx, inst)` — return current VM state
- `List(ctx)` — scan vms directory for all instances

Implementations: QEMU (`pkg/vm/qemu.go`) and Apple Virt (`pkg/vm/applevirt.go`). Linux always uses QEMU; Darwin arm64 uses Apple Virt by default.

**QEMU on Linux** (`pkg/vm/backend_linux.go`): Uses `AccelKVM` (KVM hardware acceleration). This is the critical point: on Linux, QEMU requires KVM. Without KVM, QEMU falls back to software emulation which is 10-50x slower and effectively unusable for interactive agent sessions.

### jcard.toml Configuration Schema

masterblaster's jcard.toml (`pkg/config/config.go:17-123`) is a superset of agentd's:

```toml
mixtape = "opencode-mixtape:latest"
mixtape_digest = "sha256:..."     # optional: pin to exact digest

[resources]
cpus   = 2
memory = "4GiB"
disk   = "20GiB"

[network]
mode        = "nat"               # nat | bridged | none
egress_allow = ["api.anthropic.com", "10.0.0.0/8"]

[[shared]]
host     = "~/projects/myrepo"
guest    = "/workspace"
readonly = false

[secrets]
ANTHROPIC_API_KEY = "${ANTHROPIC_API_KEY}"   # ${ENV_VAR} interpolation

[agent]
harness     = "claude-code"
prompt      = "Review the codebase"
workdir     = "/workspace"
restart     = "on-failure"
max_restarts = 3
timeout     = "2h"
```

`${ENV_VAR}` interpolation in secrets and paths (`pkg/config/expand.go`) means the host's environment variables are substituted at load time. Name defaults to parent directory name.

**Q14: Egress control**

`network.egress_allow` is a domain/CIDR allowlist (`pkg/config/config.go:71-72`). Domains are resolved to IPs; CIDRs are matched directly. This is neurosys's accepted risk area — agent network sandboxing is absent. masterblaster's egress control works at the VM network level via QEMU NAT rules, not at the bubblewrap level. For a bwrap-based sandbox, equivalent would need nftables/iptables rules in the sandbox's net namespace.

### State Management

VM state persisted at `~/.config/mb/vms/<name>/`:
- `state.json` — name, config, status, ports
- `disk.qcow2` — QCOW2 overlay backed by the mixtape image (CoW, disk-efficient)
- Various sockets

The QCOW2 overlay model (`pkg/vm/qemu.go:74-80`) is elegant: each VM gets a thin overlay backed by the shared base image. New VMs are disk-cheap. The mixtape image itself is never modified.

**Q10: masterblaster vs. deploy-rs**

These solve fundamentally different problems. deploy-rs activates NixOS configurations on running systems. masterblaster creates and destroys ephemeral VMs. The architectural lessons:
- masterblaster's vmhost child process pattern (hypervisor process survives daemon restart) is a good design for anything that holds heavyweight resources
- The JSON-RPC over Unix socket pattern (daemon ↔ CLI) is cleaner than neurosys's deploy.sh approach which does everything in one script

**Q11: VM isolation vs. bwrap**

Full VM isolation (masterblaster) vs. namespace isolation (bwrap):
- VM isolation: kernel-level isolation, requires KVM, ~500ms startup overhead, stronger security boundary
- bwrap: process-level isolation, no special hardware, zero overhead, weaker against kernel exploits
- **Verdict for neurosys:** bwrap is the right choice on Contabo (no KVM). On OVH VPS where KVM may be available, full VM isolation would be stronger but adds management complexity.

**Q12: Mixtape images vs. nixos-rebuild switch**

Mixtape distribution (immutable images with SHA-256 manifests) vs. nixos-rebuild switch (mutable system activation):
- Mixtapes: immutable, reproducible, content-addressed. Rollback = `mb destroy` + `mb up` with previous image.
- nixos-rebuild: mutable activation on running system. Rollback via deploy-rs magic rollback or `nixos-rebuild switch --rollback`.
- For a persistent VPS, nixos-rebuild switch is more appropriate. Mixtapes are optimized for ephemeral agents.

---

## 4. Deep Dive: stereosd (In-Guest System Daemon)

**Q13, Q19 (partial) addressed here.**

stereosd runs inside the stereOS VM as the control plane bridge between host and guest. It is a focused Go daemon with clean subsystem separation.

### State Machine

States defined in `pkg/protocol.go:94-100`:
```go
StateBooting  LifecycleState = "booting"
StateReady    LifecycleState = "ready"
StateHealthy  LifecycleState = "healthy"
StateDegraded LifecycleState = "degraded"
StateShutdown LifecycleState = "shutdown"
```

The `MsgLifecycle` message type allows stereosd to push state transitions to the host. masterblaster waits for `StateReady` after `mb up` before injecting secrets.

### NDJSON Wire Protocol

Messages are newline-delimited JSON (NDJSON) over vsock (CID 3, port 1024) or TCP fallback (`listenMode = "auto"`). 1MB message limit.

Message types (`pkg/protocol.go:16-58`):

**Host → Guest:**
- `ping` — health check
- `inject_secret` — write secret to tmpfs
- `mount` — mount shared directory (virtiofs/9p)
- `shutdown` — graceful shutdown
- `set_config` — deliver jcard.toml content
- `inject_ssh_key` — write public key to user's authorized_keys

**Guest → Host:**
- `pong` — ping response
- `lifecycle` — state transition
- `ack` — command acknowledgement (OK/error)
- `get_health` / `health` — health query

### Secret Injection Model

`pkg/secrets.go` implements atomic tmpfs writes:
1. Receives `inject_secret` message with `{name, value, mode}` payload
2. Validates name (path traversal prevention via `filepath.Base`)
3. Writes to `/run/stereos/secrets/<name>.tmp` with specified mode
4. Atomically renames `.tmp` → final path
5. Clears `secret.Value = ""` in-memory after write

**Q13: stereosd secret model vs. sops-nix**

| Property | stereosd | sops-nix |
|---|---|---|
| Delivery mechanism | vsock from host at boot | age decryption at NixOS activation |
| Storage | tmpfs at `/run/stereos/secrets/` | tmpfs at `/run/secrets/` |
| Never-on-disk guarantee | Yes (tmpfs only) | Yes (activation writes to tmpfs) |
| Encrypted at rest | No (host holds plaintext, sends over vsock) | Yes (sops-encrypted YAML in git) |
| Secret update trigger | Host sends new `inject_secret` message | `nixos-rebuild switch` |
| Key management | Host process has plaintext | age keys (SSH host key derivation) |
| Fit for persistent VPS | Not designed for this use case | Yes, purpose-built |

sops-nix is clearly superior for neurosys's persistent VPS model. stereosd's secret model is designed for ephemeral VMs where secrets should never reach the disk image. neurosys already has tmpfs `/run/secrets` from sops-nix.

### Mount Management

`pkg/mounts.go` handles virtiofs and 9p mounts from `MsgMount` messages. System directory protection prevents mounting over `/nix`, `/etc`, `/bin`, `/boot`, `/dev`, `/proc`, `/sys`, `/run`.

### agentd Integration

`pkg/agentd.go` polls agentd's HTTP API every 5 seconds (configurable) via `GET /v1/health` on `/run/stereos/agentd.sock`. This allows stereosd to report combined VM health to the host including agent status.

---

## 5. Deep Dive: stereOS (NixOS Image Builder)

**Q6, Q7, Q8, Q9 addressed here.**

### Module Structure Comparison

stereOS module tree (`modules/`): 6 files covering the full image.

| stereOS module | Purpose | neurosys equivalent |
|---|---|---|
| `modules/base.nix` | Filesystem, SSH, Nix access, packages, firewall, hardening | `modules/base.nix` (partially) |
| `modules/boot.nix` | Boot optimization (sub-3s), GRUB EFI, virtio | `modules/boot.nix` |
| `modules/users/agent.nix` | agent user, stereos-agent-shell, workspace | part of `modules/agent-compute.nix` |
| `modules/users/admin.nix` | admin user, wheel, admin group | `modules/users.nix` |
| `modules/services/agentd.nix` | agentd systemd service | `modules/agent-compute.nix` (agent-spawn) |
| `modules/services/stereosd.nix` | stereosd systemd service | (no equivalent — VM-only) |

**Q6: Module structure comparison**

stereOS's 6-module structure is simpler than neurosys's 15+ modules because:
1. It's purpose-built for one use case (agent sandbox VM), not a general-purpose server
2. No monitoring, backup, messaging, Matrix, web servers, or home automation
3. No multi-host support
4. No secrets-at-rest management (secrets come over vsock)

stereOS gains: simplicity, clarity, minimal attack surface.
neurosys gains: richness, multi-service support, battle-tested secrets model.

Both are appropriate for their use cases.

**Q7: stereos-agent-shell vs. bubblewrap**

stereos-agent-shell (`modules/users/agent.nix:73-92`):

```bash
# stereos-agent-shell
export PATH="${agentEnv}/bin:${extraEnv}/bin"   # ONLY curated binaries
export SSL_CERT_FILE=...
unset NIX_PATH NIX_REMOTE NIX_CONF_DIR ...      # Nuke all Nix variables
exec bash --login "$@"
```

This combines three isolation layers:
1. Separate `agent` user (UID isolation, no wheel membership)
2. Curated PATH (buildEnv with explicit approved binaries only)
3. Explicit sudo denial (`agent ALL=(ALL:ALL) !ALL` in sudoers)

bubblewrap (neurosys agent-spawn):
- PID namespace isolation (`--unshare-pid`)
- IPC namespace isolation (`--unshare-ipc`)
- UTS namespace isolation (`--unshare-uts`)
- Cgroup namespace isolation (`--unshare-cgroup`)
- User namespace isolation (`--unshare-user`)
- Selective bind mounts (explicit allowlist of accessible paths)
- Can run as current user (no separate agent user required)

**Q7 verdict:** These defend against different threat models:
- `stereos-agent-shell`: defends against agent escalating to admin/root by exploiting sudo or modifying system via Nix. Effective if agent cannot escape the shell (but PATH restriction is bypassable via absolute paths if any permitted binary is exploitable).
- bwrap: defends against agent accessing unauthorized filesystem paths, seeing host processes, or escaping to host network. Kernel-exploitable but much stronger filesystem and process isolation.

They are complementary. On a VM (where the VM itself is the outer sandbox), `stereos-agent-shell` + bwrap would be belt-and-suspenders. On a bare VPS with no VM layer, bwrap is the stronger choice because it provides namespace isolation that `stereos-agent-shell` alone does not.

**Q8: extraPackages pattern**

stereOS uses `stereos.agent.extraPackages` option (defined in `modules/users/agent.nix:104-111`), appended to `agentEnv` via `pkgs.buildEnv`:

```nix
stereos.agent.extraPackages = [ pkgs.claude-code ];  # in mixtapes/claude-code/base.nix
```

This is a clean, composable NixOS options pattern. Contrast with neurosys's approach:
- neurosys's bwrap sandbox builds a `--bind` path list that includes specific nix store paths
- Any package available in `environment.systemPackages` is potentially accessible

The stereOS `buildEnv` pattern is better for controllability: exact set of binaries is declaratively defined, with override at the mixtape level. neurosys could adopt this pattern for controlling what tools agents can access without adopting the full stereOS VM model.

**Q9: Boot optimization applicability**

stereOS boot optimization (`modules/boot.nix`): systemd initrd, virtio-only modules, no getty, volatile journal (32M), tight timeouts targeting sub-3s boot.

For neurosys:
- Persistent VPS: boot time is irrelevant (reboots are rare deploy events)
- The kernel hardening sysctls in `modules/base.nix` partially overlap with neurosys's `modules/base.nix` (dmesg restrict, kptr restrict, ptrace scope 2, network redirect hardening)
- `boot.tmp.useTmpfs = true` (stereOS) is already in neurosys via impermanence
- No-getty optimization would eliminate console logins on the VPS — potential footgun during disaster recovery

**Q9 verdict:** Boot optimization is not useful. Some kernel hardening constants are worth reviewing against what neurosys already has.

### Mixtape Build System

`lib/default.nix` exports `mkMixtape`:
```nix
mkMixtape { name = "claude-code"; features = [ ./mixtapes/claude-code/base.nix ]; }
```

This assembles a `nixpkgs.lib.nixosSystem` from:
- agentd NixOS module (from input)
- stereosd NixOS module (from input)
- stereOS module tree
- profiles/base.nix
- Feature-specific modules (e.g., claude-code/base.nix adds pkgs.claude-code to extraPackages)

`lib/dist.nix` exports `mkDist` for building distribution packages: `zstd` compression, SHA-256 manifests, `raw-efi` image format (raw EFI disk image). This is the mixtape registry distribution format masterblaster pulls.

---

## 6. Secondary Components

### tapes (Agent Telemetry)

**Q15 addressed here.**

tapes is a transparent proxy that intercepts LLM API calls and provides content-addressable durable session storage. Architecture:
- `proxy/` — HTTP proxy that sits between agent and LLM API, recording conversations
- `api/` — REST API server for managing sessions
- `cli/` — `tapes serve`, `tapes chat`, `tapes search`, `tapes checkout`, `tapes deck` (TUI)

The content-addressing model is interesting: conversation turns are stored by SHA-256 hash of content, making sessions deterministic and replayable. `tapes checkout <hash>` restores a previous conversation state.

Semantic search uses Ollama embeddings (`embeddinggema:latest` model) via a local vector store. This is meaningful for agent observability: "find the session where I fixed the nginx bug last week" becomes possible.

**Q15 verdict:** Interesting but premature for neurosys. The value proposition (session durability, replay, semantic search) is real, but:
- Requires running Ollama locally for embeddings
- Adds significant infrastructure (proxy + API server + vector store)
- 96 commits but still early-stage
- Spacebot already provides some session observability via LanceDB embeddings

**Decision: Defer.** Worth revisiting when neurosys has 10+ regular agent sessions per week and observability becomes a bottleneck.

### flake-skills (Skill Distribution)

**Q16 addressed here.**

flake-skills provides `mkSkillsFlake` and `mkSkillsHook` for distributing agent skills via Nix flakes. Skills are SKILL.md files (+ supporting scripts) discovered from `skills/<name>/` directories. `mkSkillsHook` syncs selected skills to `.agents/skills/` (or configurable `targetDir`) on `nix develop` entry, with gitignore management for flake-managed skills.

The composition model supports layering: pull community skills + override with project-local skills. Typo protection validates skill names at Nix eval time.

**Q16 verdict:** The idea of Nix-pinned skill distribution is elegant, but neurosys's current `.claude/skills/` model is simpler and sufficient. The value of flake-skills emerges in multi-project or team scenarios where skill sharing is needed.

**Decision: Steal the concept, not the implementation.** The gitignore management pattern (tracking which skills are managed vs. hand-written) is worth adopting directly in neurosys's `agent-config.nix`.

---

## 7. Adoption Table

| # | Pattern/Tool | What It Is | Why It Matters for Neurosys | Difficulty | Decision |
|---|---|---|---|---|---|
| 1 | agentd as NixOS service | Long-running daemon with reconciliation loop, restart policy, HTTP API for agent status | Replaces one-shot agent-spawn with supervised agent with restarts + status endpoint | moderate | **adopt** |
| 2 | Harness interface concept | `Name() string`, `BuildCommand(prompt) (bin, args)` typed abstraction for agent CLIs | Cleans up agent-spawn's `case "$AGENT"` dispatch; enables typed harness selection | trivial | **steal** |
| 3 | jcard.toml agent config schema | TOML config: harness, prompt, workdir, restart, timeout, grace_period, env | Declarative agent config replaces all agent-spawn CLI arguments; enables file-based config management | trivial | **steal** |
| 4 | Hash-based config reconciliation | SHA-256 hash of config+secrets to detect changes; only restart if changed | Enables hot-reload of agent config without manual intervention | moderate | **steal** |
| 5 | agentd HTTP API (Unix socket) | `GET /v1/health`, `/v1/agents` over `/run/stereos/agentd.sock` | Enable Prometheus scraping of agent status; homepage widget showing running agents | moderate | **adopt** |
| 6 | stereos-agent-shell curated PATH | `pkgs.buildEnv` + shell wrapper nuking Nix vars + sudo denial | Complement bwrap with user-level Nix access prevention; explicit agent user | moderate | **steal** |
| 7 | `stereos.agent.extraPackages` NixOS option | Declarative option for composable package addition to agent PATH | Cleaner than current system-level packages; enables per-harness package sets | trivial | **steal** |
| 8 | tmux dedicated socket pattern | `tmux -S /run/agentd/tmux.sock` with admin-group socket ownership | Admin can attach to agent sessions for introspection without interfering with user tmux | trivial | **steal** |
| 9 | `on-failure` restart policy | Restart agent on exit, with configurable max restarts and 3s backoff | Agents crash; automatic restart prevents silent failure without human intervention | trivial (via agentd) | **adopt** |
| 10 | QCOW2 overlay disk images | Copy-on-write overlays backed by base image — disk-efficient per-VM disks | N/A for current Contabo VPS. Relevant if OVH VPS KVM available | hard (requires KVM) | **defer** |
| 11 | egress_allow domain/CIDR allowlist | VM-level network allowlist via QEMU NAT | Agent network sandboxing (currently accepted risk SEC-4). Requires VM or custom nftables | hard (no KVM) | **defer** |
| 12 | stereosd vsock secret injection | Secrets delivered at boot over vsock, written to tmpfs, never reach disk image | N/A — neurosys sops-nix model is architecturally superior for persistent VPS | impractical | **skip** |
| 13 | mkMixtape builder pattern | `nixpkgs.lib.nixosSystem` assembly from modules + features in one function | neurosys doesn't build VM images; useful as reference for clean nixosSystem abstraction | moderate | **defer** |
| 14 | tapes session telemetry | Proxy-based LLM recording, semantic search, replay, checkpointing | Real value for observability but adds significant infra (Ollama + vector store) | hard | **defer** |
| 15 | flake-skills distribution | Nix-mediated composable skill sharing via flake inputs | .claude/skills/ is already working; flake-skills adds value only in multi-project/team settings | trivial | **defer** |
| 16 | Boot optimization (no-getty, virtio-only) | Systemd initrd, no console logins, virtio-only modules | VPS reboots are rare; the recovery footgun risk outweighs savings | impractical | **skip** |
| 17 | agentd debug mode | `-debug` flag logs full command, env key names, captures tmux pane output on exit | Useful for diagnosing agent launch failures; easy to add | trivial | **steal** |
| 18 | vmhost child process architecture | Hypervisor process survives daemon restart | N/A without VM layer; pattern is interesting for any long-lived heavyweight resource | impractical | **skip** |
| 19 | Dagger-based CI | Dagger pipeline for all build/test/release operations | Already using GitHub Actions; Dagger adds value for complex cross-platform pipelines | moderate | **defer** |
| 20 | MsgGetHealth polling pattern | stereosd polls agentd every 5s for status aggregation | Useful if adopting agentd; enables health rollup to monitoring | trivial (with agentd) | **adopt** |

---

## 8. Switch Recommendation

### Non-Negotiable Evaluation

| Criterion | stereOS | Evidence | Pass/Fail |
|---|---|---|---|
| Declarative, reproducible system config | Yes — NixOS-native, flake-pinned | `flake.nix`, `modules/` tree, `mkMixtape` | **PASS** |
| Encrypted secrets management | Partial — secrets in host environment (not encrypted-at-rest in git) | vsock injection from host plaintext; no age/sops equivalent | **PARTIAL FAIL** |
| Agent sandboxing | Yes — full VM isolation (stronger than bwrap) | stereOS VM + stereos-agent-shell + sudo denial | **PASS (but KVM-blocked)** |
| Minimal cloud dependency | Yes — self-hosted, QEMU-based | No cloud control plane required | **PASS** |
| Rollback safety on deploy | Partial — no explicit rollback; `mb destroy` + `mb up` with previous image tag | No deploy-rs equivalent; image tags provide rollback point | **PARTIAL FAIL** |

### KVM Blocker Analysis

**Contabo VPS (neurosys):**
- No KVM/nested virtualization — documented in MEMORY.md
- `mb up` cannot launch VMs — hard blocker for full stereOS adoption
- bubblewrap remains the only viable sandboxing approach on this host
- **Conclusion:** Full stereOS on Contabo is blocked indefinitely.

**OVH VPS (neurosys-prod at 135.125.196.143):**
- KVM status unknown — not verified during this research
- OVH Cloud bare-metal and dedicated VPS products typically expose hardware virtualization
- OVH VMs (managed cloud) typically do NOT expose KVM to guests
- To verify: `grep -c vmx /proc/cpuinfo` on the running OVH host
- **Conclusion:** Possibly available on OVH, but unverified. Even if KVM works, masterblaster is pre-release software.

**Impact of KVM blocker on recommendation:**
The KVM blocker eliminates full stereOS (VM-based isolation) as an option for neurosys's primary compute host. The adoptable patterns (agentd, Harness interface, jcard.toml, curated PATH) work without VMs.

### Recommendation

**Tier: Partial Adoption**

Do not switch from NixOS to stereOS. Do adopt agentd and three config patterns.

**Justification:**

1. **Full stereOS switch is blocked:** The VM isolation model requires KVM, which is unavailable on Contabo (neurosys's primary host). This is the core of what stereOS offers — removing VM isolation leaves only design patterns.

2. **sops-nix is superior for neurosys's use case:** stereosd's vsock injection model is designed for ephemeral VMs where secrets must not reach the disk. neurosys is a persistent VPS where age-encrypted secrets committed to git and decrypted at activation is architecturally cleaner and provides encrypted-at-rest guarantees.

3. **deploy-rs provides better rollback:** stereOS has no magic-rollback equivalent. neurosys's deploy-rs with 120s confirm timeout is a better safety model for a production VPS.

4. **Single-developer pre-release risk:** All repos created in February 2026. A sole developer at pre-release quality (v0.0.1-rc.10) creates API instability risk. Importing agentd as a flake input would expose neurosys to upstream breakage.

5. **agentd is valuable but adoptable in isolation:** The reconciliation-loop daemon, restart policy, and HTTP API are worth adopting. Adopt by importing agentd as a flake input and writing a neurosys-specific NixOS module that wires it to neurosys's sops-based secret files.

**Q17 answer:** stereOS full adoption is blocked by the KVM constraint on Contabo. Cannot run `mb up` on the current primary compute host.

**Q18 answer:** Partial adoption shape: import `agentd` as flake input, add `services.agentd.enable` module in neurosys with sops-nix secrets directory wiring, adopt jcard.toml config schema for agent configuration, switch `agent-spawn` to use agentd's tmux session model. No masterblaster, no stereosd, no stereOS image building.

**Q19 answer:** Non-negotiable gaps:
- Encrypted secrets: stereosd has no equivalent to sops-nix encrypted-at-rest secrets in git. This is a fundamental architecture difference, not a gap to bridge.
- Rollback safety: stereOS has no magic-rollback equivalent. Neurosys's deploy-rs is better.
- KVM requirement: Cannot be satisfied on Contabo.
- Multi-tenant server: stereOS is purpose-built for single-use agent VMs. Neurosys hosts 10+ services; full stereOS would require re-architecting everything.

---

## 9. Action Items

### Recommended New Phase: Phase 40 — agentd Integration

**Goal:** Replace neurosys's one-shot `agent-spawn` script with agentd for supervised agent lifecycle management. Preserve bubblewrap sandbox. Add HTTP API for agent status monitoring.

**Scope:**
1. Add `papercomputeco/agentd` as flake input (pin to a specific commit, not floating tag)
2. Write `modules/agent-compute.nix` changes: add `services.agentd` with sops-nix secrets wired to `agentd.secretDir`
3. Write neurosys-specific jcard.toml template (with claude-code harness, workspace pointing to neurosys project dir)
4. Keep bubblewrap for filesystem isolation — agentd does not currently sandbox; wiring bwrap into agentd's `custom` harness is possible
5. Wire agentd Unix socket to Prometheus via a simple health-check exporter
6. Update `modules/homepage.nix` with agent status widget

**Depends on:** None (standalone improvement)
**Estimated effort:** 1-2 plans (implementation + verification)
**Risk:** agentd is pre-release; pin to a commit hash, not `main` or a floating tag

### Pattern Steals (no new phase, TODO items for existing modules)

1. **TODO (agent-compute.nix):** Adopt jcard.toml for declarative agent config; remove CLI-argument-heavy `agent-spawn` invocation pattern
2. **TODO (agent-compute.nix):** Add a separate `agent` user with curated PATH buildEnv + sudo denial, complementing existing bubblewrap sandbox (defense-in-depth)
3. **TODO (agent-compute.nix):** Switch from zmx to tmux with dedicated socket (`/run/agentd/tmux.sock`) for admin-attachable sessions

### Not recommended for immediate action

- masterblaster / VM isolation: KVM blocked on Contabo. Revisit when/if OVH KVM verified + masterblaster matures past v0.1.0.
- tapes: Premature. Spacebot covers basic observability. Revisit at Phase 45+.
- flake-skills: Not yet needed. Single-project skills model is sufficient.
- stereOS image builder: Only relevant if neurosys runs VMs (KVM dependent).
