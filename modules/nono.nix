# modules/nono.nix
# @decision NONO-159-01: nono is the filesystem/process sandbox only.
#   Iron owns public-base credential replacement and mediated HTTP(S) egress.
# @decision NONO-145-03: Extended deny list covers registry tokens and cloud credential directories.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.nonoSandbox;

  tsurfProfile = {
    meta = {
      name = "tsurf";
      version = "1.0.0";
      description = "tsurf agent sandbox base profile";
      author = "tsurf";
    };
    groups = {
      include = [
        "nix_runtime"
        "node_runtime"
        "rust_runtime"
        "python_runtime"
        "user_caches_linux"
        "unlink_protection"
      ];
    };
    security = {
      signal_mode = "isolated";
      capability_elevation = false;
    };
    filesystem = {
      allow = [
        "${cfg.homeDir}/.gitconfig"
        "/nix/var/nix/profiles"
        "/run/current-system"
        "/run/current-system/sw"
        "/etc/profiles/per-user"
        "/etc/ssl"
        "/etc/nix"
        "/etc/static"
      ]
      ++ cfg.extraAllow;
      allow_file = cfg.extraAllowFile;
      read_file = [
        "${cfg.homeDir}/.gitconfig"
        "${cfg.homeDir}/.gitignore_global"
        "${cfg.homeDir}/.config/git/ignore"
        "/etc/resolv.conf"
        "/etc/passwd"
        "/etc/group"
      ]
      ++ cfg.extraReadFile;
      # @decision NONO-84-01: Deny sensitive home paths from sandboxed agents.
      # Extended by ecosystem review (Trail of Bits credential path list).
      # @decision SEC-AGENT-AUTH-01: Agent auth/session caches are denied by
      # default. API-backed wrappers must use brokered credentials plus an
      # isolated non-secret state dir instead of raw login state.
      deny = [
        "/run/secrets"
        "${cfg.homeDir}/.ssh"
        "${cfg.homeDir}/.bash_history"
        "${cfg.homeDir}/.gnupg"
        "${cfg.homeDir}/.aws"
        "${cfg.homeDir}/.kube"
        "${cfg.homeDir}/.docker"
        "${cfg.homeDir}/.npmrc"
        "${cfg.homeDir}/.pypirc"
        "${cfg.homeDir}/.gem"
        "${cfg.homeDir}/.config/gh"
        "${cfg.homeDir}/.git-credentials"
        "${cfg.homeDir}/.claude"
        "${cfg.homeDir}/.config/claude"
        "${cfg.homeDir}/.claude.json"
        "${cfg.homeDir}/.claude.json.lock"
        "${cfg.homeDir}/.codex"
        "${cfg.homeDir}/.config/codex"
        "${cfg.homeDir}/.agents"
        "/etc/nono"
      ];
    };
    network = {
      block = !cfg.allowDirectNetwork;
    };
    workdir.access = "readwrite";
    interactive = true;
  };

  profileText = builtins.toJSON tsurfProfile;
in
{
  options.services.nonoSandbox = {
    enable = lib.mkEnableOption "nono sandbox base profile for agent wrappers";

    homeDir = lib.mkOption {
      type = lib.types.str;
      default = config.tsurf.agent.home;
      description = "Home directory for the agent user. Used in profile filesystem allow-list.";
    };

    extraAllow = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Additional filesystem.allow directory paths merged into the tsurf nono profile.";
    };

    extraAllowFile = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Additional filesystem.allow_file paths merged into the tsurf nono profile.";
    };

    extraReadFile = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Additional filesystem.read_file paths merged into the tsurf nono profile.";
    };

    allowDirectNetwork = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Allow direct sandbox network access. Leave this disabled for
        credential-backed wrappers so nono's reverse proxy is the only route to
        brokered providers.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ pkgs.nono ];
    environment.etc."nono/profiles/tsurf.json".text = profileText;
    environment.variables.NONO_PROFILE_PATH = "/etc/nono/profiles";
  };
}
