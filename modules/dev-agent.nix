# modules/dev-agent.nix
# Persistent autonomous Claude Code agent running in zmx session
# @decision DEV-AGENT-89: Systemd user service for dev user running claude in zmx
#   with nono sandbox (via agent-sandbox.nix wrapper). Auto-restart on failure.
# @decision DEV-AGENT-98: bypassPermissions is enabled only inside nono sandbox;
#   nono is the real permission boundary, so auto-approval in-sandbox is accepted risk (SEC98-01).
# @decision DEV-AGENT-106: Opt-in via services.devAgent.enable (default: false).
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.devAgent;
in
{
  options.services.devAgent.enable = lib.mkEnableOption
    "persistent autonomous Claude Code agent";

  config = lib.mkIf cfg.enable {
    # NOTE: %U in system-level units resolves to the *managing* user (root/0),
    # NOT the User= directive. UID must be resolved at runtime via `id -u`
    # since NixOS auto-allocates UIDs (config.users.users.*.uid may be null).

    # System service running as primary agent user (private overlay may override user)
    # On template: runs as "dev" (private overlay may override user)
    systemd.services.dev-agent = {
      description = "Persistent autonomous Claude Code agent";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        User = "dev"; # Private overlay may override user for other hosts
        WorkingDirectory = "/data/projects/tsurf";
        Restart = "on-failure";
        RestartSec = "30s";

        # Systemd hardening
        # NOTE: ProtectHome removed -- claude needs write access to ~/.claude/ and
        # zmx session processes inherit the mount namespace. ReadWritePaths cannot
        # adequately override ProtectHome=read-only for all paths claude needs.
        PrivateTmp = true;
        ProtectClock = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        LockPersonality = true;
        RestrictRealtime = true;
        NoNewPrivileges = true;

        # Environment -- XDG_RUNTIME_DIR set in script via `id -u` (not %U, which resolves to root in system units)
        Environment = [
          "ANTHROPIC_API_KEY_FILE=/run/secrets/anthropic-api-key"
        ];
      };

      # zmx wraps claude (which is already sandboxed via agent-sandbox.nix)
      # The wrapper loads ANTHROPIC_API_KEY from /run/secrets/ before exec
      path = [
        pkgs.coreutils
        pkgs.zmx
      ];
      script = ''
        set -euo pipefail

        # Set XDG_RUNTIME_DIR from actual UID (systemd %U resolves to root in system units)
        export XDG_RUNTIME_DIR="/run/user/$(id -u)"

        # Load API key from secrets (nono will read this from parent env)
        if [ -f "$ANTHROPIC_API_KEY_FILE" ]; then
          export ANTHROPIC_API_KEY=$(cat "$ANTHROPIC_API_KEY_FILE")
        else
          echo "WARNING: ANTHROPIC_API_KEY not loaded from $ANTHROPIC_API_KEY_FILE" >&2
        fi

        # Launch claude in zmx session with research task
        # claude wrapper from sandbox.nix is in PATH (sandboxed via nono)
        # -p for non-interactive mode (prompt as arg, not stdin), --permission-mode=bypassPermissions for yolo mode
        exec ${pkgs.zmx}/bin/zmx run dev-agent claude -p --permission-mode=bypassPermissions "Conduct a literature search for projects similar to tsurf - NixOS configurations combined with AI agent infrastructure. Focus on projects with commits in the last few weeks (check GitHub). Document findings in /data/projects/tsurf/RESEARCH.md with: project name, repo URL, last commit date, key features, relevance score (1-10), and adoption recommendations. Use WebSearch and WebFetch tools."
      '';
    };
  };
}
