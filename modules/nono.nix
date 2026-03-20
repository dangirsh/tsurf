# modules/nono.nix
# @decision NONO-89-01: Full nono module — credential bridge + tsurf profile.
#   Installs nono system-wide and writes the tsurf profile JSON to
#   /etc/nono/profiles/tsurf.json so wrapper scripts reference the profile
#   by full path (agent-sandbox.nix uses /etc/nono/profiles/tsurf.json).
# @decision NONO-89-02: Credentials are passed via env injection
#   (--env-credential-map in the wrapper script, see agent-sandbox.nix).
#   The wrapper reads /run/secrets/* into env vars, then nono injects them into
#   the sandboxed child as environment variables. The child receives real API keys.
#   nono proxy credential mode is not used (requires org.freedesktop.secrets,
#   unavailable on headless servers). Env injection is used instead.
{ config, lib, pkgs, ... }:
let
  cfg = config.services.nonoSandbox;

  # Credential definitions: env var name -> secret file name in /run/secrets/
  # The wrapper script exports these before calling nono; the profile maps
  # them (via env://) into the child as the same env var name.
  credentialDefs = {
    anthropic   = { secretName = "anthropic-api-key";   envVar = "ANTHROPIC_API_KEY"; };
    openai      = { secretName = "openai-api-key";      envVar = "OPENAI_API_KEY"; };
    google      = { secretName = "google-api-key";      envVar = "GOOGLE_API_KEY"; };
    xai         = { secretName = "xai-api-key";         envVar = "XAI_API_KEY"; };
    openrouter  = { secretName = "openrouter-api-key";  envVar = "OPENROUTER_API_KEY"; };
  };

  # env_credentials section: maps "env://ENV_VAR" -> "DEST_ENV_VAR"
  # When both source and destination are the same, the child receives the same
  # env var name but populated from the nono proxy, not the real parent env.
  envCredentials = lib.mapAttrs'
    (_name: cred: lib.nameValuePair "env://${cred.envVar}" cred.envVar)
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
  # - env_credentials section defined but unused (proxy mode requires system keystore)
  # - credentials injected via --env-credential-map in agent-sandbox.nix wrapper
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
        "${cfg.homeDir}/.codex"
        "${cfg.homeDir}/.pi"
        "${cfg.homeDir}/.pi/agent"
        "${cfg.homeDir}/.gitconfig"
        "/nix/var/nix/profiles"
        "/run/current-system"
        "/run/current-system/sw"
        "/etc/profiles/per-user"
        "/etc/ssl"
        "/etc/nix"
        "/etc/static"
      ];
      allow_file = [
        "${cfg.homeDir}/.claude.json"
        "${cfg.homeDir}/.claude.json.lock"
        "${cfg.homeDir}/.pi/agent/auth.json"
        "${cfg.homeDir}/.pi/agent/settings.json"
      ];
      read_file = [
        "${cfg.homeDir}/.gitconfig"
        "${cfg.homeDir}/.gitignore_global"
        "${cfg.homeDir}/.config/git/ignore"
        "/etc/resolv.conf"
        "/etc/passwd"
        "/etc/group"
      ];
      # @decision NONO-84-01: Deny sensitive home subdirectories from sandboxed agents.
      #   homeDir is allowed for agent config/cache access, but these subdirs contain
      #   credentials or sensitive data that agents must not read.
      #   Landlock deny entries act as exclusion filters within broader allows.
      #   Effectiveness depends on nono version and Landlock kernel support — verify
      #   with live testing after deploy (see Plan 84-02 Task 2).
      deny = [
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
    };
    workdir = { access = "readwrite"; };
    undo = {
      exclude_patterns = [ "node_modules" ".next" "__pycache__" "target" ".git" ];
      exclude_globs = [ "*.tmp.[0-9]*.[0-9]*" ];
    };
    interactive = true;
  };

  profileFile = pkgs.writeText "tsurf-nono-profile.json"
    (builtins.toJSON tsurfProfile);

in
{
  options.services.nonoSandbox = {
    enable = lib.mkEnableOption "nono sandbox wrappers for claude, codex, and pi";

    homeDir = lib.mkOption {
      type = lib.types.str;
      default = "/home/dev";
      description = "Home directory for the agent user. Used in profile filesystem allow-list.";
    };

  };

  config = lib.mkIf cfg.enable {
    # Make nono available system-wide
    environment.systemPackages = [ pkgs.nono ];

    # Install tsurf profile to /etc/nono/profiles/ and point nono at it
    # via NONO_PROFILE_PATH so `--profile tsurf` resolves without user config.
    environment.etc."nono/profiles/tsurf.json".source = profileFile;

    # Set NONO_PROFILE_PATH system-wide so nono can find /etc/nono/profiles/
    environment.variables.NONO_PROFILE_PATH = "/etc/nono/profiles";
  };
}
