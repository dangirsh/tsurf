{ config, pkgs, ... }: {
  programs.bash = {
    enable = true;
    initExtra = ''
      # API keys from sops-nix secrets (read at shell start, not build time)
      export GH_TOKEN="$(cat /run/secrets/github-pat 2>/dev/null)"
      export ANTHROPIC_API_KEY="$(cat /run/secrets/anthropic-api-key 2>/dev/null)"
      export OPENAI_API_KEY="$(cat /run/secrets/openai-api-key 2>/dev/null)"
      export GOOGLE_API_KEY="$(cat /run/secrets/google-api-key 2>/dev/null)"
      export GEMINI_API_KEY="$(cat /run/secrets/google-api-key 2>/dev/null)"
      export XAI_API_KEY="$(cat /run/secrets/xai-api-key 2>/dev/null)"
      export OPENROUTER_API_KEY="$(cat /run/secrets/openrouter-api-key 2>/dev/null)"
    '';
  };
}
