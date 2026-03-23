# modules/nono.nix
# @decision NONO-89-01: Full nono module — credential bridge + extensible tsurf profile.
#   Installs nono system-wide and writes the tsurf profile JSON to
#   /etc/nono/profiles/tsurf.json so wrapper scripts reference the profile
#   by full path (agent-sandbox.nix uses /etc/nono/profiles/tsurf.json).
# @decision NONO-118-01: Proxy credential mode with env:// URIs.
#   The wrapper reads /run/secrets/* into env vars in the parent process.
#   nono's reverse proxy loads credentials via env:// URIs, generates a
#   per-session 256-bit phantom token, and passes only the phantom token
#   to the sandboxed child. The child never sees real API keys.
#   No system keystore (org.freedesktop.secrets) is required — env:// bypasses it.
{ config, lib, pkgs, ... }:
let
  cfg = config.services.nonoSandbox;

  # Credential definitions: service name -> sops secret + env var + API upstream.
  # The wrapper reads /run/secrets/<secretName> into the parent env.
  # nono's proxy loads credentials via env://<envVar>, generates a phantom
  # token, and the child only receives the phantom token + a localhost base URL.
  #
  # Only providers with sops secrets declared in the public template are listed here.
  # Private overlay can extend via services.nonoSandbox.extraCredentials.
  credentialDefs = {
    anthropic   = { secretName = "anthropic-api-key";   envVar = "ANTHROPIC_API_KEY";
                    upstream = "https://api.anthropic.com";
                    inject_header = "x-api-key"; credential_format = "{}"; };
    openai      = { secretName = "openai-api-key";      envVar = "OPENAI_API_KEY";
                    upstream = "https://api.openai.com";
                    inject_header = "Authorization"; credential_format = "Bearer {}"; };
  } // cfg.extraCredentials;

  # custom_credentials for nono proxy mode: each service gets a custom
  # credential definition with env:// URI so nono reads from the parent
  # process env (populated by the wrapper from /run/secrets/).
  customCredentials = lib.mapAttrs
    (_name: cred: {
      inherit (cred) upstream inject_header credential_format;
      credential_key = "env://${cred.envVar}";
      env_var = cred.envVar;
    })
    credentialDefs;

  # The tsurf profile JSON.
  # Extends claude-code profile with NixOS-specific filesystem access.
  # Profile loading: nono checks ~/.config/nono/profiles/<name>.json first,
  # then NONO_PROFILE_PATH directories, then built-ins.
  # We deliver via NONO_PROFILE_PATH=/etc/nono/profiles (set system-wide).
  #
  # Key design decisions:
  # - extends "claude-code": inherits base groups (nix_runtime, claude_cache_linux, etc.)
  # - workdir.access = "readwrite": CWD is always writable
  # - custom_credentials with env:// URIs: proxy mode without system keystore
  # - credentials injected via --credential in agent-sandbox.nix wrapper
  tsurfProfile = {
    extends = "claude-code";
    meta = {
      name = "tsurf";
      version = "1.0.0";
      description = "tsurf dev host — NixOS agent sandbox profile";
      author = "tsurf";
    };
    security = {
      groups = [ "nix_runtime" "node_runtime" "rust_runtime" "python_runtime"
                 "claude_code_linux" "claude_cache_linux" "user_caches_linux"
                 "unlink_protection" ];
      signal_mode = "isolated";
      capability_elevation = false;
    };
    filesystem = {
      # NixOS-specific read paths not covered by built-in system_read_linux group
      # Read access to /data/projects removed — agent-sandbox.nix wrapper
      # grants --read to the current git repo root only (SANDBOX-105-02).
      allow = [
        # NOTE: Do NOT grant cfg.homeDir directly — it overlaps nono's
        # protected state root (~/.nono). Grant specific subdirs instead.
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
      # @decision NONO-84-01: Deny sensitive home subdirectories from sandboxed agents.
      #   homeDir is allowed for agent config/cache access, but these subdirs contain
      #   credentials or sensitive data that agents must not read.
      #   Landlock deny entries act as exclusion filters within broader allows.
      #   Effectiveness depends on nono version and Landlock kernel support — verify
      #   with live testing after deploy (see Plan 84-02 Task 2).
      deny = [
        "/run/secrets"
        "${cfg.homeDir}/.ssh"
        "${cfg.homeDir}/.bash_history"
        "${cfg.homeDir}/.config/syncthing"
        "${cfg.homeDir}/.gnupg"
        "${cfg.homeDir}/.aws"
        "${cfg.homeDir}/.kube"
        "${cfg.homeDir}/.docker"
      ];
    };
    network = {
      block = false;
      custom_credentials = customCredentials;
    };
    workdir = { access = "readwrite"; };
    interactive = true;
  };

  profileFile = pkgs.writeText "tsurf-nono-profile.json"
    (builtins.toJSON tsurfProfile);

in
{
  options.services.nonoSandbox = {
    enable = lib.mkEnableOption "nono sandbox support for the core claude wrapper and opt-in extra agents";

    homeDir = lib.mkOption {
      type = lib.types.str;
      default = config.tsurf.agent.home;
      description = "Home directory for the agent user. Used in profile filesystem allow-list.";
    };

    extraCredentials = lib.mkOption {
      type = lib.types.attrsOf (lib.types.attrsOf lib.types.str);
      default = {};
      description = ''
        Additional provider credential definitions merged into the nono profile.
        Each key is a service name; value is an attrset with: secretName, envVar,
        upstream, inject_header, credential_format.
        Example: { google = { secretName = "google-api-key"; envVar = "GOOGLE_API_KEY";
          upstream = "https://generativelanguage.googleapis.com";
          inject_header = "x-goog-api-key"; credential_format = "{}"; }; }
      '';
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

    _credentialDefs = lib.mkOption {
      type = lib.types.attrsOf (lib.types.attrsOf lib.types.str);
      internal = true;
      description = "Merged credential definitions for internal module consumers.";
    };

  };

  config = lib.mkMerge [
    {
      services.nonoSandbox._credentialDefs = credentialDefs;
    }
    (lib.mkIf cfg.enable {
      # Make nono available system-wide
      environment.systemPackages = [ pkgs.nono ];

      # Install tsurf profile to /etc/nono/profiles/ and point nono at it
      # via NONO_PROFILE_PATH so `--profile tsurf` resolves without user config.
      environment.etc."nono/profiles/tsurf.json".source = profileFile;

      # Set NONO_PROFILE_PATH system-wide so nono can find /etc/nono/profiles/
      environment.variables.NONO_PROFILE_PATH = "/etc/nono/profiles";
    })
  ];
}
