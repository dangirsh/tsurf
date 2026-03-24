# extras/dev-agent.nix
# Persistent autonomous Claude Code agent running in a supervised zmx session
# @decision SEC-115-04: dev-agent runs as the dedicated agent user, not operator.
# @decision SEC-145-03: dev-agent reaches Claude through the same brokered
#   immutable launcher path, so the agent principal never needs raw provider keys.
# @decision DEV-AGENT-89: Systemd supervises a zmx manager loop so session health
#   is visible in systemd and unattended agent workflows restart cleanly.
# @decision DEV-AGENT-98: bypassPermissions is enabled only inside nono sandbox;
#   nono is the real permission boundary, so auto-approval in-sandbox is accepted risk (SEC98-01).
# @decision DEV-AGENT-106: Opt-in via services.devAgent.enable (default: false).
{ config, lib, pkgs, ... }:
let
  cfg = config.services.devAgent;
  agentCfg = config.tsurf.agent;
  runtimePath = lib.makeBinPath [ pkgs.coreutils pkgs.git pkgs.gnugrep pkgs.zmx ];
  promptConfigured = cfg.prompt != null;
  commandConfigured = cfg.command != null;
  taskScript =
    if promptConfigured then
      pkgs.writeShellScript "tsurf-dev-agent-task" ''
        set -euo pipefail
        exec /run/current-system/sw/bin/claude \
        ${lib.optionalString (cfg.model != null) "  --model ${lib.escapeShellArg cfg.model} \\\n"}
        ${lib.optionalString (cfg.extraArgs != [ ]) "  ${lib.concatMapStringsSep " \\\n  " lib.escapeShellArg cfg.extraArgs} \\\n"}
          -p \
          --permission-mode=${lib.escapeShellArg cfg.permissionMode} \
          ${lib.escapeShellArg cfg.prompt}
      ''
    else if commandConfigured then
      pkgs.writeShellScript "tsurf-dev-agent-task" ''
        set -euo pipefail
        ${cfg.command}
      ''
    else
      pkgs.writeShellScript "tsurf-dev-agent-task" ''
        set -euo pipefail
        echo "services.devAgent requires exactly one of prompt or command" >&2
        exit 1
      '';
in
{
  options.services.devAgent = {
    enable = lib.mkEnableOption
      "persistent autonomous Claude Code agent";

    workingDirectory = lib.mkOption {
      type = lib.types.str;
      default = "${agentCfg.projectRoot}/dev-agent-workspace";
      description = ''
        Working directory for the dev-agent service. This should be a workspace repo path,
        not the control-plane repo. The default is a dedicated workspace under projectRoot.
      '';
    };

    sessionName = lib.mkOption {
      type = lib.types.str;
      default = "dev-agent";
      description = "zmx session name used for the supervised dev-agent process.";
    };

    pollIntervalSec = lib.mkOption {
      type = lib.types.ints.positive;
      default = 30;
      description = "Seconds between zmx session health polls in the manager loop.";
    };

    prompt = lib.mkOption {
      type = lib.types.nullOr lib.types.lines;
      default = null;
      description = ''
        Prompt passed to `claude -p` for the dev-agent session. Set exactly one of
        `services.devAgent.prompt` or `services.devAgent.command`.
      '';
    };

    command = lib.mkOption {
      type = lib.types.nullOr lib.types.lines;
      default = null;
      description = ''
        Shell command script run inside the supervised zmx session. Set exactly one of
        `services.devAgent.command` or `services.devAgent.prompt`.
      '';
    };

    model = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Optional Claude model passed to the prompt-based dev-agent task.";
    };

    permissionMode = lib.mkOption {
      type = lib.types.str;
      default = "bypassPermissions";
      description = ''
        Claude Code permission mode for prompt-based dev-agent runs. The default keeps
        unattended operation explicit while relying on the nono sandbox as the real boundary.
      '';
    };

    extraArgs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Additional CLI flags appended to prompt-based Claude invocations.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = config.services.agentSandbox.enable;
        message = "extras/dev-agent.nix: services.agentSandbox.enable must be true";
      }
      {
        assertion = config.services.nonoSandbox.enable;
        message = "extras/dev-agent.nix: services.nonoSandbox.enable must be true";
      }
      {
        assertion = config.services.agentCompute.enable;
        message = "extras/dev-agent.nix: services.agentCompute.enable must be true";
      }
      {
        assertion = promptConfigured != commandConfigured;
        message = "extras/dev-agent.nix: set exactly one of services.devAgent.prompt or services.devAgent.command";
      }
    ];

    systemd.tmpfiles.rules = [
      "d ${cfg.workingDirectory} 0700 ${agentCfg.user} ${agentCfg.user} -"
    ];

    systemd.services.dev-agent = {
      description = "Persistent autonomous Claude Code agent";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "simple";
        User = agentCfg.user;
        WorkingDirectory = cfg.workingDirectory;
        Restart = "on-failure";
        RestartSec = "30s";
        ExecStop = "-${pkgs.zmx}/bin/zmx kill ${lib.escapeShellArg cfg.sessionName}";

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
        Environment = [
          "PATH=/run/current-system/sw/bin:${runtimePath}"
          "DEV_AGENT_SESSION_NAME=${cfg.sessionName}"
          "DEV_AGENT_TASK_SCRIPT=${taskScript}"
          "DEV_AGENT_POLL_INTERVAL_SEC=${toString cfg.pollIntervalSec}"
        ];
      };

      script = builtins.readFile ./scripts/dev-agent.sh;
    };
  };
}
