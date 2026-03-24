# @decision SEC-04: Core provider API keys stay root-owned. The brokered launcher
#   reads them before entering the sandbox and exposes only per-session loopback
#   tokens to the agent child. Operator-side credentials stay owned by 'dev'.
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
    secrets."anthropic-api-key" = { owner = "root"; };
    secrets."openai-api-key" = { owner = "root"; };
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
