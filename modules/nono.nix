# modules/nono.nix
# @decision NONO-89-01: Public core ships one tsurf nono profile for Claude.
# @decision NONO-145-01: Raw provider credentials stay outside nono. Credential
#   brokering happens in the root-owned launcher path before the child drops to
#   the agent user.
{ config, lib, pkgs, ... }:
let
  cfg = config.services.nonoSandbox;

  tsurfProfile = {
    extends = "claude-code";
    meta = {
      name = "tsurf";
      version = "1.0.0";
      description = "tsurf dev host - NixOS Claude sandbox profile";
      author = "tsurf";
    };
    security = {
      groups = [
        "nix_runtime"
        "node_runtime"
        "rust_runtime"
        "python_runtime"
        "claude_code_linux"
        "claude_cache_linux"
        "user_caches_linux"
        "unlink_protection"
      ];
      signal_mode = "isolated";
      capability_elevation = false;
    };
    filesystem = {
      allow = [
        "${cfg.homeDir}/.claude"
        "${cfg.homeDir}/.config/claude"
        "${cfg.homeDir}/.gitconfig"
        "/nix/var/nix/profiles"
        "/run/current-system"
        "/run/current-system/sw"
        "/etc/profiles/per-user"
        "/etc/ssl"
        "/etc/nix"
        "/etc/static"
      ] ++ cfg.extraAllow;
      allow_file = [
        "${cfg.homeDir}/.claude.json"
        "${cfg.homeDir}/.claude.json.lock"
      ] ++ cfg.extraAllowFile;
      read_file = [
        "${cfg.homeDir}/.gitconfig"
        "${cfg.homeDir}/.gitignore_global"
        "${cfg.homeDir}/.config/git/ignore"
        "/etc/resolv.conf"
        "/etc/passwd"
        "/etc/group"
      ] ++ cfg.extraReadFile;
      # @decision NONO-84-01: Deny sensitive home paths from sandboxed agents.
      deny = [
        "/run/secrets"
        "${cfg.homeDir}/.ssh"
        "${cfg.homeDir}/.bash_history"
        "${cfg.homeDir}/.gnupg"
        "${cfg.homeDir}/.aws"
        "${cfg.homeDir}/.kube"
        "${cfg.homeDir}/.docker"
      ];
    };
    network = {
      block = false;
    };
    workdir.access = "readwrite";
    interactive = true;
  };

  profileFile = pkgs.writeText "tsurf-nono-profile.json" (builtins.toJSON tsurfProfile);
in
{
  options.services.nonoSandbox = {
    enable = lib.mkEnableOption "nono sandbox support for the core Claude wrapper";

    homeDir = lib.mkOption {
      type = lib.types.str;
      default = config.tsurf.agent.home;
      description = "Home directory for the agent user. Used in profile filesystem allow-list.";
    };

    extraAllow = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "Additional filesystem.allow directory paths merged into the tsurf nono profile.";
    };

    extraAllowFile = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "Additional filesystem.allow_file paths merged into the tsurf nono profile.";
    };

    extraReadFile = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "Additional filesystem.read_file paths merged into the tsurf nono profile.";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ pkgs.nono ];
    environment.etc."nono/profiles/tsurf.json".source = profileFile;
    environment.variables.NONO_PROFILE_PATH = "/etc/nono/profiles";
  };
}
