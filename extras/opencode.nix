# extras/opencode.nix
# Optional: opencode AI coding assistant with nono sandbox.
# Uses a self-contained wrapper + launcher (no core extraAgents API dependency).
# Requires: services.agentSandbox.enable = true and services.nonoSandbox.enable = true.
#
# Usage: import this module, then set services.opencodeAgent.enable = true.
# Override the package via services.opencodeAgent.package if opencode is available
# in your nixpkgs (pkgs.opencode) or to pin a specific version.
#
# To find the correct hash for a new version:
#   nix store prefetch-file "https://github.com/sst/opencode/releases/download/vVERSION/opencode-linux-x64"
{ config, lib, pkgs, ... }:
let
  cfg = config.services.opencodeAgent;
  agentCfg = config.tsurf.agent;
  launcherName = "tsurf-launch-opencode";
  runtimePath = lib.makeBinPath [ pkgs.bash pkgs.coreutils pkgs.git pkgs.nono pkgs.python3 pkgs.util-linux ];

  defaultPackage = pkgs.stdenv.mkDerivation rec {
    pname = "opencode";
    version = "0.1.125"; # bump version + update hash together
    src = pkgs.fetchurl {
      url = "https://github.com/sst/opencode/releases/download/v${version}/opencode-linux-x64";
      # Replace with the actual hash:
      #   nix store prefetch-file "https://github.com/sst/opencode/releases/download/v${version}/opencode-linux-x64"
      hash = lib.fakeHash;
    };
    nativeBuildInputs = [ pkgs.autoPatchelfHook ];
    buildInputs = [ pkgs.stdenv.cc.cc.lib ];
    dontUnpack = true;
    installPhase = ''
      runHook preInstall
      install -m755 -D $src $out/bin/opencode
      runHook postInstall
    '';
    meta = with lib; {
      description = "AI coding assistant";
      homepage = "https://opencode.ai";
      platforms = [ "x86_64-linux" ];
    };
  };

  nonoProfile = pkgs.writeText "tsurf-opencode-profile.json" (builtins.toJSON {
    extends = "tsurf";
    meta = {
      name = "tsurf-opencode";
      version = "1.0.0";
      description = "tsurf opencode profile extension";
      author = "tsurf";
    };
    filesystem = { allow = [ "${agentCfg.home}/.config/opencode" ]; };
  });

  launcher = pkgs.writeShellApplication {
    name = launcherName;
    runtimeInputs = [ pkgs.systemd pkgs.coreutils ];
    text = ''
      export AGENT_NAME="opencode"
      export AGENT_REAL_BINARY="${cfg.package}/bin/opencode"
      export AGENT_PROJECT_ROOT="${agentCfg.projectRoot}"
      export AGENT_NONO_PROFILE="/etc/nono/profiles/tsurf-opencode.json"
      export AGENT_CREDENTIAL_PROXY="${../scripts/credential-proxy.py}"
      export AGENT_CREDENTIALS="${lib.concatStringsSep " " cfg.credentials}"

      exec systemd-run \
        --same-dir --collect --pipe \
        --unit="agent-opencode-$$" \
        --slice=tsurf-agents.slice \
        --setenv=PATH="${runtimePath}" \
        --setenv=AGENT_CHILD_PATH="${runtimePath}" \
        --setenv=AGENT_NAME="$AGENT_NAME" \
        --setenv=AGENT_REAL_BINARY="$AGENT_REAL_BINARY" \
        --setenv=AGENT_PROJECT_ROOT="$AGENT_PROJECT_ROOT" \
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
    name = "opencode";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      export AGENT_NAME="opencode"
      export AGENT_REAL_BINARY="${cfg.package}/bin/opencode"
      export AGENT_PROJECT_ROOT="${agentCfg.projectRoot}"
      export AGENT_NONO_PROFILE="/etc/nono/profiles/tsurf-opencode.json"
      export AGENT_CREDENTIAL_PROXY="${../scripts/credential-proxy.py}"
      export AGENT_CREDENTIALS="${lib.concatStringsSep " " cfg.credentials}"

      if [[ "$(id -u)" == "0" ]]; then
        exec ${launcher}/bin/${launcherName} "$@"
      fi

      exec /run/wrappers/bin/sudo ${launcher}/bin/${launcherName} "$@"
    '';
  }).overrideAttrs (old: {
    meta = (old.meta or { }) // { priority = 4; };
  });
in
{
  options.services.opencodeAgent = {
    enable = lib.mkEnableOption "opencode AI coding assistant with nono sandbox";

    package = lib.mkOption {
      type = lib.types.package;
      default = defaultPackage;
      description = ''
        opencode package to use. Override with pkgs.opencode if available in your nixpkgs,
        or provide a custom derivation pinned to a specific version.
      '';
    };

    credentials = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "anthropic:ANTHROPIC_API_KEY:anthropic-api-key" "openai:OPENAI_API_KEY:openai-api-key" ];
      description = ''
        Credential triples for the root-owned credential broker (SERVICE:ENV_VAR:secret-file-name).
        Only triples whose secrets exist in /run/secrets/ are activated at runtime.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = config.services.agentSandbox.enable;
        message = "extras/opencode.nix: services.agentSandbox.enable must be true";
      }
      {
        assertion = config.services.nonoSandbox.enable;
        message = "extras/opencode.nix: services.nonoSandbox.enable must be true";
      }
    ];

    environment.systemPackages = [ wrapper ];
    environment.etc."nono/profiles/tsurf-opencode.json".source = nonoProfile;

    security.sudo.extraRules = [{
      groups = [ "wheel" ];
      commands = [{
        command = "${launcher}/bin/${launcherName}";
        options = [ "NOPASSWD" ];
      }];
    }];
  };
}
