{ config, lib, ... }: {
  sops = {
    age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];

    secrets."tailscale-authkey" = {
      restartUnits = [ "tailscaled.service" ];
    };

    secrets."b2-account-id" = {};
    secrets."b2-account-key" = {};
    secrets."restic-password" = {};
    secrets."anthropic-api-key" = { owner = "myuser"; };
    secrets."openai-api-key" = { owner = "myuser"; };
    secrets."google-api-key" = { owner = "myuser"; };
    secrets."xai-api-key" = { owner = "myuser"; };
    secrets."openrouter-api-key" = { owner = "myuser"; };
    secrets."github-pat" = { owner = "myuser"; };

    secrets."cloudflare-dns-token" = { owner = "myuser"; };

    secrets."openclaw-mark-gateway-token"    = { sopsFile = lib.mkForce ../secrets/neurosys.yaml; };
    secrets."openclaw-lou-gateway-token"     = { sopsFile = lib.mkForce ../secrets/neurosys.yaml; };
    secrets."openclaw-alexia-gateway-token"  = { sopsFile = lib.mkForce ../secrets/neurosys.yaml; };
    secrets."openclaw-ari-gateway-token"     = { sopsFile = lib.mkForce ../secrets/neurosys.yaml; };
    secrets."openclaw-jordan-claw-gateway-token"  = { sopsFile = lib.mkForce ../secrets/neurosys.yaml; };

    # --- Matrix / messaging bridge secrets ---
    # telegram-api-id and telegram-api-hash managed by parts module (parts.yaml)
    secrets."matrix-registration-token" = {
      sopsFile = lib.mkForce ../secrets/neurosys.yaml;
    };

    # Cachix auth token — used by deploy.sh to push system closure after each deploy
    secrets."cachix-auth-token" = {};

    templates."restic-b2-env" = {
      content = ''
        AWS_ACCESS_KEY_ID=${config.sops.placeholder."b2-account-id"}
        AWS_SECRET_ACCESS_KEY=${config.sops.placeholder."b2-account-key"}
      '';
    };

  };
}
