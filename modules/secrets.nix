{ config, ... }: {
  sops = {
    defaultSopsFile = ../secrets/acfs.yaml;
    age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];

    secrets."tailscale-authkey" = {
      restartUnits = [ "tailscaled.service" ];
    };

    secrets."b2-account-id" = {};
    secrets."b2-account-key" = {};
    secrets."restic-password" = {};
    secrets."anthropic-api-key" = { owner = "dangirsh"; };
    secrets."openai-api-key" = { owner = "dangirsh"; };
    secrets."github-pat" = { owner = "dangirsh"; };
  };
}
