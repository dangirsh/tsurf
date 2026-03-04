NixOS server config for an agentic development platform. Declarative, batteries-included, Tailscale-only.

## Design Principles

- **Declarative everything**: no imperative setup steps after initial deploy
- **Tailscale-only internal networking**: all services Tailscale-gated by default; public firewall minimal
- **Agents as first-class workloads**: bubblewrap sandboxing, cgroup isolation, multi-provider key injection
- **Secrets never in the Nix store**: sops-nix age-encrypted, decrypted at activation
- **Impermanent root**: BTRFS ephemeral `/` subvolume, explicit `/persist` state manifest
- **Private config via overlay**: personal services and secrets in a separate private flake repo

## What's Included

- **Agent sandboxing** (`agent-compute.nix`)
  - CLIs: `claude-code`, `codex`, `zmx` via [llm-agents.nix](https://github.com/numtide/llm-agents.nix)
  - bubblewrap + systemd slice: PID/cgroup/user/IPC namespace isolation
  - `/run/secrets` and `~/.ssh` hidden from sandbox; API keys injected as env vars
- **Secret proxy** (`secret-proxy.nix`)
  - localhost-only proxy on port 9091; real API key never enters the sandbox
  - projects route via `ANTHROPIC_BASE_URL=http://127.0.0.1:9091`
- **Ephemeral root** (`impermanence.nix`)
  - BTRFS subvolume rollback on boot; Docker on separate `@docker` subvolume
  - explicit `/persist` manifest for stateful paths
- **Server hardening** (`base.nix`, `networking.nix`)
  - [srvos](https://github.com/nix-community/srvos) server profile, kernel sysctl hardening
  - nftables firewall, fail2ban, SSH key-only with ed25519
  - build-time assertion prevents internal ports from leaking to public firewall
- **Secrets** (`secrets.nix`)
  - sops-nix with age key derived from SSH host key
  - multi-provider API keys: Anthropic, OpenAI, Google, XAI, OpenRouter, GitHub
- **Backups** (`restic.nix`)
  - daily restic to Backblaze B2; blanket `/persist` with exclusions
- **File sync** (`syncthing.nix`)
  - Syncthing with Tailscale-only GUI
- **Dashboards** (`dashboard.nix`, `canvas.nix`)
  - Nix-derived service dashboard with systemd status; agent visualization canvas
- **Deployment** (`flake.nix`, `scripts/deploy.sh`)
  - deploy-rs with magic rollback; `nixos-anywhere` for first install
  - disko declarative disk layout
- **Reverse proxy** (`nginx.nix`)
  - ACME TLS stub; extend vhosts in private overlay
- **Docker** (`docker.nix`)
  - `--iptables=false`; NAT via nftables; trusted on Tailscale interface

## Example Use Cases

Examples based on real deployments:

- **Autonomous AI agent runtime.** Long-running agent as a systemd service with isolated state, API keys via secret proxy, lifecycle managed through a dashboard.
- **Chat bridge hub.** Matrix homeserver with mautrix bridges (Signal, WhatsApp, Telegram), each as a hardened service with persisted state.
- **Home automation.** Native Home Assistant + ESPHome, Tailscale Serve for HTTPS, automations in a separate git repo cloned on activation.
- **Multi-instance SaaS gateway.** Parametric `lib.mapAttrs'` generates N isolated instances with dedicated users, ports, and per-instance TLS via ACME DNS-01.
- **LLM cost tracking.** Extend the secret proxy to log token counts and pricing; expose summaries via MCP tool.

## Quick Start

1. Fork this repo. Create a private overlay flake that imports individual modules.
2. Generate age key from SSH host key (`ssh-to-age`). Encrypt secrets with `sops`.
3. Deploy: `nixos-anywhere` for first install; `nix run .#deploy-rs` for updates.
4. Launch agents: `claude` or `codex` from any project directory.

## License

MIT
