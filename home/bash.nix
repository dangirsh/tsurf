{ config, pkgs, ... }: {
  programs.bash = {
    enable = true;
    initExtra = ''
      # API keys from sops-nix secrets (read at shell start, not build time)
      export GH_TOKEN="$(cat /run/secrets/github-pat 2>/dev/null)"
      export ANTHROPIC_API_KEY="$(cat /run/secrets/anthropic-api-key 2>/dev/null)"
      export OPENAI_API_KEY="$(cat /run/secrets/openai-api-key 2>/dev/null)"
    '';
  };
}
