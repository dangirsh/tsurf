NixOS server config for an agentic development platform. Declarative, batteries-included, Tailscale-only.

## Design Principles

- **Declarative everything**: no imperative setup steps after initial deploy
- **Tailscale-only internal networking**: all services Tailscale-gated by default; public firewall minimal
- **Agents as first-class workloads**: bubblewrap sandboxing, cgroup isolation, multi-provider key injection
- **Secrets never in the Nix store**: sops-nix age-encrypted, decrypted at activation
- **Impermanent root**: BTRFS ephemeral `/` subvolume, explicit `/persist` state manifest
- **Private config via overlay**: personal services and secrets in a separate private flake repo (see [docs/private-overlay.md](docs/private-overlay.md))

## Modules

| Module | Role | Key detail |
|--------|------|------------|
| `base.nix` | Nix settings, system packages, kernel hardening | sysctl: dmesg/kptr/BPF restrictions, ICMP redirect off |
| `boot.nix` | GRUB bootloader | x86_64 legacy BIOS, GRUB 2 |
| `users.nix` | User accounts, sudo, SSH keys | Key-only auth; replace placeholder keys |
| `networking.nix` | nftables firewall, SSH, Tailscale, fail2ban | port 22 assertion prevents accidental public exposure |
| `secrets.nix` | sops-nix secret declarations | age key derived from SSH host key |
| `docker.nix` | Docker engine | `--iptables=false`; NAT via nftables |
| `monitoring.nix` | Prometheus + node\_exporter | 15s scrape, 90d retention, textfile collector |
| `syncthing.nix` | Syncthing file sync | GUI Tailscale-only; replace device ID placeholders |
| `agent-compute.nix` | Agent CLIs + bubblewrap sandbox + agent-spawn | See Agent Tooling section |
| `secret-proxy.nix` | Anthropic API key forwarding proxy | Port 9091, localhost-only; key injected pre-sandbox |
| `impermanence.nix` | BTRFS ephemeral root | `/persist` state manifest; Docker on `@docker` subvolume |
| `restic.nix` | Restic backup to Backblaze B2 | Daily, blanket `/persist` with exclusions |
| `homepage.nix` | Homepage dashboard | Tailscale-only port 8082; add services in private overlay |

## Agent Tooling

**Included CLIs** (via [llm-agents.nix](https://github.com/numtide/llm-agents.nix) overlay):
`claude-code`, `codex`, `opencode`, `gemini-cli`, `pi` — plus `zmx` (session persistence) and `agent-spawn` (sandboxed launcher).

```
agent-spawn <name> <project-dir> [claude|codex|opencode|gemini|pi] [--no-sandbox]
```

**Sandbox policy** (bubblewrap + systemd slice):

| Resource | Access |
|----------|--------|
| `/nix/store` | read-only bind |
| `/data/projects` | read-only (all siblings visible) |
| `<project-dir>` | read-write |
| `~/.claude`, `~/.codex`, `~/.gemini` | read-only |
| `~/.local/share/opencode` | read-write |
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
| 80, 443 | HTTP/HTTPS (nginx in private overlay) | Public |
| 22000 | Syncthing transfer | Public |
| 8082 | Homepage dashboard | Tailscale-only |
| 8384 | Syncthing GUI | Tailscale-only |
| 9090 | Prometheus | Tailscale-only |
| 9091 | Secret proxy | localhost-only |
| 9100 | node-exporter | Tailscale-only |

Build-time assertion prevents any `internalOnlyPorts` from appearing in `allowedTCPPorts`. Add private service ports in your private overlay.

## Quick Start

1. Fork this repo. Create your private overlay (see [docs/private-overlay.md](docs/private-overlay.md)).
2. Generate age key from SSH host key (`ssh-to-age`). Encrypt secrets with `sops`.
3. Deploy: `nixos-anywhere` for first install; `nix run .#deploy-rs` (or `scripts/deploy.sh`) for updates.
4. Launch agents: `agent-spawn <name> <project-dir> [claude|codex|opencode]`

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
