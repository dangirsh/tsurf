# modules/agent-launcher.nix
# Generic sandboxed agent launcher infrastructure.
# @decision LAUNCHER-152-01: Generic agent launcher - each agent produces a wrapper,
#   systemd-run launcher, nono profile, and sudo rule.
# @decision LAUNCHER-152-02: Agents must not deploy changes to their own security boundaries.
# @decision SEC-159-01: Legacy nono credential mode brokers raw keys through nono's
#   built-in reverse proxy (--credential + custom_credentials with env:// URIs).
# @decision SEC-IRON-01: Iron credential mode gives children provider-shaped proxy
#   tokens while raw provider keys stay in the Iron proxy service environment.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.agentLauncher;
  agentCfg = config.tsurf.agent;
  egressCfg = config.tsurf.agentEgress;

  agentRuntimePath = lib.makeBinPath [
    pkgs.bash
    pkgs.coreutils
    pkgs.git
    pkgs.nono
    pkgs.util-linux
  ];

  # Well-known credential service defaults. Maps service name to upstream/header/format
  # and the conventional env var + sops secret name.
  credentialServiceDefaults = {
    anthropic = {
      upstream = "https://api.anthropic.com";
      injectHeader = "x-api-key";
      credentialFormat = "{}";
      envVar = "ANTHROPIC_API_KEY";
      secretName = "anthropic-api-key";
    };
    openai = {
      upstream = "https://api.openai.com";
      injectHeader = "authorization";
      credentialFormat = "Bearer {}";
      envVar = "OPENAI_API_KEY";
      secretName = "openai-api-key";
    };
    openrouter = {
      upstream = "https://openrouter.ai/api/v1";
      injectHeader = "authorization";
      credentialFormat = "Bearer {}";
      envVar = "OPENROUTER_API_KEY";
      secretName = "openrouter-api-key";
    };
    xai = {
      upstream = "https://api.x.ai";
      injectHeader = "authorization";
      credentialFormat = "Bearer {}";
      envVar = "XAI_API_KEY";
      secretName = "xai-api-key";
    };
  };

  credentialDefaultsFor =
    agentDef: svc:
    credentialServiceDefaults.${svc}
    // lib.filterAttrs (_: value: value != null) (agentDef.credentialOverrides.${svc} or { });

  ironProxyTokenFor =
    svc: defaults: "tsurf-iron-${svc}-${defaults.envVar}-${defaults.secretName}-proxy-token";

  # Build launcher + wrapper for a single agent definition
  mkAgentPair =
    name: agentDef:
    let
      launcherName = "tsurf-launch-${name}";
      credentialServicesStr = lib.concatStringsSep " " agentDef.credentialServices;
      effectiveCredentialProxy =
        if agentDef.credentialProxy == null then cfg.defaultCredentialProxy else agentDef.credentialProxy;

      # Build nono custom_credentials for env:// URI-based credential proxy
      credentialDefs = lib.listToAttrs (
        map (
          svc:
          let
            defaults = credentialDefaultsFor agentDef svc;
          in
          lib.nameValuePair svc {
            upstream = defaults.upstream;
            credential_key = "env://${defaults.envVar}";
            env_var = defaults.envVar;
            inject_mode = "header";
            inject_header = defaults.injectHeader;
            credential_format = defaults.credentialFormat;
          }
        ) agentDef.credentialServices
      );

      # Build secret-loading instructions: "envVar:secretName" pairs
      credentialSecrets = lib.concatStringsSep " " (
        map (
          svc:
          let
            defaults = credentialDefaultsFor agentDef svc;
          in
          "${defaults.envVar}:${defaults.secretName}"
        ) agentDef.credentialServices
      );
      ironCredentialTokens = lib.concatStringsSep " " (
        map (
          svc:
          let
            defaults = credentialDefaultsFor agentDef svc;
          in
          "${defaults.envVar}:${ironProxyTokenFor svc defaults}"
        ) agentDef.credentialServices
      );

      # Merge the base tsurf profile into each generated profile. NixOS-installed
      # profiles must be self-contained instead of relying on registry lookup.
      nonoProfileName = "tsurf-${name}";
      hasCredentials = agentDef.credentialServices != [ ];
      useNonoCredentials = hasCredentials && effectiveCredentialProxy == "nono";
      useIronEgress = cfg.egressProxy.url != "";
      baseNonoProfile = builtins.fromJSON config.environment.etc."nono/profiles/tsurf.json".text;
      baseFilesystem = baseNonoProfile.filesystem or { };
      baseNetwork = baseNonoProfile.network or { };
      nonoProfile = builtins.toJSON (
        baseNonoProfile
        // {
          meta = {
            inherit name;
            version = "1.0.0";
            description = "tsurf ${name} sandbox profile";
            author = "tsurf";
          };
          filesystem = baseFilesystem // {
            allow = lib.unique ((baseFilesystem.allow or [ ]) ++ agentDef.nonoProfile.extraAllow);
            allow_file = lib.unique ((baseFilesystem.allow_file or [ ]) ++ agentDef.nonoProfile.extraAllowFile);
            deny = lib.unique ((baseFilesystem.deny or [ ]) ++ agentDef.nonoProfile.extraDeny);
          };
          network =
            baseNetwork
            // lib.optionalAttrs useNonoCredentials {
              credentials = agentDef.credentialServices;
              custom_credentials = credentialDefs;
            }
            // lib.optionalAttrs useIronEgress {
              # Iron mediates the only allowed egress path at host level. nono
              # still provides filesystem/process isolation, but must not block
              # loopback proxy connections from the child.
              block = false;
            };
        }
      );

      nonoProfilePath = "/etc/nono/profiles/${nonoProfileName}.json";

      defaultArgStr = lib.concatMapStringsSep " " lib.escapeShellArg agentDef.defaultArgs;
      extraReadPathsFile = pkgs.writeText "${name}-agent-extra-read-paths" (
        lib.concatStringsSep "\n" cfg.extraReadPaths
      );
      extraAllowPathsFile = pkgs.writeText "${name}-agent-extra-allow-paths" (
        lib.concatStringsSep "\n" cfg.extraAllowPaths
      );
      childEnvironmentFile = pkgs.writeText "${name}-agent-child-environment" (
        lib.concatStringsSep "\n" (
          lib.mapAttrsToList (envName: value: "${envName}=${value}") agentDef.childEnvironment
        )
      );

      launcher = pkgs.writeShellApplication {
        name = launcherName;
        runtimeInputs = [
          pkgs.systemd
          pkgs.coreutils
        ];
        text = ''
          export AGENT_NAME="${name}"
          export AGENT_REAL_BINARY="${agentDef.package}/bin/${agentDef.command}"
          export AGENT_PROJECT_ROOT="${cfg.projectRoot}"
          export AGENT_NONO_PROFILE="${nonoProfilePath}"
          export AGENT_CREDENTIAL_SERVICES="${credentialServicesStr}"
          export AGENT_CREDENTIAL_SECRETS="${credentialSecrets}"
          export AGENT_CREDENTIAL_PROXY="${effectiveCredentialProxy}"
          export AGENT_IRON_CREDENTIAL_TOKENS="${ironCredentialTokens}"
          export AGENT_EGRESS_PROXY_URL="${cfg.egressProxy.url}"
          export AGENT_EGRESS_PROXY_CA_CERT="${cfg.egressProxy.caCert}"
          export AGENT_EGRESS_PROXY_NO_PROXY="${cfg.egressProxy.noProxy}"
          export AGENT_SCOPE_ACCESS="${cfg.scopeAccess}"
          export AGENT_EXTRA_READ_PATHS_FILE="${extraReadPathsFile}"
          export AGENT_EXTRA_ALLOW_PATHS_FILE="${extraAllowPathsFile}"
          export AGENT_CHILD_ENVIRONMENT_FILE="${childEnvironmentFile}"
          export AGENT_NONO_PROXY_PORT_START="${toString egressCfg.nonoProxyTCPPortRange.from}"
          export AGENT_NONO_PROXY_PORT_END="${toString egressCfg.nonoProxyTCPPortRange.to}"

          if [[ -t 0 && -t 1 ]]; then
            stdio_flag="--pty"
          else
            stdio_flag="--pipe"
          fi

          # Per-invocation resource limits. These are tighter than the parent
          # tsurf-agents.slice (MemoryMax=8G, CPUQuota=300%, TasksMax=1024 in
          # agent-compute.nix) so each agent session is individually bounded while
          # the slice caps the aggregate across all concurrent sessions.
          exec systemd-run \
            "$stdio_flag" --same-dir --collect \
            --unit="agent-${name}-$$" \
            --slice=tsurf-agents.slice \
            --property=MemoryMax=4G \
            --property=CPUQuota=200% \
            --property=TasksMax=256 \
            --property=NoNewPrivileges=true \
            "--property=CapabilityBoundingSet=CAP_SETUID CAP_SETGID" \
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
            --setenv=AGENT_CREDENTIAL_SERVICES="$AGENT_CREDENTIAL_SERVICES" \
            --setenv=AGENT_CREDENTIAL_SECRETS="$AGENT_CREDENTIAL_SECRETS" \
            --setenv=AGENT_CREDENTIAL_PROXY="$AGENT_CREDENTIAL_PROXY" \
            --setenv=AGENT_IRON_CREDENTIAL_TOKENS="$AGENT_IRON_CREDENTIAL_TOKENS" \
            --setenv=AGENT_EGRESS_PROXY_URL="$AGENT_EGRESS_PROXY_URL" \
            --setenv=AGENT_EGRESS_PROXY_CA_CERT="$AGENT_EGRESS_PROXY_CA_CERT" \
            --setenv=AGENT_EGRESS_PROXY_NO_PROXY="$AGENT_EGRESS_PROXY_NO_PROXY" \
            --setenv=AGENT_SCOPE_ACCESS="$AGENT_SCOPE_ACCESS" \
            --setenv=AGENT_EXTRA_READ_PATHS_FILE="$AGENT_EXTRA_READ_PATHS_FILE" \
            --setenv=AGENT_EXTRA_ALLOW_PATHS_FILE="$AGENT_EXTRA_ALLOW_PATHS_FILE" \
            --setenv=AGENT_CHILD_ENVIRONMENT_FILE="$AGENT_CHILD_ENVIRONMENT_FILE" \
            --setenv=AGENT_NONO_PROXY_PORT_START="$AGENT_NONO_PROXY_PORT_START" \
            --setenv=AGENT_NONO_PROXY_PORT_END="$AGENT_NONO_PROXY_PORT_END" \
            --setenv=AGENT_RUN_AS_USER="${agentCfg.user}" \
            --setenv=AGENT_RUN_AS_UID="${toString agentCfg.uid}" \
            --setenv=AGENT_RUN_AS_GID="${toString agentCfg.gid}" \
            --setenv=AGENT_RUN_AS_HOME="${agentCfg.home}" \
            ${pkgs.bash}/bin/bash ${../scripts/agent-wrapper.sh} ${defaultArgStr} "$@"
        '';
      };

      wrapperName = agentDef.wrapperName;
      wrapper =
        (pkgs.writeShellApplication {
          name = wrapperName;
          runtimeInputs = [
            pkgs.nono
            pkgs.git
            pkgs.coreutils
            pkgs.util-linux
          ];
          text = ''
            if [[ "$(id -u)" == "0" ]]; then
              exec ${launcher}/bin/${launcherName} "$@"
            fi

            exec /run/wrappers/bin/sudo ${launcher}/bin/${launcherName} "$@"
          '';
        }).overrideAttrs
          (old: {
            meta = (old.meta or { }) // {
              priority = 4;
            };
          });

    in
    {
      inherit
        launcher
        launcherName
        wrapper
        wrapperName
        nonoProfile
        nonoProfilePath
        ;
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
      type = lib.types.attrsOf (
        lib.types.submodule {
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
                    default = [ ];
                    description = "Additional filesystem.allow directory paths for this agent's nono profile.";
                  };
                  extraAllowFile = lib.mkOption {
                    type = lib.types.listOf lib.types.str;
                    default = [ ];
                    description = "Additional filesystem.allow_file paths for this agent's nono profile.";
                  };
                  extraDeny = lib.mkOption {
                    type = lib.types.listOf lib.types.str;
                    default = [ ];
                    description = "Additional filesystem.deny paths for this agent's nono profile.";
                  };
                };
              };
              default = { };
              description = "Per-agent nono profile overrides (merged on top of the base tsurf profile).";
            };

            credentialServices = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [ ];
              description = ''
                Credential service names for nono's built-in reverse proxy (e.g., "anthropic", "openai").
                Each service maps to a well-known upstream, inject header, env var, and sops secret.
                Credentials are brokered through nono's phantom token proxy; the child never sees real keys.
              '';
            };

            credentialProxy = lib.mkOption {
              type = lib.types.nullOr (
                lib.types.enum [
                  "nono"
                  "iron"
                ]
              );
              default = null;
              description = ''
                Credential proxy implementation for this agent. null uses
                services.agentLauncher.defaultCredentialProxy.
              '';
            };

            credentialOverrides = lib.mkOption {
              type = lib.types.attrsOf (
                lib.types.submodule {
                  options = {
                    upstream = lib.mkOption {
                      type = lib.types.nullOr lib.types.str;
                      default = null;
                      description = "Override the upstream base URL for this credential service.";
                    };
                    injectHeader = lib.mkOption {
                      type = lib.types.nullOr lib.types.str;
                      default = null;
                      description = "Override the HTTP header used for credential injection.";
                    };
                    credentialFormat = lib.mkOption {
                      type = lib.types.nullOr lib.types.str;
                      default = null;
                      description = "Override the nono credential_format template.";
                    };
                    envVar = lib.mkOption {
                      type = lib.types.nullOr lib.types.str;
                      default = null;
                      description = "Override the root-side environment variable used by env://.";
                    };
                    secretName = lib.mkOption {
                      type = lib.types.nullOr lib.types.str;
                      default = null;
                      description = "Override the /run/secrets file name loaded for this credential service.";
                    };
                  };
                }
              );
              default = { };
              description = "Small per-agent overrides for well-known credential service defaults.";
            };

            defaultArgs = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [ ];
              description = "Default CLI arguments prepended to every invocation.";
            };

            managedSettings = lib.mkOption {
              type = lib.types.nullOr lib.types.attrs;
              default = null;
              description = "Optional managed settings JSON written to /etc/<name>-agent-settings.json.";
            };

            childEnvironment = lib.mkOption {
              type = lib.types.attrsOf lib.types.str;
              default = { };
              description = ''
                Non-secret environment variables injected into the final agent child
                after privilege drop. Values are written into the Nix store; do not
                use this for credentials.
              '';
            };

            persistence = lib.mkOption {
              type = lib.types.submodule {
                options = {
                  directories = lib.mkOption {
                    type = lib.types.listOf lib.types.str;
                    default = [ ];
                    description = "Relative paths under agent home to persist (directories).";
                  };
                  files = lib.mkOption {
                    type = lib.types.listOf lib.types.str;
                    default = [ ];
                    description = "Relative paths under agent home to persist (files).";
                  };
                };
              };
              default = { };
              description = "Agent-specific persistence paths under the agent home directory.";
            };

            egress = lib.mkOption {
              type = lib.types.submodule {
                options = {
                  allowedHosts = lib.mkOption {
                    type = lib.types.listOf lib.types.str;
                    default = [ ];
                    description = "Additional host globs allowed through the agent egress proxy.";
                  };
                  allowedCIDRs = lib.mkOption {
                    type = lib.types.listOf lib.types.str;
                    default = [ ];
                    description = "Additional CIDRs allowed through the agent egress proxy.";
                  };
                };
              };
              default = { };
              description = "Per-agent egress policy consumed by the Iron egress proxy.";
            };
          };
        }
      );
      default = { };
      description = "Per-agent sandbox definitions. Each produces a wrapper, launcher, nono profile, and sudo rule.";
    };

    defaultCredentialProxy = lib.mkOption {
      type = lib.types.enum [
        "nono"
        "iron"
      ];
      default = "nono";
      description = "Default credential proxy used by generated agents unless overridden per agent.";
    };

    egressProxy = {
      url = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "Loopback URL for the agent egress proxy. Empty disables proxy env injection.";
      };

      caCert = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "CA certificate path trusted by agent child processes for MITM proxying.";
      };

      noProxy = lib.mkOption {
        type = lib.types.str;
        default = "127.0.0.1,localhost";
        description = "NO_PROXY value injected into agent child processes when egressProxy.url is set.";
      };
    };

    scopeAccess = lib.mkOption {
      type = lib.types.enum [
        "read"
        "allow"
      ];
      default = "read";
      description = ''
        How the wrapper grants nono access to the current top-level workspace.
        "read" is the public default; private overlays may use "allow" when agents
        are expected to edit the whole current workspace from subdirectories.
      '';
    };

    extraReadPaths = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Additional paths passed to nono with --read for every generated launcher.";
    };

    extraAllowPaths = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Additional paths passed to nono with --allow for every generated launcher.";
    };

    sudoUsers = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ agentCfg.user ];
      description = "Users allowed to invoke generated immutable launchers through sudo.";
    };

    sudoGroups = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Groups allowed to invoke generated immutable launchers through sudo.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = config.tsurf.agentEgress.enable or false;
        message = "services.agentLauncher requires modules/networking.nix so the dedicated agent UID has host-level egress filtering.";
      }
    ]
    ++ lib.concatLists (
      lib.mapAttrsToList (
        name: agentDef:
        map (svc: {
          assertion = builtins.hasAttr svc credentialServiceDefaults;
          message = "services.agentLauncher.agents.${name}.credentialServices contains unsupported credential service '${svc}'.";
        }) agentDef.credentialServices
      ) cfg.agents
    )
    ++ lib.mapAttrsToList (
      name: agentDef:
      let
        effectiveCredentialProxy =
          if agentDef.credentialProxy == null then cfg.defaultCredentialProxy else agentDef.credentialProxy;
      in
      {
        assertion = effectiveCredentialProxy != "iron" || cfg.egressProxy.url != "";
        message = "services.agentLauncher.agents.${name} uses credentialProxy=iron but services.agentLauncher.egressProxy.url is empty.";
      }
    ) cfg.agents;

    environment.systemPackages = lib.mapAttrsToList (_: pair: pair.wrapper) agentPairs;

    # Install per-agent nono profiles and managed settings files
    environment.etc = lib.mkMerge (
      (lib.mapAttrsToList (name: pair: {
        "nono/profiles/tsurf-${name}.json".text = pair.nonoProfile;
      }) agentPairs)
      ++ (lib.mapAttrsToList (
        name: agentDef:
        lib.optionalAttrs (agentDef.managedSettings != null) {
          "${name}-agent-settings.json".text = builtins.toJSON agentDef.managedSettings;
        }
      ) cfg.agents)
    );

    # Sudo rules: allow configured callers to invoke each immutable launcher.
    security.sudo.extraRules =
      lib.mapAttrsToList (_: pair: {
        users = cfg.sudoUsers;
        commands = [
          {
            command = "${pair.launcher}/bin/${pair.launcherName}";
            options = [ "NOPASSWD" ];
          }
        ];
      }) agentPairs
      ++ lib.optionals (cfg.sudoGroups != [ ]) (
        lib.mapAttrsToList (_: pair: {
          groups = cfg.sudoGroups;
          commands = [
            {
              command = "${pair.launcher}/bin/${pair.launcherName}";
              options = [ "NOPASSWD" ];
            }
          ];
        }) agentPairs
      );

    # Per-agent persistence
    environment.persistence."/persist".directories = lib.unique (
      lib.concatLists (
        lib.mapAttrsToList (
          _: agentDef: map (path: "${agentCfg.home}/${path}") agentDef.persistence.directories
        ) cfg.agents
      )
    );

    environment.persistence."/persist".files = lib.unique (
      lib.concatLists (
        lib.mapAttrsToList (
          _: agentDef: map (path: "${agentCfg.home}/${path}") agentDef.persistence.files
        ) cfg.agents
      )
    );
  };
}
