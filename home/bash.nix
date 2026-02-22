{ config, pkgs, ... }: {
  programs.bash = {
    enable = true;
    initExtra = ''
      # Disable mouse tracking in Node.js TUI apps for native terminal scrollback (zmx)
      if [ -f "$HOME/.local/lib/disable-mouse.js" ]; then
        export NODE_OPTIONS="''${NODE_OPTIONS:+$NODE_OPTIONS }--require=$HOME/.local/lib/disable-mouse.js"
      fi

      # API keys from sops-nix secrets (read at shell start, not build time)
      export GH_TOKEN="$(cat /run/secrets/github-pat 2>/dev/null)"
      export ANTHROPIC_API_KEY="$(cat /run/secrets/anthropic-api-key 2>/dev/null)"
      export OPENAI_API_KEY="$(cat /run/secrets/openai-api-key 2>/dev/null)"
    '';
  };
}
