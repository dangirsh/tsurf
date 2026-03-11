# modules/agent-sandbox.nix
# @decision SANDBOX-73-01: Wrapper scripts replace bare agent binaries on dev hosts.
#   Bubblewrap sandbox is the default; --no-sandbox requires AGENT_ALLOW_NOSANDBOX=1.
# @decision SANDBOX-73-02: Audit log at /data/projects/.agent-audit/agent-launches.log.
#   TSV format: timestamp, user, pid, mode, workdir, binary, args.
# @decision SANDBOX-73-03: Secret-proxy env vars injected only when secretProxyPort is set.
#   Public repo evaluates with port=null (no proxy); private overlay sets port+placeholder.
{ config, lib, pkgs, ... }:
let
  cfg = config.services.agentSandbox;

  auditLog = "/data/projects/.agent-audit/agent-launches.log";

  # Static bwrap args (no runtime shell variables).
  # $PWD is handled separately in the shell script as a dynamic bind.
  staticBwrapArgs = [
    "--ro-bind" "/nix/store" "/nix/store"
    "--ro-bind" "/run/current-system" "/run/current-system"
    "--ro-bind" "/data/projects" "/data/projects"
    "--proc" "/proc"
    "--dev" "/dev"
    "--tmpfs" "/tmp"
    "--dir" cfg.homeDir
    "--tmpfs" "${cfg.homeDir}/.cache"
    "--ro-bind" "/etc/resolv.conf" "/etc/resolv.conf"
    "--ro-bind" "/etc/passwd" "/etc/passwd"
    "--ro-bind" "/etc/group" "/etc/group"
    "--ro-bind" "/etc/ssl" "/etc/ssl"
    "--ro-bind" "/etc/nix" "/etc/nix"
    "--bind" "/nix/var/nix/daemon-socket" "/nix/var/nix/daemon-socket"
    "--setenv" "CLAUDE_CODE_BUBBLEWRAP" "1"
    "--setenv" "HOME" cfg.homeDir
    "--unsetenv" "GH_TOKEN"
    "--die-with-parent"
    "--new-session"
  ];

  # Conditionally add secret-proxy env vars
  proxyArgs = lib.optionals (cfg.secretProxyPort != null) [
    "--setenv" "ANTHROPIC_BASE_URL" "http://127.0.0.1:${toString cfg.secretProxyPort}"
    "--setenv" "ANTHROPIC_API_KEY" cfg.secretProxyPlaceholder
  ];

  allStaticArgs = staticBwrapArgs ++ proxyArgs;

  # Build the bwrap argument string for embedding in the shell script.
  # All values are static Nix-interpolated paths/strings — no shell variables.
  bwrapArgsStr = lib.concatStringsSep " " (map lib.escapeShellArg allStaticArgs);

  mkWrapper = { name, realPkg, realBin }:
    (pkgs.writeShellApplication {
      inherit name;
      runtimeInputs = [ pkgs.bubblewrap pkgs.coreutils ];
      text = ''
        AUDIT_LOG="${auditLog}"
        REAL_BINARY="${realPkg}/bin/${realBin}"

        # Audit logging helper
        audit_log() {
          local mode="$1"
          shift
          printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
            "$(date -Iseconds)" "$(whoami)" "$$" "$mode" "$PWD" "${name}" "$*" \
            >> "$AUDIT_LOG" 2>/dev/null || true
        }

        # --no-sandbox override check
        if [[ "''${1:-}" == "--no-sandbox" ]]; then
          if [[ "''${AGENT_ALLOW_NOSANDBOX:-}" != "1" ]]; then
            echo "ERROR: --no-sandbox requires AGENT_ALLOW_NOSANDBOX=1" >&2
            echo "  Run: AGENT_ALLOW_NOSANDBOX=1 ${name} --no-sandbox [args...]" >&2
            exit 1
          fi
          echo "WARNING: Running ${name} WITHOUT sandbox. All secrets are accessible." >&2
          audit_log "nosandbox" "''${@:2}"
          shift
          exec "$REAL_BINARY" "$@"
        fi

        # Default: sandboxed execution
        audit_log "sandboxed" "$@"

        # Build bwrap args array from static Nix-generated args
        # shellcheck disable=SC2206
        BWRAP_ARGS=(${bwrapArgsStr})

        # Dynamic: bind current working directory read-write (runtime shell variable)
        BWRAP_ARGS+=("--bind" "$PWD" "$PWD")

        # Conditionally mount dotfiles if they exist
        if [[ -f "${cfg.homeDir}/.gitconfig" ]]; then
          BWRAP_ARGS+=("--ro-bind" "${cfg.homeDir}/.gitconfig" "${cfg.homeDir}/.gitconfig")
        fi
        if [[ -d "${cfg.homeDir}/.config/claude" ]]; then
          BWRAP_ARGS+=("--ro-bind" "${cfg.homeDir}/.config/claude" "${cfg.homeDir}/.config/claude")
        fi

        exec bwrap "''${BWRAP_ARGS[@]}" -- "$REAL_BINARY" "$@"
      '';
    }).overrideAttrs (old: { meta = (old.meta or { }) // { priority = 4; }; });

  claude-sandboxed = mkWrapper {
    name = "claude";
    realPkg = pkgs.claude-code;
    realBin = "claude";
  };

  codex-sandboxed = mkWrapper {
    name = "codex";
    realPkg = pkgs.codex;
    realBin = "codex";
  };
in
{
  options.services.agentSandbox = {
    enable = lib.mkEnableOption "sandboxed agent wrappers for claude and codex";

    homeDir = lib.mkOption {
      type = lib.types.str;
      default = "/home/dev";
      description = "Home directory for the dev user (private overlay overrides to /home/dangirsh).";
    };

    secretProxyPort = lib.mkOption {
      type = lib.types.nullOr lib.types.port;
      default = null;
      description = "Secret proxy port. When set, ANTHROPIC_BASE_URL and ANTHROPIC_API_KEY are injected into the sandbox.";
    };

    secretProxyPlaceholder = lib.mkOption {
      type = lib.types.str;
      default = "sk-ant-api03-placeholder";
      description = "Placeholder API key for secret proxy.";
    };
  };

  config = lib.mkIf cfg.enable {
    # Replace bare agent binaries with sandboxed wrappers (meta.priority = 4 wins over default 5).
    # The real binaries remain at their Nix store paths (referenced inside wrappers).
    environment.systemPackages = [
      claude-sandboxed
      codex-sandboxed
    ];
  };
}
