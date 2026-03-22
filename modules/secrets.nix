# @decision SEC-04: Wrapper API keys (anthropic, openai) are owned by the agent
#   user so the sandboxed wrapper process can read them at runtime. Operator-side
#   provider keys (google, xai, openrouter, github-pat) stay owned by 'dev'.
#   Other secrets inherit the sops-nix default owner unless explicitly set.
#   Private overlay may override via lib.mkForce in its own secrets.nix.
{ config, lib, ... }: {
  sops = {
    age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];

    secrets."tailscale-authkey" = {
      restartUnits = [ "tailscaled.service" ];
    };

    secrets."b2-account-id" = {};
    secrets."b2-account-key" = {};
    secrets."restic-password" = {};
    secrets."anthropic-api-key" = { owner = config.tsurf.agent.user; };
    secrets."openai-api-key" = { owner = config.tsurf.agent.user; };
    secrets."google-api-key" = { owner = "dev"; };
    secrets."xai-api-key" = { owner = "dev"; };
    secrets."openrouter-api-key" = { owner = "dev"; };
    secrets."github-pat" = { owner = "dev"; };

    # Private overlay: add service-specific secrets in your own secrets module.
    # Example:
    #   secrets."my-service-token" = { sopsFile = ../secrets/my-secrets.yaml; };

    templates."restic-b2-env" = {
      content = ''
        AWS_ACCESS_KEY_ID=${config.sops.placeholder."b2-account-id"}
        AWS_SECRET_ACCESS_KEY=${config.sops.placeholder."b2-account-key"}
      '';
    };

  };
}
