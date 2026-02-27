{ config, lib, ... }: {
  sops = {
    age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];

    secrets."tailscale-authkey" = {
      restartUnits = [ "tailscaled.service" ];
    };

    secrets."b2-account-id" = {};
    secrets."b2-account-key" = {};
    secrets."restic-password" = {};
    secrets."anthropic-api-key" = { owner = "dangirsh"; };
    secrets."openai-api-key" = { owner = "dangirsh"; };
    secrets."google-api-key" = { owner = "dangirsh"; };
    secrets."xai-api-key" = { owner = "dangirsh"; };
    secrets."openrouter-api-key" = { owner = "dangirsh"; };
    secrets."github-pat" = { owner = "dangirsh"; };

    secrets."cloudflare-dns-token" = { owner = "acme"; };
    secrets."conway-api-key" = {
      sopsFile = ../secrets/neurosys.yaml;
      owner = "automaton";
      group = "automaton";
    };

    # --- Matrix / messaging bridge secrets ---
    secrets."telegram-api-id" = {
      sopsFile = lib.mkForce ../secrets/neurosys.yaml;
    };
    secrets."telegram-api-hash" = {
      sopsFile = lib.mkForce ../secrets/neurosys.yaml;
    };
    secrets."matrix-registration-token" = {
      sopsFile = lib.mkForce ../secrets/neurosys.yaml;
    };

    templates."restic-b2-env" = {
      content = ''
        AWS_ACCESS_KEY_ID=${config.sops.placeholder."b2-account-id"}
        AWS_SECRET_ACCESS_KEY=${config.sops.placeholder."b2-account-key"}
      '';
    };

    templates."automaton-env" = {
      owner = "automaton";
      content = ''
        ANTHROPIC_BASE_URL=http://127.0.0.1:9091
        ANTHROPIC_API_KEY=placeholder-for-secret-proxy
      '';
    };
  };
}
