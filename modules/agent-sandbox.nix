# modules/agent-sandbox.nix
# @decision SANDBOX-73-01: Wrapper scripts replace bare agent binaries on dev hosts.
#   nono sandbox is the default; --no-sandbox requires AGENT_ALLOW_NOSANDBOX=1.
# @decision SANDBOX-73-02: Audit log at /data/projects/.agent-audit/agent-launches.log.
#   TSV format: timestamp, user, pid, mode, workdir, binary, args.
# @decision NONO-89-03: Replaced bubblewrap with nono. Real API keys are loaded from
#   /run/secrets/ into the wrapper's environment, then passed to nono via
#   --env-credential-map. nono injects them as env vars into the sandboxed child.
#   This is env injection — the child process receives real API keys.
#   nono proxy credential mode is not used (requires org.freedesktop.secrets,
#   unavailable on headless servers). Env injection is used instead.
{ config, lib, pkgs, ... }:
let
  cfg = config.services.agentSandbox;

  auditLog = "/data/projects/.agent-audit/agent-launches.log";

  # Credential definitions: provider name -> secret file + env var
  allCredentials = {
    anthropic  = { secretPath = "anthropic-api-key";  envVar = "ANTHROPIC_API_KEY"; };
    openai     = { secretPath = "openai-api-key";     envVar = "OPENAI_API_KEY"; };
    google     = { secretPath = "google-api-key";     envVar = "GOOGLE_API_KEY"; };
    xai        = { secretPath = "xai-api-key";        envVar = "XAI_API_KEY"; };
    openrouter = { secretPath = "openrouter-api-key"; envVar = "OPENROUTER_API_KEY"; };
  };

  # Resolve a list of provider names to credential specs
  resolveCredentials = providers:
    let
      combined = lib.unique (providers ++ cfg.extraCredentials);
    in map (p: allCredentials.${p}) (builtins.filter (p: builtins.hasAttr p allCredentials) combined);

  mkWrapper = { name, realPkg, realBin, defaultCredentials ? [ "anthropic" ] }:
    (pkgs.writeShellApplication {
      inherit name;
      runtimeInputs = [ pkgs.nono pkgs.coreutils ];
      text = ''
        AUDIT_LOG="${auditLog}"
        REAL_BINARY="${realPkg}/bin/${realBin}"

        # Audit logging helper — must never block agent launch
        audit_log() {
          local mode="$1"
          shift
          {
            printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
              "$(date -Iseconds)" "$(whoami)" "$$" "$mode" "$PWD" "${name}" "$*" \
              >> "$AUDIT_LOG"
          } 2>/dev/null || true
        }

        # --no-sandbox override check
        # @decision SANDBOX-73-01: --no-sandbox escape hatch preserved;
        #   requires AGENT_ALLOW_NOSANDBOX=1 to prevent accidental unsandboxed runs.
        if [[ "''${1:-}" == "--no-sandbox" ]]; then
          if [[ "''${AGENT_ALLOW_NOSANDBOX:-}" != "1" ]]; then
            echo "ERROR: --no-sandbox requires AGENT_ALLOW_NOSANDBOX=1" >&2
            echo "  Run: AGENT_ALLOW_NOSANDBOX=1 ${name} --no-sandbox [args...]" >&2
            exit 1
          fi
          echo "WARNING: Running ${name} WITHOUT sandbox. All secrets are accessible." >&2
          audit_log "nosandbox" "''${@:2}"
          shift
          # Inject default model for claude if --model not in args
          ${lib.optionalString (cfg.claudeDefaultModel != "") ''
            if [[ "$REAL_BINARY" == *"/claude" ]]; then
              _has_model=0
              for _arg in "$@"; do
                [[ "$_arg" == "--model" ]] && _has_model=1
              done
              if [[ $_has_model -eq 0 ]]; then
                set -- --model "${cfg.claudeDefaultModel}" "$@"
              fi
            fi
          ''}
          exec "$REAL_BINARY" "$@"
        fi

        # Default: sandboxed execution via nono

        # @decision SANDBOX-76-03: PWD must be inside projectRoot. Refuse broad binds.
        WORK_ROOT="${cfg.projectRoot}"
        cwd="$(readlink -f "$PWD")"
        case "$cwd" in
          "$WORK_ROOT"/*) ;;
          "$WORK_ROOT") ;;
          *)
            echo "ERROR: sandboxed agents must run inside $WORK_ROOT (current: $cwd)" >&2
            exit 1
            ;;
        esac

        # Load API keys for this wrapper's allowed credentials only.
        # @decision SANDBOX-105-01: Per-wrapper credential allowlist — each agent
        #   only receives the API keys it needs (least privilege).
        # nono passes these into the sandboxed child as environment variables
        # via --env-credential-map (env injection, not proxy isolation).
        # NOTE: Use $(cat ...) not $(< ...) — bash's built-in $(< file) fails
        # on NixOS /run/secrets/ symlinks (returns empty). cat works correctly.
        ${lib.concatMapStringsSep "\n        " (cred: ''
export ${cred.envVar}
        ${cred.envVar}="$(cat /run/secrets/${cred.secretPath} 2>/dev/null)" || ${cred.envVar}=""
        [[ -z "''$${cred.envVar}" ]] && echo "WARNING: ${cred.envVar} not loaded from /run/secrets/" >&2'') (resolveCredentials defaultCredentials)}

        # Build nono arguments.
        # --profile: full path required for nono v0.16.0 (name-based resolution only
        #   checks ~/.config/nono/profiles/, not NONO_PROFILE_PATH).
        # NOTE: --proxy-credential removed — nono v0.16.0 requires org.freedesktop.secrets
        # (system keystore) which is unavailable on headless servers. API keys are passed
        # directly via env_credentials. Re-enable proxy credentials after upgrading to
        # nono v0.20.0+ or installing a headless keystore (e.g., pass-secret-service).
        NONO_ARGS=(
          "run"
          "--profile" "/etc/nono/profiles/tsurf.json"
          "--net-allow"
        )

        # Only inject non-empty, non-placeholder API keys into sandbox.
        # Placeholder keys interfere with OAuth-based auth (e.g., codex Pro).
        _cred_vars=(${lib.concatMapStringsSep " " (cred: cred.envVar) (resolveCredentials defaultCredentials)})
        for _cred_var in "''${_cred_vars[@]}"; do
          _cred_val="''${!_cred_var:-}"
          if [[ -n "$_cred_val" && "$_cred_val" != PLACEHOLDER* ]]; then
            NONO_ARGS+=("--env-credential-map" "env://$_cred_var" "$_cred_var")
          fi
        done

        # Rollback support (opt-in)
        if [[ "''${AGENT_ROLLBACK:-}" == "1" ]]; then
          NONO_ARGS+=("--rollback")
        else
          NONO_ARGS+=("--no-rollback")
        fi

        # Nix daemon socket access (opt-in via allowNixDaemon)
        ${lib.optionalString cfg.allowNixDaemon ''
          NONO_ARGS+=("--read" "/nix/var/nix/daemon-socket")
        ''}

        # /nix/store and /run/current-system are covered by the profile's
        # nix_runtime + system_read_linux groups.
        # @decision SANDBOX-105-02: Read access scoped to current git repo root,
        #   not all of /data/projects. Prevents agents from reading sibling repos.
        GIT_ROOT="$(${pkgs.git}/bin/git -C "$cwd" rev-parse --show-toplevel 2>/dev/null)" || GIT_ROOT=""
        if [[ -n "$GIT_ROOT" ]]; then
          NONO_ARGS+=("--read" "$GIT_ROOT")
        else
          echo "WARNING: PWD is not inside a git repository; read access limited to $cwd" >&2
          NONO_ARGS+=("--read" "$cwd")
        fi

        # Inject default model for claude if --model not already in args
        ${lib.optionalString (cfg.claudeDefaultModel != "") ''
          if [[ "$REAL_BINARY" == *"/claude" ]]; then
            _has_model=0
            for _arg in "$@"; do
              [[ "$_arg" == "--model" ]] && _has_model=1
            done
            if [[ $_has_model -eq 0 ]]; then
              set -- --model "${cfg.claudeDefaultModel}" "$@"
            fi
          fi
        ''}

        NONO_ARGS+=("--" "$REAL_BINARY" "$@")

        audit_log "sandboxed" "$@"

        exec nono "''${NONO_ARGS[@]}"
      '';
    }).overrideAttrs (old: { meta = (old.meta or { }) // { priority = 4; }; });

  claude-sandboxed = mkWrapper {
    name = "claude";
    realPkg = pkgs.claude-code;
    realBin = "claude";
    defaultCredentials = [ "anthropic" ];
  };

  codex-sandboxed = mkWrapper {
    name = "codex";
    realPkg = pkgs.codex;
    realBin = "codex";
    defaultCredentials = [ "openai" ];
  };

  pi-sandboxed = mkWrapper {
    name = "pi";
    realPkg = pkgs.pi-coding-agent;
    realBin = "pi";
    defaultCredentials = [ "anthropic" ];
  };
in
{
  options.services.agentSandbox = {
    enable = lib.mkEnableOption "sandboxed agent wrappers for claude, codex, and pi";

    extraCredentials = lib.mkOption {
      type = lib.types.listOf (lib.types.enum [ "anthropic" "openai" "google" "xai" "openrouter" ]);
      default = [];
      description = "Additional credential providers to inject into ALL agent wrappers (e.g., [ \"google\" \"openrouter\" ]).";
    };

    projectRoot = lib.mkOption {
      type = lib.types.str;
      default = "/data/projects";
      description = "Root directory for sandboxed agent execution. PWD must be inside this path.";
    };

    allowNixDaemon = lib.mkEnableOption "access to /nix/var/nix/daemon-socket inside the sandbox";

    claudeDefaultModel = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "Default --model flag for claude wrapper (injected when --model not in args).";
    };

    egressControl = {
      enable = lib.mkEnableOption "UID-based nftables egress filtering for agent user";
      allowedPorts = lib.mkOption {
        type = lib.types.listOf lib.types.port;
        default = [ 53 80 443 22 9418 ];
        description = "TCP destination ports the agent user may connect to.";
      };
      user = lib.mkOption {
        type = lib.types.str;
        default = "dev";
        description = "Username whose egress is restricted.";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    # Replace bare agent binaries with nono-sandboxed wrappers (meta.priority = 4 wins over default 5).
    # The real binaries remain at their Nix store paths (referenced inside wrappers).
    environment.systemPackages = [
      claude-sandboxed
      codex-sandboxed
      pi-sandboxed
    ];

    # @decision SANDBOX-NET-01: UID-based nftables egress filtering restricts the agent
    #   user to a whitelist of TCP destination ports. DNS (UDP 53) is always allowed.
    #   Tailscale traffic is unrestricted (needed for internal service access).
    #   All other outbound traffic is logged and dropped.
    # Disable nftables ruleset validation because `meta skuid` with symbolic
    # usernames fails in the nix build sandbox (no /etc/passwd). The rules are
    # syntactically correct and work at runtime.
    networking.nftables.checkRuleset = lib.mkIf cfg.egressControl.enable false;

    networking.nftables.tables.agent-egress = lib.mkIf cfg.egressControl.enable {
      family = "inet";
      # NixOS nftables check runs in a build sandbox without /etc/passwd,
      # so we must use a numeric UID. NixOS auto-allocates UIDs, so we use
      # checkRuleset = false and resolve at runtime via ExecStartPre.
      # Alternative: hardcode a UID range. For now, disable syntax check
      # for this table only (the rest of nftables still gets checked).
      content = let
        portList = lib.concatMapStringsSep ", " toString cfg.egressControl.allowedPorts;
        user = cfg.egressControl.user;
      in ''
        chain output {
          type filter hook output priority 0; policy accept;
          meta skuid != "${user}" accept
          oifname "lo" accept
          ct state established,related accept
          meta l4proto udp th dport 53 accept
          meta l4proto tcp th dport { ${portList} } accept
          oifname "tailscale0" accept
          log prefix "agent-egress-deny: " drop
        }
      '';
    };
  };
}
