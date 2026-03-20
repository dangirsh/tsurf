# modules/dev-agent.nix
# Persistent autonomous Claude Code agent running in zmx session
# @decision DEV-AGENT-89: Systemd user service for dev user running claude in zmx
#   with nono sandbox (via agent-sandbox.nix wrapper). Auto-restart on failure.
# @decision DEV-AGENT-98: bypassPermissions is enabled only inside nono sandbox;
#   nono is the real permission boundary, so auto-approval in-sandbox is accepted risk (SEC98-01).
# @decision DEV-AGENT-106: Opt-in via services.devAgent.enable (default: false).
{ config, lib, pkgs, ... }:
let
  cfg = config.services.devAgent;
in
{
  options.services.devAgent.enable = lib.mkEnableOption
    "persistent autonomous Claude Code agent";

  config = lib.mkIf cfg.enable {
    systemd.services.dev-agent = {
      description = "Persistent autonomous Claude Code agent";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        # Type=oneshot + RemainAfterExit: zmx run launches the agent in a detached
        # session and exits immediately. The long-running process lives inside the
        # zmx session, not as a direct systemd child. RemainAfterExit keeps the
        # unit "active" so systemctl status reflects that the session was launched.
        Type = "oneshot";
        RemainAfterExit = true;
        User = "dev";
        WorkingDirectory = "/data/projects/tsurf";
        Restart = "on-failure";
        RestartSec = "30s";

        # NOTE: ProtectHome removed — claude needs write access to ~/.claude/ and
        # zmx session processes inherit the mount namespace.
        PrivateTmp = true;
        ProtectClock = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        LockPersonality = true;
        RestrictRealtime = true;
        NoNewPrivileges = true;

        # API key loading handled by agent-wrapper.sh (AGENT_CREDENTIALS),
        # not by parent env. No secrets needed in this unit's environment.
      };

      # zmx wraps claude (which is already sandboxed via agent-sandbox.nix)
      path = [ pkgs.coreutils pkgs.zmx ];
      script = builtins.readFile ../scripts/dev-agent.sh;
    };
  };
}
