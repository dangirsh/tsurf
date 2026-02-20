# neurosys -- NixOS configuration for the neurosys server

## Overview
- Declarative NixOS infrastructure for the `neurosys` host, built with flakes and host modules.
- Manages base OS, networking/security, users, secrets, containers, observability, backups, and operator tooling.
- Uses `home-manager` for user environment and `sops-nix` for encrypted secret delivery.
- Runs Docker workloads plus native services (Home Assistant, Syncthing, Prometheus, Homepage).
- Includes agent compute tooling (Claude Code, Codex, `agent-spawn`, `zmx`, rootless Podman).
- Target audience: operators who need to deploy, maintain, and recover this server quickly.

## Infrastructure
- Provider: Contabo VPS profile (18 vCPU AMD EPYC, 96 GB RAM, 350 GB NVMe).
- Hostname: `neurosys`.
- Static IPv4: `161.97.74.121/18` (gateway `161.97.64.1`).
- OS baseline: NixOS `25.11` (`system.stateVersion = "25.11"`).
- Timezone: `Europe/Berlin`.

## Architecture
`neurosys` is a flake-based NixOS system with layered modules:
- `modules/` for system concerns (networking, services, backups, sandboxing, etc).
- `home/` for user-level home-manager configuration.
- `packages/` for custom packaged binaries (`zmx`, `cass`).

### Flake Inputs
| Input | Source | Purpose |
|---|---|---|
| `nixpkgs` | `github:NixOS/nixpkgs/nixos-25.11` | Base package set and NixOS modules |
| `home-manager` | `github:nix-community/home-manager/release-25.11` | User environment management |
| `sops-nix` | `github:Mic92/sops-nix` | Encrypted secrets at activation/runtime |
| `disko` | `github:nix-community/disko` | Declarative disk partitioning for install |
| `parts` | `github:dangirsh/personal-agent-runtime` | External service module input |
| `claw-swap` | `github:dangirsh/claw-swap` | External service module input |
| `llm-agents` | `github:numtide/llm-agents.nix` | Agent CLI overlay (`claude-code`, `codex`) |

## NixOS Modules
All 13 NixOS modules in `modules/` are active via `modules/default.nix`.

| Module | Role | Key Config Highlights |
|---|---|---|
| `base.nix` | Base OS defaults and hardening | Enables flakes, weekly GC, core CLI packages, kernel sysctl hardening (`dmesg`, `kptr`, BPF, redirects) |
| `boot.nix` | Bootloader config | GRUB enabled with EFI support, removable EFI install, boot entry limit 10 |
| `networking.nix` | Network policy and SSH security | nftables enabled, metadata endpoint blocked, firewall default-deny with public `80/443/22000`, Tailscale trusted interface, SSH key-only and not public, fail2ban incremental bans |
| `users.nix` | Accounts and privilege model | Immutable users, `dangirsh` in `wheel`+`docker`, root and user authorized keys, passwordless wheel sudo, `execWheelOnly` |
| `secrets.nix` | Secret declarations | `sops-nix` default file `secrets/neurosys.yaml`, age from host SSH key, 7 declared secrets + 1 rendered template |
| `docker.nix` | Docker runtime and networking | Docker daemon with `iptables = false`, journald logging, NixOS NAT over `172.16.0.0/12`, trusted `docker0` interface |
| `monitoring.nix` | Metrics and alerts | Prometheus localhost-only (`:9090`), node exporter (`:9100`), 15s scrape, 90d retention, 7 alert rules, restic freshness metric via textfile collector |
| `syncthing.nix` | File sync service | Runs as `dangirsh`, default sync ports enabled, GUI bound to `127.0.0.1:8384`, declarative devices/folders |
| `home-assistant.nix` | Home automation services | Home Assistant on `0.0.0.0:8123` (tailnet reachability), ESPHome on `0.0.0.0:6052`, both with `openFirewall = false` |
| `homepage.nix` | Service dashboard | Homepage Dashboard on `:8082`, allowed hosts include Tailscale IP and local hostnames, status widgets for infrastructure/services |
| `agent-compute.nix` | Agent runtime and sandboxing | Installs `claude-code`, `codex`, `zmx`, `agent-spawn`; bubblewrap sandbox default-on; rootless Podman enabled; agent cgroup slice and audit logging |
| `repos.nix` | Repo bootstrap on activation | Idempotent clone-only activation script for `parts`, `claw-swap`, `global-agent-conf` using temporary credential store |
| `restic.nix` | Backups and restore metadata | Daily restic backup to Backblaze B2 (S3 endpoint), retention `7/5/12`, blanket `/` with exclusions and `.nobackup`, `pg_dumpall` pre-hook, backup timestamp export |

## Home-Manager Modules
All 7 home-manager modules in `home/`:

| Module | Role | Key Config Highlights |
|---|---|---|
| `default.nix` | Home import hub | Defines user/home path, enables home-manager, imports all home modules |
| `bash.nix` | Shell bootstrap | Bash enabled; exports `GH_TOKEN`, `ANTHROPIC_API_KEY`, `OPENAI_API_KEY` from `/run/secrets/*` |
| `git.nix` | Git + GitHub CLI | Sets git identity and enables `gh` |
| `ssh.nix` | SSH client defaults | Connection multiplexing, keepalive, hashed known hosts |
| `direnv.nix` | Env auto-loading | Enables `direnv` plus `nix-direnv` and bash integration |
| `cass.nix` | Session indexer automation | Installs `cass`; user timer runs `cass index --full` every 30 minutes |
| `agent-config.nix` | Agent config linking | Symlinks `~/.claude` and `~/.codex` to `/data/projects/global-agent-conf` |

## Custom Packages
| Package | Version | What It Does | Integrity |
|---|---|---|---|
| `zmx` | `0.3.0` | Session persistence for terminal processes | Pre-built binary tarball fetched with pinned SHA256 |
| `cass` | `0.1.64` | Index/search CLI for coding agent session history | Pre-built binary tarball fetched with pinned SHA256 |

## Services and Ports
Ports are derived from `modules/networking.nix` plus per-service modules.

| Service | Port | Access Level | Source |
|---|---:|---|---|
| HTTP ingress | `80/tcp` | Public | `networking.firewall.allowedTCPPorts` |
| HTTPS ingress | `443/tcp` | Public | `networking.firewall.allowedTCPPorts` |
| Syncthing sync | `22000/tcp` | Public | `networking.firewall.allowedTCPPorts` + `syncthing.openDefaultPorts` |
| OpenSSH | `22/tcp` | Tailscale-only | `openssh.openFirewall = false`; `tailscale0` trusted; assertion forbids public 22 |
| Homepage Dashboard | `8082/tcp` | Tailscale-only | `homepage-dashboard.listenPort = 8082`; internal-only assertion set |
| Home Assistant | `8123/tcp` | Tailscale-only | `services.home-assistant` binds `0.0.0.0:8123`; not public firewall-open |
| ESPHome | `6052/tcp` | Tailscale-only | `services.esphome.port = 6052`; not public firewall-open |
| node_exporter | `9100/tcp` | Tailscale-only | Prometheus exporter port with internal-only assertion |
| Prometheus UI/API | `9090/tcp` | localhost-only | `services.prometheus.listenAddress = 127.0.0.1` |
| Syncthing GUI/API | `8384/tcp` | localhost-only | `services.syncthing.guiAddress = 127.0.0.1:8384` |

## Security Model
- nftables firewall with default-deny stance and explicit allow-list (`80`, `443`, `22000`).
- OpenSSH is key-only and Tailscale-only; build-time assertions block accidental public SSH exposure.
- fail2ban enabled with incremental ban multipliers and one-week cap.
- `sops-nix` secrets are age-encrypted and decrypted using the host SSH ed25519 key material.
- Agent workloads default to bubblewrap sandboxing via `agent-spawn`; `--no-sandbox` is explicit opt-out.
- Kernel sysctl hardening enabled: restrict `dmesg`, hide kernel pointers, disable unprivileged BPF, disable redirects.
- Cloud metadata endpoint `169.254.169.254` is blocked in nftables output chain.
- Docker daemon runs with `--iptables=false`; firewall ownership stays in NixOS networking policy.

## Deployment Quick-Start
Use this for first-time deployment workflow.

### Prerequisites
- Nix installed with flakes enabled.
- Access to admin age key for secret editing/decryption workflows.
- Tailscale connectivity to `neurosys` (MagicDNS target used by deploy script).

### Validate and Build
```bash
nix flake check
nixos-rebuild build --flake .#neurosys
```

### Deploy
```bash
./scripts/deploy.sh
```

Default behavior:
- Target: `root@neurosys`.
- Mode: `local` (build locally, switch remotely).
- Locking: local `flock` lock file + remote lock directory.

### Deploy Flags
```bash
./scripts/deploy.sh --mode local
./scripts/deploy.sh --mode remote
./scripts/deploy.sh --target root@<host>
./scripts/deploy.sh --skip-update
```

- `--mode local`: local build + remote switch.
- `--mode remote`: SSH to target, `git pull --ff-only`, then remote `nixos-rebuild switch`.
- `--skip-update`: skip `nix flake update parts` step.

## Operations
### Deploy
Use `scripts/deploy.sh` for routine rollout.

```bash
# Default deploy (local build -> remote switch)
./scripts/deploy.sh

# Remote rebuild mode
./scripts/deploy.sh --mode remote

# Override target
./scripts/deploy.sh --target root@161.97.74.121
```

Operational behavior:
- Two-layer deploy lock prevents concurrent deploys.
- Polls container health for up to 30 seconds (`parts-*`, `claw-swap-*`).
- On failure, use rollback:

```bash
ssh root@neurosys nixos-rebuild switch --rollback
```

### Backup and Restore
Backups are configured in `modules/restic.nix`.

- Backend: restic to Backblaze B2 over S3 API endpoint.
- Schedule: daily, persistent timer, randomized delay up to 1 hour.
- Retention: `--keep-daily 7`, `--keep-weekly 5`, `--keep-monthly 12`.
- Scope: blanket `/` backup with `--one-file-system`, cache exclusions, and `.nobackup` sentinel support.
- DB consistency: `pg_dumpall` pre-hook in `claw-swap-db` before backup.
- Health signal: post-backup writes `restic_backup_last_run_timestamp` metric.
- Targets: `RTO < 2h`, `RPO 24h`.

Daily operator commands:
```bash
# Inspect timer and last run
systemctl status restic-backups-b2.timer --no-pager
systemctl status restic-backups-b2.service --no-pager

# Manual run
systemctl start restic-backups-b2.service

# Check repository snapshots (from host)
source /run/secrets/rendered/restic-b2-env
export RESTIC_REPOSITORY='s3:s3.eu-central-003.backblazeb2.com/SyncBkp'
export RESTIC_PASSWORD="$(cat /run/secrets/restic-password)"
restic snapshots
```

For full disaster recovery steps, see `docs/recovery-runbook.md`.

### Monitoring
Prometheus stack is defined in `modules/monitoring.nix`.

- Prometheus: `127.0.0.1:9090`, scrape interval `15s`, retention `90d`.
- node_exporter: `:9100` with `systemd`, `processes`, `tcpstat`, and `textfile` collectors.
- Homepage Dashboard: `:8082` (tailnet access) for quick service visibility.

Alert rules (7):
1. `InstanceDown`
2. `DiskSpaceCritical`
3. `DiskSpaceWarning`
4. `HighMemoryUsage`
5. `HighCpuUsage`
6. `SystemdUnitFailed`
7. `BackupStale`

Concrete checks:
```bash
# Local alert query
curl -s http://127.0.0.1:9090/api/v1/alerts | jq '.data.alerts'

# Node exporter liveness
curl -s http://127.0.0.1:9100/metrics | head

# Verify restic staleness metric
cat /var/lib/prometheus-node-exporter/restic.prom
```

### Secrets
Secrets are managed through `sops-nix` and `secrets/neurosys.yaml`.

- Decryption keys:
  - Admin age key (operator-managed) for editing encrypted secret files.
  - Host key-derived age identity from `/etc/ssh/ssh_host_ed25519_key` for runtime decryption.
- Declared secrets (7):
  - `tailscale-authkey`
  - `b2-account-id`
  - `b2-account-key`
  - `restic-password`
  - `anthropic-api-key`
  - `openai-api-key`
  - `github-pat`
- Template (1):
  - `restic-b2-env` (renders AWS credentials for restic runtime env file)

Add a new secret:
```bash
# 1) Declare it in modules/secrets.nix under sops.secrets
$EDITOR modules/secrets.nix

# 2) Encrypt value into the sops file
sops secrets/neurosys.yaml

# 3) Validate and deploy
nix flake check
./scripts/deploy.sh
```

Runtime validation:
```bash
ls /run/secrets
ls /run/secrets/rendered
```

### Agent Compute
Agent runtime is declared in `modules/agent-compute.nix`.

- `agent-spawn` defaults to bubblewrap sandbox (`--no-sandbox` bypass requires explicit flag).
- CLIs installed: `claude-code`, `codex`.
- Session management: `zmx` (`zmx run`, `zmx attach`).
- Rootless Podman enabled; sandbox PATH provides `docker -> podman` compatibility shim.
- Resource controls: `agent.slice` with `CPUWeight=100`, `TasksMax=4096`.
- Audit logging: append-only operational log at `/data/projects/.agent-audit/spawn.log` plus journald events (`agent-spawn` tag).

Operator commands:
```bash
# Show sandbox policy
agent-spawn test-agent /data/projects/neurosys claude --show-policy

# Spawn sandboxed session (default)
agent-spawn test-agent /data/projects/neurosys codex

# Attach to session
zmx attach test-agent

# View recent spawn events
tail -n 50 /data/projects/.agent-audit/spawn.log
journalctl -t agent-spawn -n 50 --no-pager
```

## Design Decisions
Decisions below are extracted from `@decision` annotations in source modules and scripts.

| ID | Decision | Rationale |
|---|---|---|
| `SEC-17-01` | Apply kernel sysctl hardening baseline. | Reduce kernel/userland attack surface and metadata leakage. |
| `NET-01` | SSH is key-only and not publicly exposed. | Remote admin goes over tailnet path; public brute-force surface is reduced. |
| `NET-02` | nftables default-deny with explicit allow-list. | Keep network exposure intentional and reviewable. |
| `NET-03` | Tailscale is first-class host VPN. | Internal/admin services are reachable via tailnet identity. |
| `NET-04` | Only `80/443/22000` are public TCP ports. | Limit internet-facing endpoints to required ingress and Syncthing sync. |
| `NET-05` | fail2ban with progressive bans. | Penalize repeated SSH abuse with escalating ban windows. |
| `NET-06` | Tailscale reverse path filtering uses loose mode. | Compatible routing behavior for VPN traffic. |
| `NET-07` | Build-time assertion blocks leaking internal ports to public firewall rules. | Prevent accidental config drift from exposing admin/internal services. |
| `SYS-01` | Immutable user model with wheel/docker groups and controlled sudo policy. | Stable auth state and explicit privilege boundaries. |
| `DOCK-01` | Docker daemon runs with `iptables=false`. | Single firewall authority remains in NixOS policy. |
| `DOCK-02` | NAT uses `internalIPs` (`172.16.0.0/12`) for Docker networks. | Covers default and custom bridges without per-interface maintenance. |
| `MON-02` | Prometheus scrape every 15s with 90d retention. | Enough granularity/history for operations and debugging. |
| `MON-05` | Auxiliary dashboard/notification stack removed; alerts are queried from Prometheus API. | Simpler monitoring architecture with fewer moving parts. |
| `MON-06` | Prometheus is localhost-only. | API/data is not directly internet-exposed. |
| `MON-07` | Textfile collector exports restic freshness timestamp. | Backup staleness becomes alertable and dashboard-visible. |
| `SVC-02` | Syncthing runs declaratively as `dangirsh`. | Reproducible peer/folder config under version control. |
| `SVC-03` | Syncthing GUI is localhost-only and CASS indexer runs as periodic oneshot timer. | Lower GUI attack surface and low-overhead indexing. |
| `HA-01` | Home Assistant runs as native NixOS service (not containerized). | Simpler integration with host networking/service management. |
| `HA-02` | Home Assistant UI follows tailnet-only access model. | Access control aligns with trusted-interface pattern. |
| `HP-01` | Homepage Dashboard is NixOS-native and tailnet-reachable. | Lightweight status surface with declarative config. |
| `SANDBOX-11-01` | `agent-spawn` defaults to bubblewrap sandbox; opt-out requires `--no-sandbox`; Podman rootless with no system `dockerCompat`. | Enforce safer defaults while preserving explicit escape hatch and avoiding Docker conflicts. |
| `AGENT-01` | Agent config directories (`~/.claude`, `~/.codex`) are symlinked to shared repo. | Centralized policy/config for all agent tooling. |
| `AGENT-02` | Repo bootstrap is clone-only on activation (no pull). | Idempotent provisioning without mutating dirty checkouts. |
| `RESTIC-01` | Use S3-compatible B2 backend for restic. | Stable repository access with known-compatible path. |
| `RESTIC-02` | Retention policy is 7 daily / 5 weekly / 12 monthly. | Balances recovery depth and storage growth. |
| `RESTIC-03` | Restic credentials are provided through sops template and secret files. | Keep credentials out of plaintext config/runtime arguments. |
| `RESTIC-04` | Run `pg_dumpall` pre-backup hook. | Capture consistent logical DB snapshot alongside filesystem backup. |
| `RESTIC-05` | Backup scope is blanket `/` with exclusions and `.nobackup` opt-out. | New stateful paths are protected by default without recurring config edits. |
| `DPLY-01` | Deployment is manual via script with full `nixos-rebuild switch`. | Keep operator control and avoid fragmented deploy paths. |
| `DPLY-02` | Deploy verifies container health and uses local+remote locking. | Prevent concurrent rollout conflicts and surface post-deploy failure quickly. |

## Accepted Risks
Accepted risks documented in `CLAUDE.md` plus sandbox-related design choices.

| ID | Risk | Mitigation |
|---|---|---|
| `SEC3` | Container hardening settings in external service repos are deferred. | Keep services declarative here; track hardening work in external repos. |
| `SEC5` | `--no-sandbox` sessions can modify user-scoped agent config. | Sandbox default-on; bypass requires explicit operator intent. |
| `SEC6` | Homepage service accesses Docker socket. | Dashboard is tailnet-only (`8082`) and not public-exposed. |
| `SEC9` | Additional systemd hardening overrides are deferred for many services. | Rely on module defaults to avoid destabilizing service behavior. |
| `SEC11` | Custom binaries (`zmx`, `cass`) are pre-built artifacts without signature verification. | Pinned SHA256 hashes enforce deterministic artifact integrity. |
| `SANDBOX-CHOICE-01` | Sandbox allows read access to sibling repos under `/data/projects`. | Deliberate tradeoff to support cross-repo operator/agent workflows. |
| `SANDBOX-CHOICE-02` | Sandbox does not block outbound network by default. | Required for API and git workflows; metadata endpoint is still blocked. |
| `SEC-17-04` | User-writable spawn log file can be tampered with. | Spawn events are mirrored to journald for stronger audit trail. |

## Project Structure
Authoritative high-level layout (aligned to `CLAUDE.md`):

```text
flake.nix              # Entrypoint: inputs, outputs, nixosConfigurations.neurosys
flake.lock             # Pinned dependencies
hosts/
  neurosys/
    default.nix        # Host-specific NixOS config (imports modules)
    hardware.nix       # Hardware profile
    disko-config.nix   # Disk layout
modules/
  default.nix          # Import hub for all NixOS modules
  base.nix
  boot.nix
  networking.nix
  users.nix
  secrets.nix
  docker.nix
  monitoring.nix
  syncthing.nix
  home-assistant.nix
  homepage.nix
  agent-compute.nix
  repos.nix
  restic.nix
home/
  default.nix          # home-manager import hub
  bash.nix
  git.nix
  ssh.nix
  direnv.nix
  cass.nix
  agent-config.nix
packages/
  zmx.nix
  cass.nix
scripts/
  deploy.sh            # Deploy script (local/remote mode, locks, health checks)
secrets/
  neurosys.yaml        # sops-encrypted secrets
docs/
  recovery-runbook.md  # Disaster recovery runbook
```

## Footer
- Development and agent conventions: `CLAUDE.md`
- Disaster recovery runbook: `docs/recovery-runbook.md`
