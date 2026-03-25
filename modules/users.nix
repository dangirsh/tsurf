# modules/users.nix
# @decision SEC-152-01: Two-user model: root + agent. Root is the operator (deploy,
#   maintenance, SSH). Agent runs sandboxed tools, in wheel for sudo to immutable
#   launchers only. The former 'dev' operator user is removed.
# @decision SEC-106-01: allowUnsafePlaceholders gates insecure template defaults.
#   When false (default), assertions reject placeholder SSH keys and passwordless login.
#   Public template hosts set this to true for eval; real deploys must not.
{ config, lib, pkgs, ... }:
let
  cfg = config.tsurf.template;
  agentCfg = config.tsurf.agent;

  # Placeholder key material — assertions detect these exact strings
  bootstrapKeyComment = "bootstrap-key";
  breakGlassPlaceholder = "AAAAC3NzaC1lZDI1NTE5AAAAIIb2ZbEP4YS7INuRcu/myeiajC/KD34yjfSssCnbggAJ";
in
{
  options.tsurf.template.allowUnsafePlaceholders = lib.mkEnableOption
    "unsafe public-template placeholders (NEVER enable for real deployments)";

  options.tsurf.agent = {
    user = lib.mkOption {
      type = lib.types.str;
      default = "agent";
      description = "Username for the agent user (runs sandboxed agent tools)";
    };
    uid = lib.mkOption {
      type = lib.types.int;
      default = 1001;
      description = "Numeric UID for the agent user (used in nftables rules)";
    };
    gid = lib.mkOption {
      type = lib.types.int;
      default = 1001;
      description = "Numeric GID for the agent group";
    };
    home = lib.mkOption {
      type = lib.types.str;
      default = "/home/agent";
      description = "Home directory for the agent user";
    };
    projectRoot = lib.mkOption {
      type = lib.types.str;
      default = "/data/projects";
      description = "Root directory for agent workspaces";
    };
  };

  config = {
    users.mutableUsers = false;

    # Agent user — runs sandboxed agent tools, no wheel, no docker
    users.users.${agentCfg.user} = {
      isNormalUser = true;
      uid = agentCfg.uid;
      group = agentCfg.user;
      home = agentCfg.home;
      extraGroups = [ "users" "wheel" ];
      subUidRanges = [{ startUid = 200000; count = 65536; }];
      subGidRanges = [{ startGid = 200000; count = 65536; }];
      shell = pkgs.bashInteractive;
      openssh.authorizedKeys.keys = [
        # Replace with your SSH public key in private overlay
      ];
    };

    users.groups.${agentCfg.user} = {
      gid = agentCfg.gid;
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
    security.sudo.execWheelOnly = lib.mkForce false;

    # Agent user security invariants (unconditional — always enforced)
    assertions = [
      {
        assertion = !(builtins.elem "docker" config.users.users.${agentCfg.user}.extraGroups);
        message = "SECURITY: agent user '${agentCfg.user}' must not be in docker group.";
      }
    ] ++ lib.optionals (!cfg.allowUnsafePlaceholders) [
      {
        assertion = !builtins.any (k: lib.hasInfix bootstrapKeyComment k)
          config.users.users.root.openssh.authorizedKeys.keys;
        message = ''
          Root SSH authorized_keys contains the placeholder bootstrap-key.
          Run `nix run .#tsurf-init` to generate a real key, then replace the
          placeholder in your private overlay's users.nix.
          For template evaluation only, set tsurf.template.allowUnsafePlaceholders = true.
        '';
      }
      {
        assertion = !builtins.any (k: lib.hasInfix breakGlassPlaceholder k)
          config.users.users.root.openssh.authorizedKeys.keys;
        message = ''
          Root SSH authorized_keys contains the placeholder break-glass key.
          Run `nix run .#tsurf-init` to generate a real key, then replace the
          placeholder in your private overlay's break-glass-ssh.nix.
          For template evaluation only, set tsurf.template.allowUnsafePlaceholders = true.
        '';
      }
    ];

    # --- Persistence: root home state ---
    environment.persistence."/persist".directories = [
      "/root/.ssh"
      "/root/.config/nix"
      "/root/.docker"
    ];
    environment.persistence."/persist".files = [
      "/root/.gitconfig"
    ];
  };
}
