Neurosys is NixOS configuration optimized for secure agentic computing. I use it to deploy and manage agents across several remote hosts, alongside the services they build / maintain. 

> Note: this public repo is only the base configuration. My personal services are configured in a private overlay repo.

## Design Principles

- **Agent-mediated**: All tools are chosen based on agents being their users. Humans talk to agents to make changes.  
- **Secure defaults**: Networking, secret management, and agent sandboxing should be secure out-of-the-box.
- **Maximally reproducible**: flake-pinned inputs, ephemeral root with explicit persist manifest, no imperative setup
- **Forkable**: personal services live in a private overlay flake; public repo is a clean skeleton

## What's Included

- **Agent sandboxing**: bubblewrap + systemd slice isolation for AI coding agents
  - [`agent-compute.nix`](modules/agent-compute.nix), [`secret-proxy.nix`](modules/secret-proxy.nix)
  - PID/cgroup/user/IPC namespace isolation; `/run/secrets` hidden from sandbox
  - API keys read pre-sandbox and injected as env vars; secret proxy on port 9091 keeps real keys out of the sandbox entirely
- **Server hardening**: locked-down defaults for a public-facing VPS
  - [`networking.nix`](modules/networking.nix), [`base.nix`](modules/base.nix)
  - [srvos](https://github.com/nix-community/srvos) server profile, nftables, fail2ban, kernel sysctl hardening
  - build-time assertion prevents internal ports from leaking to public firewall
- **Ephemeral root**: BTRFS subvolume rollback on every boot
  - [`impermanence.nix`](modules/impermanence.nix)
  - explicit `/persist` manifest; Docker on separate `@docker` subvolume
- **Secrets management**: sops-nix with age key derived from SSH host key
  - [`secrets.nix`](modules/secrets.nix)
  - multi-provider API keys (Anthropic, OpenAI, Google, XAI, OpenRouter, GitHub)
- **Backups**: daily restic to Backblaze B2
  - [`restic.nix`](modules/restic.nix)
  - blanket `/persist` with exclusions
- **Dashboards**: Nix-derived service status and agent visualization
  - [`dashboard.nix`](modules/dashboard.nix), [`canvas.nix`](modules/canvas.nix)
- **File sync**: Syncthing with Tailscale-only GUI
  - [`syncthing.nix`](modules/syncthing.nix)
- **Deployment**: deploy-rs with magic rollback
  - [`flake.nix`](flake.nix), [`scripts/deploy.sh`](scripts/deploy.sh)
  - `nixos-anywhere` for first install; disko declarative disk layout
- **Reverse proxy**: nginx stub with ACME TLS
  - [`nginx.nix`](modules/nginx.nix)
  - extend vhosts in private overlay
- **Docker**: engine with `--iptables=false`, NAT via nftables
  - [`docker.nix`](modules/docker.nix)

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
