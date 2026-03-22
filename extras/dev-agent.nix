# extras/dev-agent.nix
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
  options.services.devAgent = {
    enable = lib.mkEnableOption
      "persistent autonomous Claude Code agent";

    workingDirectory = lib.mkOption {
      type = lib.types.str;
      default = agentCfg.projectRoot;
      description = ''
        Working directory for the dev-agent service. Should be a workspace repo path,
        NOT the control-plane repo (tsurf). Default is the agent project root.
        Private overlay should set this to a specific workspace repo.
      '';
    };
  };

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
        # @decision SEC-124-03: Default to project root, not control-plane repo.
        #   Private overlay should set services.devAgent.workingDirectory to a
        #   specific workspace repo path. See SECURITY.md "Control-Plane Separation".
        # NOTE: Type=oneshot + RemainAfterExit does not supervise the zmx session.
        #   The long-running process lives inside zmx, not as a direct systemd child.
        #   systemctl status shows "active" (RemainAfterExit), but zmx session health
        #   is not monitored. Accept this limitation for template simplicity.
        WorkingDirectory = cfg.workingDirectory;
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
        SystemCallArchitectures = "native";
        LockPersonality = true;
        RestrictRealtime = true;
        RestrictSUIDSGID = true;
        RestrictNamespaces = true;
        NoNewPrivileges = true;
        CapabilityBoundingSet = "";
        # NOTE: ProtectHome, ProtectSystem=strict, PrivateDevices omitted — agent needs home
        #   dir write, project dir write, and PTY access for zmx sessions.
        # @decision SEC-125-02: MemoryDenyWriteExecute omitted intentionally.
        #   Node.js V8 JIT requires W+X memory pages.

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
      script = builtins.readFile ./scripts/dev-agent.sh;
    };
  };
}
