# home/agentic-dev-base.nix
# @decision DEV-01: agentic-dev-base symlinks managed declaratively via home-manager
# @rationale: Replaces manual install.sh script with reproducible Nix configuration.
#   Source repo lives at /data/projects/agentic-dev-base (synced via Syncthing).
{ config, lib, pkgs, ... }:
let
  agenticBase = "/data/projects/agentic-dev-base";
in
{
  # Create ~/.claude and ~/.codex directory structure via activation script
  # Using activation script instead of home.file because we need symlinks to
  # paths outside the Nix store that may not exist at build time.
  home.activation.setupAgenticDevBase = lib.hm.dag.entryAfter ["writeBoundary"] ''
    # Create directories
    mkdir -p $HOME/.claude
    mkdir -p $HOME/.claude/usage
    mkdir -p $HOME/.codex

    # Symlink agentic-dev-base directories (only if source exists)
    if [ -d "${agenticBase}/.claude" ]; then
      for dir in hooks agents scripts skills rules; do
        target="$HOME/.claude/$dir"
        source="${agenticBase}/.claude/$dir"
        if [ -d "$source" ]; then
          # Remove existing (backup real dirs)
          if [ -d "$target" ] && [ ! -L "$target" ]; then
            mv "$target" "$target.bak.$(date +%s)"
          fi
          ln -sfn "$source" "$target"
        fi
      done
    fi

    # Symlink Codex agent instructions
    if [ -f "${agenticBase}/codex/AGENTS.md" ]; then
      ln -sfn "${agenticBase}/codex/AGENTS.md" "$HOME/.codex/AGENTS.md"
    fi
  '';
}
