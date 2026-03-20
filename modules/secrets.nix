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
