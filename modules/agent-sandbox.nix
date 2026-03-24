# modules/agent-sandbox.nix
# @decision SANDBOX-73-01: Public core exposes one sandboxed Claude wrapper.
#   Additional wrappers and unattended workflows build on the same wrapper contract.
# @decision AUDIT-117-01: Launch logging uses journald only (logger -t agent-launch).
#   File-based audit logs remain removed.
# @decision NONO-145-02: The launcher path stays root-owned long enough to read
#   provider secrets and start the per-session loopback credential proxy.
# @decision SEC-119-01: Interactive Claude sessions stay brokered through
#   systemd-run; the actual agent binary drops to the dedicated agent user inside
#   the sandboxed command chain, not as the calling operator.
# @decision SEC-135-01: The sudo boundary exposes one immutable Claude launcher.
# @decision SEC-145-03: systemd-run properties enforce NoNewPrivileges, drop all
#   capabilities, set rlimits, seccomp syscall blocklist, and 4h runtime timeout.
#   Sourced from ecosystem review of nsjail, ai-jail, and clampdown patterns.
# @decision SEC-145-04: Claude-level deny rules provide defense-in-depth for
#   sensitive paths atop Landlock enforcement. enableAllProjectMcpServers=false
#   prevents malicious repos from injecting MCP servers.
{ config, lib, pkgs, ... }:
let
  cfg = config.services.agentSandbox;
  agentCfg = config.tsurf.agent;
  agentRuntimePath = lib.makeBinPath [
    pkgs.bash
    pkgs.coreutils
    pkgs.git
    pkgs.nono
    pkgs.python3
    pkgs.util-linux
  ];
  protectedRepoMarkers = lib.concatStringsSep ":" cfg.protectedRepoMarkers;
  protectedRepoRoots = lib.concatStringsSep ":" cfg.protectedRepoRoots;

  launcherName = "tsurf-launch-claude";
  launcher = pkgs.writeShellApplication {
    name = launcherName;
    runtimeInputs = [ pkgs.systemd pkgs.coreutils ];
    text = ''
      export AGENT_NAME="claude"
      export AGENT_REAL_BINARY="${pkgs.claude-code}/bin/claude"
      export AGENT_PROJECT_ROOT="${cfg.projectRoot}"
      export AGENT_PROTECTED_REPO_MARKERS="${protectedRepoMarkers}"
      export AGENT_PROTECTED_REPO_ROOTS="${protectedRepoRoots}"
      export AGENT_NONO_PROFILE="/etc/nono/profiles/tsurf.json"
      export AGENT_CREDENTIAL_PROXY="${../scripts/credential-proxy.py}"
      export AGENT_CREDENTIALS="anthropic:ANTHROPIC_API_KEY:anthropic-api-key"

      if [[ -t 0 && -t 1 ]]; then
        stdio_flag="--pty"
      else
        stdio_flag="--pipe"
      fi

      exec systemd-run \
        "$stdio_flag" --same-dir --collect \
        --unit="agent-claude-$$" \
        --slice=tsurf-agents.slice \
        --property=MemoryMax=4G \
        --property=CPUQuota=200% \
        --property=TasksMax=256 \
        --property=NoNewPrivileges=true \
        --property=CapabilityBoundingSet= \
        --property=OOMScoreAdjust=500 \
        --property=LimitNOFILE=512 \
        --property=LimitFSIZE=2G \
        --property=LimitAS=8G \
        --property=LimitCORE=0 \
        --property=RuntimeMaxSec=14400 \
        "--property=SystemCallFilter=~@mount @clock @cpu-emulation @debug @obsolete @raw-io @reboot @swap kexec_load kexec_file_load open_by_handle_at io_uring_setup io_uring_enter io_uring_register bpf" \
        --setenv=PATH="${agentRuntimePath}" \
        --setenv=AGENT_CHILD_PATH="${agentRuntimePath}" \
        --setenv=AGENT_NAME="$AGENT_NAME" \
        --setenv=AGENT_REAL_BINARY="$AGENT_REAL_BINARY" \
        --setenv=AGENT_PROJECT_ROOT="$AGENT_PROJECT_ROOT" \
        --setenv=AGENT_PROTECTED_REPO_MARKERS="$AGENT_PROTECTED_REPO_MARKERS" \
        --setenv=AGENT_PROTECTED_REPO_ROOTS="$AGENT_PROTECTED_REPO_ROOTS" \
        --setenv=AGENT_NONO_PROFILE="$AGENT_NONO_PROFILE" \
        --setenv=AGENT_CREDENTIAL_PROXY="$AGENT_CREDENTIAL_PROXY" \
        --setenv=AGENT_CREDENTIALS="$AGENT_CREDENTIALS" \
        --setenv=AGENT_RUN_AS_USER="${agentCfg.user}" \
        --setenv=AGENT_RUN_AS_UID="${toString agentCfg.uid}" \
        --setenv=AGENT_RUN_AS_GID="${toString agentCfg.gid}" \
        --setenv=AGENT_RUN_AS_HOME="${agentCfg.home}" \
        ${pkgs.bash}/bin/bash ${../scripts/agent-wrapper.sh} "$@"
    '';
  };

  wrapper = (pkgs.writeShellApplication {
    name = "claude";
    runtimeInputs = [ pkgs.nono pkgs.git pkgs.coreutils pkgs.util-linux ];
    text = ''
      export AGENT_NAME="claude"
      export AGENT_REAL_BINARY="${pkgs.claude-code}/bin/claude"
      export AGENT_PROJECT_ROOT="${cfg.projectRoot}"
      export AGENT_PROTECTED_REPO_MARKERS="${protectedRepoMarkers}"
      export AGENT_PROTECTED_REPO_ROOTS="${protectedRepoRoots}"
      export AGENT_NONO_PROFILE="/etc/nono/profiles/tsurf.json"
      export AGENT_CREDENTIAL_PROXY="${../scripts/credential-proxy.py}"
      export AGENT_CREDENTIALS="anthropic:ANTHROPIC_API_KEY:anthropic-api-key"

      if [[ "$(id -u)" == "0" ]]; then
        exec ${launcher}/bin/${launcherName} "$@"
      fi

      exec /run/wrappers/bin/sudo ${launcher}/bin/${launcherName} "$@"
    '';
  }).overrideAttrs (old: { meta = (old.meta or {}) // { priority = 4; }; });
in
{
  options.services.agentSandbox = {
    enable = lib.mkEnableOption "sandboxed Claude wrapper for the dedicated agent user";

    projectRoot = lib.mkOption {
      type = lib.types.str;
      default = config.tsurf.agent.projectRoot;
      description = "Root directory for sandboxed agent execution. PWD must be inside this path.";
    };

    protectedRepoMarkers = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ".tsurf-control-plane" ];
      description = ''
        Repo-root marker files that identify protected control-plane repositories.
        The wrapper refuses to launch agents from any git repo containing one of these markers.
      '';
    };

    protectedRepoRoots = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = ''
        Absolute git repo roots that sandboxed agents must never run from.
        Use this in private overlays for infra repos that cannot carry marker files.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    # Managed Claude settings: defense-in-depth deny rules atop Landlock enforcement.
    # Written to the agent user's settings path so Claude Code loads them automatically.
    environment.etc."claude-agent-settings.json".text = builtins.toJSON {
      permissions = {
        deny = [
          "Read(/run/secrets/**)"
          "Read(${agentCfg.home}/.ssh/**)"
          "Read(/etc/nono/**)"
          "Read(.env)"
          "Read(.envrc)"
          "Edit(.git/hooks/**)"
          "Edit(.envrc)"
          "Edit(.env)"
          "Edit(.mcp.json)"
          "Edit(.devcontainer/**)"
        ];
      };
      enableAllProjectMcpServers = false;
    };

    environment.systemPackages = [ wrapper ];

    security.sudo.extraRules = [
      {
        groups = [ "wheel" ];
        commands = [{
          command = "${launcher}/bin/${launcherName}";
          options = [ "NOPASSWD" ];
        }];
      }
      {
        users = [ agentCfg.user ];
        commands = [{
          command = "${launcher}/bin/${launcherName}";
          options = [ "NOPASSWD" ];
        }];
      }
    ];

    environment.persistence."/persist".directories =
      map (path: "${agentCfg.home}/${path}") [
        ".claude"
        ".config/claude"
        ".config/git"
        ".local/share/direnv"
      ];

    environment.persistence."/persist".files =
      map (path: "${agentCfg.home}/${path}") [
        ".gitconfig"
        ".bash_history"
      ];
  };
}
