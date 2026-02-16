# modules/repos.nix
# @decision AGENT-01, AGENT-02: Idempotent repo cloning on activation (clone-only, never pull)
{ config, pkgs, ... }: {
  system.activationScripts.clone-repos = {
    deps = [ "users" ];
    text = ''
      repos=(
        "dangirsh/parts"
        "dangirsh/claw-swap"
        "dangirsh/global-agent-conf"
      )
      CLONE_DIR="/data/projects"
      GH_TOKEN="$(cat ${config.sops.secrets."github-pat".path} 2>/dev/null || true)"

      # Ensure clone directory exists
      mkdir -p "$CLONE_DIR"

      for repo in "''${repos[@]}"; do
        name="$(basename "$repo")"
        target="$CLONE_DIR/$name"
        if [ ! -d "$target" ]; then
          echo "Cloning $repo to $target..."
          ${pkgs.git}/bin/git clone "https://''${GH_TOKEN:+$GH_TOKEN@}github.com/$repo.git" "$target" || echo "WARNING: Failed to clone $repo (will retry on next activation)"
          # Fix ownership: activation runs as root, repos must be owned by dangirsh
          chown -R dangirsh:users "$target" 2>/dev/null || true
        fi
      done
    '';
  };
}
