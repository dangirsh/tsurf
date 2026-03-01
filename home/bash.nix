{ config, pkgs, ... }: {
  programs.bash = {
    enable = true;
    initExtra = ''
      # @decision SEC47-34: On-demand API key loading via shell functions
      # @rationale: Keys are only loaded when explicitly needed, reducing the
      #   exposure window. Previously all keys were exported at shell init,
      #   making them visible in /proc/PID/environ of every child process.

      # Load all API keys into current shell (for interactive use)
      load-api-keys() {
        export GH_TOKEN="$(cat /run/secrets/github-pat 2>/dev/null)"
        export ANTHROPIC_API_KEY="$(cat /run/secrets/anthropic-api-key 2>/dev/null)"
        export OPENAI_API_KEY="$(cat /run/secrets/openai-api-key 2>/dev/null)"
        export GOOGLE_API_KEY="$(cat /run/secrets/google-api-key 2>/dev/null)"
        export GEMINI_API_KEY="$(cat /run/secrets/google-api-key 2>/dev/null)"
        export XAI_API_KEY="$(cat /run/secrets/xai-api-key 2>/dev/null)"
        export OPENROUTER_API_KEY="$(cat /run/secrets/openrouter-api-key 2>/dev/null)"
        echo "API keys loaded into current shell"
      }

      # GH_TOKEN is needed for gh CLI in most sessions -- auto-load it
      # Other keys are loaded on demand via load-api-keys
      export GH_TOKEN="$(cat /run/secrets/github-pat 2>/dev/null)"
    '';
  };
}
