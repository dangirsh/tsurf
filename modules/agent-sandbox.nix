# modules/agent-sandbox.nix
# @decision SANDBOX-73-01: Public core exposes one sandboxed Claude wrapper.
#   Extra agents and unattended workflows belong in optional modules or a private overlay.
# @decision AUDIT-117-01: Launch logging uses journald only (logger -t agent-launch).
#   File-based audit logs remain removed.
# @decision NONO-118-02: API keys are loaded into the parent env from /run/secrets/.
#   nono reads them via env:// URIs and injects phantom tokens into the child.
# @decision SEC-119-01: Interactive Claude sessions run as the dedicated agent user via
#   systemd-run, not as the calling operator.
# @decision SEC-135-01: The sudo boundary exposes one immutable Claude launcher.
{ config, lib, pkgs, ... }:
let
  cfg = config.services.agentSandbox;
  agentCfg = config.tsurf.agent;
  agentRuntimePath = lib.makeBinPath [ pkgs.bash pkgs.coreutils pkgs.git pkgs.nono pkgs.util-linux ];

  launcherName = "tsurf-launch-claude";
  launcher = pkgs.writeShellApplication {
    name = launcherName;
    runtimeInputs = [ pkgs.systemd pkgs.coreutils ];
    text = ''
      export AGENT_NAME="claude"
      export AGENT_REAL_BINARY="${pkgs.claude-code}/bin/claude"
      export AGENT_PROJECT_ROOT="${cfg.projectRoot}"
      export AGENT_NONO_PROFILE="/etc/nono/profiles/tsurf.json"
      export AGENT_CREDENTIALS="anthropic:ANTHROPIC_API_KEY:anthropic-api-key"

      if [[ -t 0 && -t 1 ]]; then
        stdio_flag="--pty"
      else
        stdio_flag="--pipe"
      fi

      exec systemd-run \
        --uid="${agentCfg.user}" --gid="${toString agentCfg.gid}" \
        "$stdio_flag" --same-dir --collect \
        --unit="agent-claude-$$" \
        --slice=tsurf-agents.slice \
        --property=MemoryMax=4G \
        --property=CPUQuota=200% \
        --property=TasksMax=256 \
        --setenv=PATH="${agentRuntimePath}" \
        --setenv=HOME="${agentCfg.home}" \
        --setenv=AGENT_NAME="$AGENT_NAME" \
        --setenv=AGENT_REAL_BINARY="$AGENT_REAL_BINARY" \
        --setenv=AGENT_PROJECT_ROOT="$AGENT_PROJECT_ROOT" \
        --setenv=AGENT_NONO_PROFILE="$AGENT_NONO_PROFILE" \
        --setenv=AGENT_CREDENTIALS="$AGENT_CREDENTIALS" \
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
      export AGENT_NONO_PROFILE="/etc/nono/profiles/tsurf.json"
      export AGENT_CREDENTIALS="anthropic:ANTHROPIC_API_KEY:anthropic-api-key"

      if [[ "$(id -un)" == "${agentCfg.user}" ]]; then
        exec bash ${../scripts/agent-wrapper.sh} "$@"
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
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ wrapper ];

    security.sudo.extraRules = [{
      groups = [ "wheel" ];
      commands = [{
        command = "${launcher}/bin/${launcherName}";
        options = [ "NOPASSWD" ];
      }];
    }];

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
