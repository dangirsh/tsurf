# modules/dev-agent.nix
# Persistent autonomous Claude Code agent running in zmx session
# @decision SEC-115-04: dev-agent runs as agent user, not operator.
# @decision DEV-AGENT-89: Systemd service running claude in zmx
#   with nono sandbox (via agent-sandbox.nix wrapper). Auto-restart on failure.
# @decision DEV-AGENT-98: bypassPermissions is enabled only inside nono sandbox;
#   nono is the real permission boundary, so auto-approval in-sandbox is accepted risk (SEC98-01).
# @decision DEV-AGENT-106: Opt-in via services.devAgent.enable (default: false).
{ config, lib, pkgs, ... }:
let
  cfg = config.services.devAgent;
  agentCfg = config.tsurf.agent;
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
        User = agentCfg.user;
        # Template default: tsurf repo. Production should use a workspace repo path
        # (not the control-plane repo) — see SECURITY.md control-plane separation.
        WorkingDirectory = "${agentCfg.projectRoot}/tsurf";
        Restart = "on-failure";
        RestartSec = "30s";

        # NOTE: ProtectHome removed — claude needs write access to ~/.claude/ and
        # zmx session processes inherit the mount namespace.
        PrivateTmp = true;
        ProtectClock = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectKernelLogs = true;
        ProtectControlGroups = true;
        LockPersonality = true;
        RestrictRealtime = true;
        RestrictSUIDSGID = true;
        NoNewPrivileges = true;
        # NOTE: ProtectHome, ProtectSystem=strict, PrivateDevices omitted — agent needs home
        #   dir write, project dir write, and PTY access for zmx sessions.

        # @decision SEC-116-03: Per-unit resource limits within the agent slice.
        #   Prevents a single agent from consuming the entire slice budget.
        Slice = "tsurf-agents.slice";
        MemoryMax = "4G";
        CPUQuota = "200%";
        TasksMax = 256;
        OOMPolicy = "kill";

        # API key loading handled by agent-wrapper.sh (AGENT_CREDENTIALS),
        # not by parent env. No secrets needed in this unit's environment.
      };

      # zmx wraps claude (which is already sandboxed via agent-sandbox.nix)
      path = [ pkgs.coreutils pkgs.zmx ];
      script = builtins.readFile ../scripts/dev-agent.sh;
    };
  };
}
