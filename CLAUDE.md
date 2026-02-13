# CLAUDE.md — agent-neurosys

NixOS configuration for the `acfs` server (and future machines). Declarative system management with flakes + home-manager.

## Project Structure

```
flake.nix              # Entrypoint — inputs, outputs, nixosConfigurations
flake.lock             # Pinned dependencies
hosts/
  acfs/                # Per-host configuration
    default.nix        # Host-specific NixOS config
    hardware.nix       # Hardware/disk config
    services.nix       # Service declarations (docker, postgres, ollama, etc.)
modules/
  common.nix           # Shared across all hosts
  dev-tools.nix        # Development toolchain
  docker-services.nix  # Docker container declarations
  syncthing.nix        # Syncthing service
  restic.nix           # Restic backup to B2
  agent-tooling.nix    # Claude Code / global-agent-conf setup
home/
  default.nix          # home-manager entrypoint
  shell.nix            # Zsh, starship, aliases
  git.nix              # Git configuration
  tmux.nix             # Tmux configuration
```

## Key Decisions

- **Flakes + home-manager**: Modern, reproducible, lockfile-pinned
- **Docker stays**: Containers declared in Nix, not converted to native services
- **Restic to B2**: Automated backups to Backblaze B2
- **No ACFS**: Shell config managed by home-manager from scratch
- **Agent tooling**: Nix clones global-agent-conf, symlinks ~/.claude

## Testing

NixOS configs are validated with:
- `nix flake check` — Flake evaluation
- `nixos-rebuild build --flake .#acfs` — Build without switching
- `nixos-rebuild test --flake .#acfs` — Build and switch (test, no boot entry)

## Conventions

- One module per concern (networking, services, dev-tools)
- Secrets managed via sops-nix or agenix (TBD)
- All service configs are declarative — no imperative setup steps
- Infrastructure repos are cloned via activation scripts
