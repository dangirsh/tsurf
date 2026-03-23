# @decision SEC-04: Core sandbox credentials stay readable by the agent user so the
#   parent wrapper can load them from /run/secrets/ before entering nono. Optional
#   extras may reuse the same ownership model. Operator-side credentials stay owned
#   by 'dev'. Private overlay may override via lib.mkForce in its own secrets.nix.
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
