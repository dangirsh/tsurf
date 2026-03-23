# extras/codex.nix
# Optional: Codex CLI sandboxed through a self-contained wrapper + launcher.
# Requires: services.agentSandbox.enable = true and services.nonoSandbox.enable = true.
{ config, lib, pkgs, ... }:
let
  cfg = config.services.codexAgent;
  agentCfg = config.tsurf.agent;
  agentHome = config.tsurf.agent.home;
  devHome = config.users.users.dev.home;
  launcherName = "tsurf-launch-codex";
  runtimePath = lib.makeBinPath [ pkgs.bash pkgs.coreutils pkgs.git pkgs.nono pkgs.util-linux ];

  nonoProfile = pkgs.writeText "tsurf-codex-profile.json" (builtins.toJSON {
    extends = "tsurf";
    meta = {
      name = "tsurf-codex";
      version = "1.0.0";
      description = "tsurf codex profile extension";
      author = "tsurf";
    };
    filesystem = { allow = [ "${agentHome}/.codex" ]; };
  });

  launcher = pkgs.writeShellApplication {
    name = launcherName;
    runtimeInputs = [ pkgs.systemd pkgs.coreutils ];
    text = ''
      export AGENT_NAME="codex"
      export AGENT_REAL_BINARY="${cfg.package}/bin/codex"
      export AGENT_PROJECT_ROOT="${agentCfg.projectRoot}"
      export AGENT_NONO_PROFILE="/etc/nono/profiles/tsurf-codex.json"
      export AGENT_CREDENTIALS="${lib.concatStringsSep " " cfg.credentials}"

      exec systemd-run \
        --uid="${agentCfg.user}" --gid="${toString agentCfg.gid}" \
        --same-dir --collect --pipe \
        --unit="agent-codex-$$" \
        --slice=tsurf-agents.slice \
        --setenv=PATH="${runtimePath}" \
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
    name = "codex";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      export AGENT_NAME="codex"
      export AGENT_REAL_BINARY="${cfg.package}/bin/codex"
      export AGENT_PROJECT_ROOT="${agentCfg.projectRoot}"
      export AGENT_NONO_PROFILE="/etc/nono/profiles/tsurf-codex.json"
      export AGENT_CREDENTIALS="${lib.concatStringsSep " " cfg.credentials}"

      if [[ "$(id -un)" == "${agentCfg.user}" ]]; then
        exec ${pkgs.bash}/bin/bash ${../scripts/agent-wrapper.sh} "$@"
      fi

      exec /run/wrappers/bin/sudo ${launcher}/bin/${launcherName} "$@"
    '';
  }).overrideAttrs (old: {
    meta = (old.meta or { }) // { priority = 4; };
  });
in
{
  options.services.codexAgent = {
    enable = lib.mkEnableOption "Codex CLI with nono sandbox";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.codex;
      description = "Codex package to expose through the sandboxed wrapper.";
    };

    credentials = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "openai:OPENAI_API_KEY:openai-api-key" ];
      description = ''
        Credential triples for nono proxy injection (SERVICE:ENV_VAR:secret-file-name).
        Only triples whose secrets exist in /run/secrets/ are activated at runtime.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = config.services.agentSandbox.enable;
        message = "extras/codex.nix: services.agentSandbox.enable must be true";
      }
      {
        assertion = config.services.nonoSandbox.enable;
        message = "extras/codex.nix: services.nonoSandbox.enable must be true";
      }
    ];

    environment.systemPackages = [ wrapper ];
    environment.etc."nono/profiles/tsurf-codex.json".source = nonoProfile;

    security.sudo.extraRules = [{
      groups = [ "wheel" ];
      commands = [{
        command = "${launcher}/bin/${launcherName}";
        options = [ "NOPASSWD" ];
      }];
    }];

    environment.persistence."/persist".directories = [
      "${devHome}/.codex"
      "${agentHome}/.codex"
    ];
  };
}
