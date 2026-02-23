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
        "dangirsh/dangirsh.org"
      )
      CLONE_DIR="/data/projects"
      GH_TOKEN="$(cat ${config.sops.secrets."github-pat".path} 2>/dev/null || true)"

      # Write token to a temporary credential store file.
      # This prevents the token from appearing in process arguments, journal logs, or .git/config.
      CRED_FILE=$(mktemp)
      chmod 600 "$CRED_FILE"

      mkdir -p "$CLONE_DIR"

      for repo in "''${repos[@]}"; do
        name="$(basename "$repo")"
        target="$CLONE_DIR/$name"
        if [ ! -d "$target" ]; then
          echo "Cloning $repo to $target..."
          # Write credential in git credential store format
          printf 'https://x-access-token:%s@github.com\n' "$GH_TOKEN" > "$CRED_FILE"
          GIT_TERMINAL_PROMPT=0 ${pkgs.git}/bin/git \
            -c credential.helper="store --file=$CRED_FILE" \
            clone "https://github.com/$repo.git" "$target" \
            || echo "WARNING: Failed to clone $repo (will retry on next activation)"
          chown -R dangirsh:users "$target" 2>/dev/null || true
        fi
      done

      rm -f "$CRED_FILE"
    '';
  };
}
