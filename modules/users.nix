# modules/users.nix
# @decision SYS-01: dev with sudo (wheel) + docker group; mutableUsers=false, execWheelOnly=true
# @decision SEC-106-01: allowUnsafePlaceholders gates insecure template defaults.
#   When false (default), assertions reject placeholder SSH keys and passwordless login.
#   Public template hosts set this to true for eval; real deploys must not.
{ config, lib, pkgs, ... }:
let
  cfg = config.tsurf.template;

  # Placeholder key material — assertions detect these exact strings
  bootstrapKeyComment = "bootstrap-key";
  breakGlassPlaceholder = "AAAAC3NzaC1lZDI1NTE5AAAAIIb2ZbEP4YS7INuRcu/myeiajC/KD34yjfSssCnbggAJ";
in
{
  options.tsurf.template.allowUnsafePlaceholders = lib.mkEnableOption
    "unsafe public-template placeholders (NEVER enable for real deployments)";

  config = {
    users.mutableUsers = false;

    users.users.dev = {
      isNormalUser = true;
      extraGroups = [ "wheel" "docker" ];
      subUidRanges = [{ startUid = 100000; count = 65536; }];
      subGidRanges = [{ startGid = 100000; count = 65536; }];
      openssh.authorizedKeys.keys = [
        # Replace with your SSH public key
      ];
    };

    users.users.root = {
      openssh.authorizedKeys.keys = [
        # Bootstrap key — private overlay replaces this entire file with real users
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIac0b7Yb2yCJrPiWf+KJQJ1c7gwH7SgHTiadSSUH0tM bootstrap-key"
      ];
    };

    # Insecure defaults gated by allowUnsafePlaceholders
    users.allowNoPasswordLogin = cfg.allowUnsafePlaceholders;
    security.sudo.wheelNeedsPassword = !cfg.allowUnsafePlaceholders;
    security.sudo.execWheelOnly = true;

    assertions = lib.mkIf (!cfg.allowUnsafePlaceholders) [
      {
        assertion = !builtins.any (k: lib.hasInfix bootstrapKeyComment k)
          config.users.users.root.openssh.authorizedKeys.keys;
        message = ''
          Root SSH authorized_keys contains the placeholder bootstrap-key.
          Replace with a real key before deploying, or set
          tsurf.template.allowUnsafePlaceholders = true for template evaluation.
        '';
      }
      {
        assertion = !builtins.any (k: lib.hasInfix breakGlassPlaceholder k)
          config.users.users.root.openssh.authorizedKeys.keys;
        message = ''
          Root SSH authorized_keys contains the placeholder break-glass key.
          Replace with a real key before deploying, or set
          tsurf.template.allowUnsafePlaceholders = true for template evaluation.
        '';
      }
    ];
  };
}
