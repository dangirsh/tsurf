# modules/agent-launcher.nix
# Generic sandboxed agent launcher infrastructure.
# @decision LAUNCHER-152-01: Generic agent launcher — each agent produces a wrapper,
#   systemd-run launcher, nono profile, and sudo rule. Raw keys never reach the agent.
# @decision LAUNCHER-152-02: Agents must not deploy changes to their own security boundaries.
{ config, lib, pkgs, ... }:
let
  cfg = config.services.agentLauncher;
  agentCfg = config.tsurf.agent;

  agentRuntimePath = lib.makeBinPath [
    pkgs.bash
    pkgs.coreutils
    pkgs.git
    pkgs.nono
    pkgs.python3
    pkgs.util-linux
  ];

  # Build launcher + wrapper for a single agent definition
  mkAgentPair = name: agentDef:
    let
      launcherName = "tsurf-launch-${name}";
      credentialString = lib.concatStringsSep " " agentDef.credentials;

      # Merge nono profile: extend base tsurf profile with agent-specific overrides
      nonoProfileName = "tsurf-${name}";
      nonoProfile = pkgs.writeText "${nonoProfileName}-profile.json" (builtins.toJSON ({
        extends = "tsurf";
        meta = {
          inherit name;
          version = "1.0.0";
          description = "tsurf ${name} sandbox profile";
          author = "tsurf";
        };
      } // lib.optionalAttrs (agentDef.nonoProfile.extraAllow != [] || agentDef.nonoProfile.extraAllowFile != []) {
        filesystem = {}
          // lib.optionalAttrs (agentDef.nonoProfile.extraAllow != []) {
            allow = agentDef.nonoProfile.extraAllow;
          }
          // lib.optionalAttrs (agentDef.nonoProfile.extraAllowFile != []) {
            allow_file = agentDef.nonoProfile.extraAllowFile;
          };
      }));

      nonoProfilePath = "/etc/nono/profiles/${nonoProfileName}.json";

      defaultArgStr = lib.concatMapStringsSep " " lib.escapeShellArg agentDef.defaultArgs;

      launcher = pkgs.writeShellApplication {
        name = launcherName;
        runtimeInputs = [ pkgs.systemd pkgs.coreutils ];
        text = ''
          export AGENT_NAME="${name}"
          export AGENT_REAL_BINARY="${agentDef.package}/bin/${agentDef.command}"
          export AGENT_PROJECT_ROOT="${cfg.projectRoot}"
          export AGENT_NONO_PROFILE="${nonoProfilePath}"
          export AGENT_CREDENTIAL_PROXY="${../scripts/credential-proxy.py}"
          export AGENT_CREDENTIALS="${credentialString}"

          if [[ -t 0 && -t 1 ]]; then
            stdio_flag="--pty"
          else
            stdio_flag="--pipe"
          fi

          exec systemd-run \
            "$stdio_flag" --same-dir --collect \
            --unit="agent-${name}-$$" \
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
            --setenv=AGENT_NONO_PROFILE="$AGENT_NONO_PROFILE" \
            --setenv=AGENT_CREDENTIAL_PROXY="$AGENT_CREDENTIAL_PROXY" \
            --setenv=AGENT_CREDENTIALS="$AGENT_CREDENTIALS" \
            --setenv=AGENT_RUN_AS_USER="${agentCfg.user}" \
            --setenv=AGENT_RUN_AS_UID="${toString agentCfg.uid}" \
            --setenv=AGENT_RUN_AS_GID="${toString agentCfg.gid}" \
            --setenv=AGENT_RUN_AS_HOME="${agentCfg.home}" \
            ${pkgs.bash}/bin/bash ${../scripts/agent-wrapper.sh} ${defaultArgStr} "$@"
        '';
      };

      wrapperName = agentDef.wrapperName;
      wrapper = (pkgs.writeShellApplication {
        name = wrapperName;
        runtimeInputs = [ pkgs.nono pkgs.git pkgs.coreutils pkgs.util-linux ];
        text = ''
          if [[ "$(id -u)" == "0" ]]; then
            exec ${launcher}/bin/${launcherName} "$@"
          fi

          exec /run/wrappers/bin/sudo ${launcher}/bin/${launcherName} "$@"
        '';
      }).overrideAttrs (old: { meta = (old.meta or {}) // { priority = 4; }; });

    in {
      inherit launcher launcherName wrapper wrapperName nonoProfile nonoProfilePath;
    };

  # Build all agent pairs
  agentPairs = lib.mapAttrs mkAgentPair cfg.agents;

in
{
  options.services.agentLauncher = {
    enable = lib.mkEnableOption "generic sandboxed agent launcher infrastructure";

    projectRoot = lib.mkOption {
      type = lib.types.str;
      default = config.tsurf.agent.projectRoot;
      description = "Root directory for sandboxed agent execution. PWD must be inside this path.";
    };

    agents = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule {
        options = {
          command = lib.mkOption {
            type = lib.types.str;
            description = "Binary name inside the package (e.g., 'claude' for pkgs.claude-code).";
          };

          package = lib.mkOption {
            type = lib.types.package;
            description = "Package providing the agent binary.";
          };

          wrapperName = lib.mkOption {
            type = lib.types.str;
            description = "Name of the wrapper script installed in PATH.";
          };

          nonoProfile = lib.mkOption {
            type = lib.types.submodule {
              options = {
                extraAllow = lib.mkOption {
                  type = lib.types.listOf lib.types.str;
                  default = [];
                  description = "Additional filesystem.allow directory paths for this agent's nono profile.";
                };
                extraAllowFile = lib.mkOption {
                  type = lib.types.listOf lib.types.str;
                  default = [];
                  description = "Additional filesystem.allow_file paths for this agent's nono profile.";
                };
                extraDeny = lib.mkOption {
                  type = lib.types.listOf lib.types.str;
                  default = [];
                  description = "Additional filesystem.deny paths for this agent's nono profile.";
                };
              };
            };
            default = {};
            description = "Per-agent nono profile overrides (merged on top of the base tsurf profile).";
          };

          credentials = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [];
            description = ''
              Credential triples for the root-owned credential broker (SERVICE:ENV_VAR:secret-file-name).
              Only triples whose secrets exist in /run/secrets/ are activated at runtime.
            '';
          };

          defaultArgs = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [];
            description = "Default CLI arguments prepended to every invocation.";
          };

          managedSettings = lib.mkOption {
            type = lib.types.nullOr lib.types.attrs;
            default = null;
            description = "Optional managed settings JSON written to /etc/<name>-agent-settings.json.";
          };

          persistence = lib.mkOption {
            type = lib.types.submodule {
              options = {
                directories = lib.mkOption {
                  type = lib.types.listOf lib.types.str;
                  default = [];
                  description = "Relative paths under agent home to persist (directories).";
                };
                files = lib.mkOption {
                  type = lib.types.listOf lib.types.str;
                  default = [];
                  description = "Relative paths under agent home to persist (files).";
                };
              };
            };
            default = {};
            description = "Agent-specific persistence paths under the agent home directory.";
          };
        };
      });
      default = {};
      description = "Per-agent sandbox definitions. Each produces a wrapper, launcher, nono profile, and sudo rule.";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = lib.mapAttrsToList (_: pair: pair.wrapper) agentPairs;

    # Install per-agent nono profiles and managed settings files
    environment.etc = lib.mkMerge (
      (lib.mapAttrsToList (name: pair: {
        "nono/profiles/tsurf-${name}.json".source = pair.nonoProfile;
      }) agentPairs)
      ++ (lib.mapAttrsToList (name: agentDef:
        lib.optionalAttrs (agentDef.managedSettings != null) {
          "${name}-agent-settings.json".text = builtins.toJSON agentDef.managedSettings;
        }
      ) cfg.agents)
    );

    # Sudo rules: allow agent user to invoke each immutable launcher
    security.sudo.extraRules = lib.mapAttrsToList (_: pair: {
      users = [ agentCfg.user ];
      commands = [{
        command = "${pair.launcher}/bin/${pair.launcherName}";
        options = [ "NOPASSWD" ];
      }];
    }) agentPairs;

    # Per-agent persistence
    environment.persistence."/persist".directories = lib.concatLists (
      lib.mapAttrsToList (_: agentDef:
        map (path: "${agentCfg.home}/${path}") agentDef.persistence.directories
      ) cfg.agents
    );

    environment.persistence."/persist".files = lib.concatLists (
      lib.mapAttrsToList (_: agentDef:
        map (path: "${agentCfg.home}/${path}") agentDef.persistence.files
      ) cfg.agents
    );
  };
}
