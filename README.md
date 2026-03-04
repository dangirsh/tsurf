NixOS server config for an agentic development platform. Declarative, batteries-included, Tailscale-only.

## Design Principles

- **Declarative everything**: no imperative setup steps after initial deploy
- **Tailscale-only internal networking**: all services Tailscale-gated by default; public firewall minimal
- **Agents as first-class workloads**: bubblewrap sandboxing, cgroup isolation, multi-provider key injection
- **Secrets never in the Nix store**: sops-nix age-encrypted, decrypted at activation
- **Impermanent root**: BTRFS ephemeral `/` subvolume, explicit `/persist` state manifest
- **Private config via overlay**: personal services and secrets in a separate private flake repo

## Modules

| Module | Role | Key detail |
|--------|------|------------|
| `base.nix` | Nix settings, system packages, kernel hardening | sysctl: dmesg/kptr/BPF restrictions, ICMP redirect off |
| `boot.nix` | GRUB bootloader | x86_64 legacy BIOS, GRUB 2 |
| `users.nix` | User accounts, sudo, SSH keys | Key-only auth; replace placeholder keys |
| `networking.nix` | nftables firewall, SSH, Tailscale, fail2ban | port assertion prevents accidental public exposure |
| `secrets.nix` | sops-nix secret declarations | age key derived from SSH host key |
| `docker.nix` | Docker engine | `--iptables=false`; NAT via nftables |
| `syncthing.nix` | Syncthing file sync | GUI Tailscale-only; replace device ID placeholders |
| `agent-compute.nix` | Agent CLIs + bubblewrap sandbox | See Agent Tooling section |
| `secret-proxy.nix` | Anthropic API key forwarding proxy | Port 9091, localhost-only; key injected pre-sandbox |
| `impermanence.nix` | BTRFS ephemeral root | `/persist` state manifest; Docker on `@docker` subvolume |
| `restic.nix` | Restic backup to Backblaze B2 | Daily, blanket `/persist` with exclusions |
| `dashboard.nix` | Nix-derived dynamic dashboard | Build-time JSON manifest, Python HTTP server, systemd status |
| `canvas.nix` | Agent visualization surface | REST+SSE APIs, GridStack/Vega-Lite client |
| `nginx.nix` | Reverse proxy stub | ACME TLS; extend vhosts in private overlay |

## Agent Tooling

**Included CLIs** (via [llm-agents.nix](https://github.com/numtide/llm-agents.nix) overlay):
`claude-code`, `codex` — plus `zmx` (session persistence).

**Sandbox policy** (bubblewrap + systemd slice):

| Resource | Access |
|----------|--------|
| `/nix/store` | read-only bind |
| `/data/projects` | read-only (all siblings visible) |
| `<project-dir>` | read-write |
| `~/.claude`, `~/.codex` | read-only |
| `/run/secrets`, `~/.ssh` | **hidden** |
| `/var/run/docker.sock` | **hidden** |
| Network | unrestricted (agents need API/git) |
| Namespaces | PID, cgroup, user, IPC, UTS isolated |
| Limits | `agent.slice` CPUWeight=100, TasksMax=4096, `/tmp` tmpfs=4GiB |

API keys (Anthropic, OpenAI, GitHub, Google, XAI, OpenRouter) are read from `/run/secrets` before sandbox entry and injected as env vars. `/run/secrets` itself is not mounted inside the sandbox.

## Secret Proxy

Port 9091 listens on localhost. Specific projects route via `ANTHROPIC_BASE_URL=http://127.0.0.1:9091` instead of using the real key directly; the proxy forwards requests upstream with the real key injected server-side. The real key never reaches the sandbox for proxy-routed projects. Wire project-specific routing in your private overlay (see `agent-compute.nix` placeholder comment).

## Networking

| Port | Service | Access |
|------|---------|--------|
| 22 | SSH | Public (key-only; also accepts Tailscale) |
| 80, 443 | HTTP/HTTPS (nginx reverse proxy) | Public |
| 22000 | Syncthing transfer | Public |
| 8082 | Nix dashboard | Tailscale-only |
| 8083 | Agent canvas | Tailscale-only |
| 8384 | Syncthing GUI | Tailscale-only |
| 9091 | Secret proxy | localhost-only |

Build-time assertion prevents any `internalOnlyPorts` from appearing in `allowedTCPPorts`. Add private service ports in your private overlay.

## Quick Start

1. Fork this repo. Create your private overlay (import individual modules from a private flake).
2. Generate age key from SSH host key (`ssh-to-age`). Encrypt secrets with `sops`.
3. Deploy: `nixos-anywhere` for first install; `nix run .#deploy-rs` (or `scripts/deploy.sh`) for updates.
4. Launch agents: `claude` or `codex` from any project directory

## Example Use Cases

This skeleton is designed to be extended via a private overlay. Here are examples
of what you can build on top of it:

### Autonomous AI Agent Runtime
Deploy a long-running AI agent that executes tasks autonomously. The agent process
runs as a dedicated systemd service with state isolation (`HOME=/var/lib/agent`),
LLM API keys injected via the secret proxy, and lifecycle managed through a
companion dashboard service. The agent-compute module provides the sandbox and
cgroup isolation; your overlay adds the agent binary, configuration, and genesis
prompt.

### Chat Bridge Hub
Run a Matrix homeserver with messaging bridges that unify conversations across
platforms. Each bridge runs as a hardened systemd service with its own state
directory. A DM pairing guide service helps new users link their accounts. The
impermanence module persists bridge state across reboots; sops-nix manages bridge
tokens and API credentials.

### Home Automation Hub
Native NixOS Home Assistant with ESPHome device management. Tailscale Serve
provides HTTPS access for MCP integration. Automations live in a separate git repo
cloned on activation. Custom components installed declaratively. ESPHome devices
connect over the local network via a Tailscale subnet router.

### Multi-Instance SaaS Gateway
Deploy multiple isolated instances of a web service (each on its own port with
dedicated systemd user, state directory, and API token). Use `lib.mapAttrs'` to
generate N instances from a single parametric attrset. An auto-approve sidecar
handles node registration. Nginx reverse proxy with per-instance TLS certificates
(ACME DNS-01).

### LLM Cost Tracking
Extend the secret proxy to log per-request token counts and model pricing.
Aggregate daily/weekly/monthly costs. Expose summaries via an MCP tool so your AI
agents can report their own operating costs. Dashboard widget shows real-time spend.

## Flake Inputs

| Input | Source | Purpose |
|-------|--------|---------|
| `nixpkgs` | `NixOS/nixpkgs/nixos-25.11` | Base package set |
| `home-manager` | `nix-community/home-manager/release-25.11` | User environment |
| `sops-nix` | `Mic92/sops-nix` | Age-encrypted secrets |
| `disko` | `nix-community/disko` | Declarative disk layout |
| `llm-agents` | `numtide/llm-agents.nix` | Agent CLI overlay |
| `deploy-rs` | `serokell/deploy-rs` | Magic-rollback deployments |
| `impermanence` | `nix-community/impermanence` | Ephemeral root |
| `srvos` | `nix-community/srvos` | Server hardening baseline |
| `treefmt-nix` | `numtide/treefmt-nix` | Formatter + devShell |

## License

MIT
