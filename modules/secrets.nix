# @decision SEC-04: API key secrets owned by 'dev' in public template.
# @rationale: Private overlay overrides owner to the real username via
#   lib.mkForce in its own secrets.nix. This two-layer pattern is inherent
#   to the public/private split — public declares secrets with template
#   ownership, private overrides to actual user.
{ config, lib, ... }: {
  sops = {
    age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];

    secrets."tailscale-authkey" = {
      restartUnits = [ "tailscaled.service" ];
    };

    secrets."b2-account-id" = {};
    secrets."b2-account-key" = {};
    secrets."restic-password" = {};
    secrets."anthropic-api-key" = { owner = "dev"; };
    secrets."openai-api-key" = { owner = "dev"; };
    secrets."google-api-key" = { owner = "dev"; };
    secrets."xai-api-key" = { owner = "dev"; };
    secrets."openrouter-api-key" = { owner = "dev"; };
    secrets."github-pat" = { owner = "dev"; };

    secrets."conway-api-key" = {
      sopsFile = lib.mkForce ../secrets/neurosys.yaml;
    };

    secrets."cloudflare-dns-token" = { owner = "dev"; };

    # @decision SEC-03: Per-secret sopsFile override for host-specific secrets.
    # @rationale: defaultSopsFile is set per-host in hosts/*/default.nix (neurosys.yaml
    #   or ovh.yaml). These secrets only exist in neurosys.yaml regardless of host.
    #   mkForce overrides the host default to point at the correct sops file.
    #   The private overlay's matrix.nix uses mkOverride 40 (beats mkForce=50)
    #   to redirect OVH-only secrets to ovh.yaml.
    secrets."openclaw-mark-gateway-token"        = { sopsFile = lib.mkForce ../secrets/neurosys.yaml; };
    secrets."openclaw-lou-gateway-token"         = { sopsFile = lib.mkForce ../secrets/neurosys.yaml; };
    secrets."openclaw-alexia-gateway-token"      = { sopsFile = lib.mkForce ../secrets/neurosys.yaml; };
    secrets."openclaw-ari-gateway-token"         = { sopsFile = lib.mkForce ../secrets/neurosys.yaml; };
    secrets."openclaw-jordan-claw-gateway-token" = { sopsFile = lib.mkForce ../secrets/neurosys.yaml; };
    secrets."openclaw-tal-claw-gateway-token"    = { sopsFile = lib.mkForce ../secrets/neurosys.yaml; };

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
