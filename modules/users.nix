# modules/users.nix
# Root owns the machine and the dedicated agent user owns sandboxed workspaces.
# Real root SSH keys are expected from a private overlay or `tsurf-init`; the public repo only bypasses that in eval fixtures.
# @decision SEC-152-01: Two-user model: root + agent. Launcher sudo access comes from explicit sudoers rules, not wheel membership.
# @decision SEC-106-01: allowUnsafePlaceholders exists only so eval fixtures can build without private root SSH material or the root-login lockout assertion.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.tsurf.template;
  agentCfg = config.tsurf.agent;
in
{
  options.tsurf.template.allowUnsafePlaceholders = lib.mkEnableOption "unsafe public-template placeholders (NEVER enable for real deployments)";

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

    # Agent user — runs sandboxed agent tools and owns agent workspaces.
    users.users.${agentCfg.user} = {
      isNormalUser = true;
      uid = agentCfg.uid;
      group = agentCfg.user;
      home = agentCfg.home;
      extraGroups = [ "users" ];
      subUidRanges = [
        {
          startUid = 200000;
          count = 65536;
        }
      ];
      subGidRanges = [
        {
          startGid = 200000;
          count = 65536;
        }
      ];
      shell = pkgs.bashInteractive;
      openssh.authorizedKeys.keys = [ ];
    };

    users.groups.${agentCfg.user} = {
      gid = agentCfg.gid;
    };

    users.users.root.openssh.authorizedKeys.keys = lib.mkDefault [ ];
    users.allowNoPasswordLogin = lib.mkDefault cfg.allowUnsafePlaceholders;

    # Agent launchers use explicit sudoers rules, so non-wheel callers must be allowed.
    security.sudo.execWheelOnly = lib.mkForce false;

    # Agent user security invariants (unconditional — always enforced).
    assertions = [
      {
        assertion = !(builtins.elem "docker" config.users.users.${agentCfg.user}.extraGroups);
        message = "SECURITY: agent user '${agentCfg.user}' must not be in docker group.";
      }
    ]
    ++ lib.optionals (!cfg.allowUnsafePlaceholders) [
      {
        assertion = config.users.users.root.openssh.authorizedKeys.keys != [ ];
        message = ''
          Root SSH authorized_keys is empty.
          Run `nix run .#tsurf-init -- --overlay-dir /path/to/private-overlay`
          to generate a root key and materialize modules/root-ssh.nix, or set
          users.users.root.openssh.authorizedKeys.keys in your private overlay.
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
