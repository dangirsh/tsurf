# @decision SEC-04: Core provider API keys stay root-owned. The brokered launcher
#   reads them before entering the sandbox and exposes only per-session loopback
#   tokens to the agent child. Operator-side credentials are owned by the agent user.
#   Private overlay may override via lib.mkForce in its own secrets.nix.
{ config, ... }:
{
  sops = {
    # Match the OpenSSH host key path in modules/networking.nix. Using the
    # persisted path directly avoids depending on /etc/ssh mount ordering.
    age.sshKeyPaths = [ "/persist/etc/ssh/ssh_host_ed25519_key" ];

    secrets."anthropic-api-key" = {
      owner = "root";
    };
    secrets."openai-api-key" = {
      owner = "root";
    };
    secrets."google-api-key" = {
      owner = config.tsurf.agent.user;
    };
    secrets."xai-api-key" = {
      owner = "root";
    };
    secrets."openrouter-api-key" = {
      owner = "root";
    };
    secrets."github-pat" = {
      owner = config.tsurf.agent.user;
    };

    # Private overlay: add service-specific secrets in your own secrets module.
    # Example:
    #   secrets."my-service-token" = { sopsFile = ../secrets/my-secrets.yaml; };
  };
}
