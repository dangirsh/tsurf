# modules/users.nix
# @decision SYS-01: dev with sudo (wheel); mutableUsers=false, execWheelOnly=true
# @decision SEC-106-01: allowUnsafePlaceholders gates insecure template defaults.
#   When false (default), assertions reject placeholder SSH keys and passwordless login.
#   Public template hosts set this to true for eval; real deploys must not.
# @decision SEC-115-01: Operator/agent user split. 'dev' is the operator (wheel,
#   human admin). tsurf.agent.user (default 'agent') runs sandboxed agent tools with
#   no wheel. Assertions enforce these invariants at build time.
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

  options.tsurf.template.devUid = lib.mkOption {
    type = lib.types.int;
    default = 1000;
    description = "Numeric UID for the dev operator user (used in nftables rules)";
  };

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

    # Operator user — human admin with wheel
    users.users.dev = {
      isNormalUser = true;
      uid = cfg.devUid;
      group = "dev";
      extraGroups = [ "wheel" ];
      subUidRanges = [{ startUid = 100000; count = 65536; }];
      subGidRanges = [{ startGid = 100000; count = 65536; }];
      openssh.authorizedKeys.keys = [
        # Replace with your SSH public key
      ];
    };

    users.groups.dev = {
      gid = cfg.devUid;
    };

    # Agent user — runs sandboxed agent tools, no wheel, no docker
    users.users.${agentCfg.user} = {
      isNormalUser = true;
      uid = agentCfg.uid;
      group = agentCfg.user;
      home = agentCfg.home;
      extraGroups = [ "users" ];
      subUidRanges = [{ startUid = 200000; count = 65536; }];
      subGidRanges = [{ startGid = 200000; count = 65536; }];
      shell = pkgs.bashInteractive;
      linger = true;
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
    security.sudo.execWheelOnly = true;

    # Agent user security invariants (unconditional — always enforced)
    assertions = [
      {
        assertion = !(builtins.elem "wheel" config.users.users.${agentCfg.user}.extraGroups);
        message = "SECURITY: agent user '${agentCfg.user}' must not be in wheel group.";
      }
      {
        assertion = !(builtins.elem "docker" config.users.users.${agentCfg.user}.extraGroups);
        message = "SECURITY: agent user '${agentCfg.user}' must not be in docker group.";
      }
      {
        assertion = agentCfg.user != "dev";
        message = "SECURITY: tsurf.agent.user must differ from the operator user 'dev'.";
      }
    ] ++ lib.optionals (!cfg.allowUnsafePlaceholders) [
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

    # --- Persistence: operator + root home state ---
    environment.persistence."/persist".directories = [
      "/home/dev/.ssh"
      "/home/dev/.claude"
      "/home/dev/.config/claude"
      "/home/dev/.config/git"
      "/home/dev/.local/share/direnv"
      "/root/.ssh"
      "/root/.config/nix"
      "/root/.docker"
    ];
    environment.persistence."/persist".files = [
      "/home/dev/.gitconfig"
      "/home/dev/.bash_history"
      "/root/.gitconfig"
    ];
  };
}
