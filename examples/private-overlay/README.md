# Private Overlay Example
Minimal forkable template for a private tsurf overlay with an internal janitor maintenance module.

**This is a TEMPLATE. It will not evaluate until you customize placeholder values, add host-specific modules, and configure real hardware.**

## Quick Start
1. Copy this directory into a new private repository.
2. Edit `flake.nix`: replace `github:your-org/tsurf` and `REPLACE` placeholders.
3. Replace placeholder recipients in `.sops.yaml` with real age public keys.
4. Replace hardware references in `hosts/example/default.nix` with your host's config.
5. After host-specific setup, import `networking.nix`, `secrets.nix`, and `sshd-liveness-check.nix` (requires Tailscale, persisted SSH host keys, and an encrypted sops file).
6. Run `nix flake lock` in this private repo to generate `flake.lock`.
7. Create `secrets/example.yaml`, encrypt it with sops, and set `sops.defaultSopsFile` when enabling `secrets.nix`.
8. Deploy with deploy-rs using your real hostnames and SSH access.

`modules/janitor.nix` runs a Claude Code agent in a nono sandbox on a weekly
timer. The agent's cleanup behavior is defined as a natural-language system
prompt - change what the janitor does by editing English, not bash. It cleans
stale `/tmp` files, runs nix garbage collection, and writes a JSON status report.

**Requirements:**
- An `anthropic-api-key` sops secret (the agent calls the Anthropic API)
- `nono.nix` imported in commonModules (included in template)

**Cost:** Each weekly run uses ~5K input + ~2K output tokens (~$0.01-0.03/run,
~$0.50-1.50/year at Sonnet pricing). Override the model with
`services.janitor.model`.

Customize schedule and retention through `services.janitor.*` options. Override
the entire cleanup logic with `services.janitor.systemPrompt`.

See `README.md` and `CLAUDE.md` in the tsurf source repo for full documentation.
