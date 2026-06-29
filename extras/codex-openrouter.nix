# extras/codex-openrouter.nix
# Optional: OpenRouter-backed Codex CLI sandboxed through nono's credential proxy.
# Requires: services.agentLauncher.enable = true and services.nonoSandbox.enable = true.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.codexOpenRouterAgent;
  launcherCfg = config.services.agentLauncher;
  agentCfg = config.tsurf.agent;

  agentRuntimePath = lib.makeBinPath [
    pkgs.bash
    pkgs.coreutils
    pkgs.git
    pkgs.nono
    pkgs.util-linux
  ];

  profileName = "tsurf-${cfg.wrapperName}";
  profilePath = "/etc/nono/profiles/${profileName}.json";
  launcherName = "tsurf-launch-${cfg.wrapperName}";
  codexHome = "${agentCfg.home}/.codex-openrouter";

  baseNonoProfile = builtins.fromJSON config.environment.etc."nono/profiles/tsurf.json".text;
  baseFilesystem = baseNonoProfile.filesystem or { };
  baseNetwork = baseNonoProfile.network or { };
  nonoProfile = builtins.toJSON (
    baseNonoProfile
    // {
      meta = {
        name = cfg.wrapperName;
        version = "1.0.0";
        description = "tsurf ${cfg.wrapperName} OpenRouter-backed Codex sandbox profile";
        author = "tsurf";
      };
      filesystem = baseFilesystem // {
        allow = lib.unique ((baseFilesystem.allow or [ ]) ++ [ codexHome ]);
        allow_file = lib.unique (
          (baseFilesystem.allow_file or [ ])
          ++ [
            "/proc/sys/kernel/overflowuid"
            "/proc/sys/kernel/overflowgid"
          ]
        );
      };
      network = baseNetwork // {
        credentials = [ "openrouter" ];
        custom_credentials.openrouter = {
          upstream = cfg.baseUrl;
          credential_key = "env://OPENROUTER_API_KEY";
          env_var = "OPENROUTER_API_KEY";
          inject_mode = "header";
          inject_header = "authorization";
          credential_format = "Bearer {}";
        };
      };
    }
  );

  extraReadPathsStr = lib.concatMapStringsSep " " lib.escapeShellArg launcherCfg.extraReadPaths;
  extraAllowPathsStr = lib.concatMapStringsSep " " lib.escapeShellArg launcherCfg.extraAllowPaths;

  runtime = pkgs.writeShellApplication {
    name = "${cfg.wrapperName}-runtime";
    runtimeInputs = [
      pkgs.bash
      pkgs.coreutils
      pkgs.git
      pkgs.nono
      pkgs.util-linux
    ];
    text = ''
      : "''${AGENT_NAME:?must be set}"
      : "''${AGENT_REAL_BINARY:?must be set}"
      : "''${AGENT_PROJECT_ROOT:?must be set}"
      : "''${AGENT_NONO_PROFILE:?must be set}"
      : "''${AGENT_RUN_AS_USER:?must be set}"
      : "''${AGENT_RUN_AS_UID:?must be set}"
      : "''${AGENT_RUN_AS_GID:?must be set}"
      : "''${AGENT_RUN_AS_HOME:?must be set}"
      : "''${AGENT_CHILD_PATH:?must be set}"
      : "''${CODEX_OPENROUTER_MODEL:?must be set}"
      : "''${CODEX_OPENROUTER_PROVIDER_ID:?must be set}"
      : "''${CODEX_OPENROUTER_PROVIDER_NAME:?must be set}"
      : "''${CODEX_OPENROUTER_SECRET_NAME:?must be set}"

      export HOME="$AGENT_RUN_AS_HOME"
      export USER="$AGENT_RUN_AS_USER"
      export LOGNAME="$AGENT_RUN_AS_USER"

      case "$AGENT_REAL_BINARY" in
        /nix/store/*) ;;
        *)
          echo "ERROR: AGENT_REAL_BINARY must be in /nix/store" >&2
          exit 1
          ;;
      esac

      project_root="$(readlink -f "$AGENT_PROJECT_ROOT")"
      cwd="$(readlink -f "$PWD")"
      case "$cwd" in
        "$project_root"/*|"$project_root") ;;
        *)
          echo "ERROR: $AGENT_NAME must run inside $project_root (current: $cwd)" >&2
          exit 1
          ;;
      esac
      if [[ "$cwd" == "$project_root" ]]; then
        echo "ERROR: refusing to grant access to the entire project root ($project_root)" >&2
        exit 1
      fi

      workspace_rel="''${cwd#"$project_root"/}"
      workspace_name="''${workspace_rel%%/*}"
      workspace_root="$project_root/$workspace_name"
      if [[ ! -d "$workspace_root" ]]; then
        echo "ERROR: could not resolve top-level workspace beneath $project_root (current: $cwd)" >&2
        exit 1
      fi

      secret_file="/run/secrets/$CODEX_OPENROUTER_SECRET_NAME"
      if [[ ! -f "$secret_file" ]]; then
        echo "ERROR: missing OpenRouter API key secret: $secret_file" >&2
        exit 1
      fi
      secret_value="$(cat "$secret_file")"
      if [[ -z "$secret_value" || "$secret_value" == PLACEHOLDER* ]]; then
        echo "ERROR: OpenRouter API key secret is empty or placeholder" >&2
        exit 1
      fi
      export OPENROUTER_API_KEY="$secret_value"

      codex_home="${codexHome}"
      if [[ ! -d "$codex_home" ]]; then
        echo "ERROR: missing OpenRouter Codex state directory: $codex_home" >&2
        exit 1
      fi

      case "''${AGENT_SCOPE_ACCESS:-read}" in
        read)
          nono_args=(run --profile "$AGENT_NONO_PROFILE" --no-rollback --credential openrouter --read "$workspace_root")
          ;;
        allow)
          nono_args=(run --profile "$AGENT_NONO_PROFILE" --no-rollback --credential openrouter --allow "$workspace_root")
          ;;
        *)
          echo "ERROR: AGENT_SCOPE_ACCESS must be 'read' or 'allow'" >&2
          exit 1
          ;;
      esac

      IFS=' ' read -ra extra_read_paths <<< "''${AGENT_EXTRA_READ_PATHS:-}"
      for path in "''${extra_read_paths[@]}"; do
        [[ -n "$path" ]] || continue
        nono_args+=(--read "$path")
      done

      IFS=' ' read -ra extra_allow_paths <<< "''${AGENT_EXTRA_ALLOW_PATHS:-}"
      for path in "''${extra_allow_paths[@]}"; do
        [[ -n "$path" ]] || continue
        nono_args+=(--allow "$path")
      done

      # shellcheck disable=SC2016
      child_script='
        child_path="$1"
        real_binary="$2"
        model="$3"
        provider_id="$4"
        provider_name="$5"
        run_uid="$6"
        run_gid="$7"
        run_user="$8"
        run_home="$9"
        codex_home="''${10}"
        shift 10

        : "''${NONO_PROXY_TOKEN:?missing nono proxy token}"
        : "''${OPENROUTER_BASE_URL:?missing OpenRouter proxy base URL}"

        exec setpriv \
          --reuid "$run_uid" \
          --regid "$run_gid" \
          --init-groups \
          env -i \
            HOME="$run_home" \
            USER="$run_user" \
            LOGNAME="$run_user" \
            CODEX_HOME="$codex_home" \
            PATH="$child_path" \
            NONO_PROXY_TOKEN="$NONO_PROXY_TOKEN" \
            OPENROUTER_BASE_URL="$OPENROUTER_BASE_URL" \
            "$real_binary" \
              -m "$model" \
              -c "model_provider=\"$provider_id\"" \
              -c "model_providers.$provider_id.name=\"$provider_name\"" \
              -c "model_providers.$provider_id.base_url=\"$OPENROUTER_BASE_URL\"" \
              -c "model_providers.$provider_id.wire_api=\"responses\"" \
              -c "model_providers.$provider_id.env_key=\"NONO_PROXY_TOKEN\"" \
              "$@"
      '

      logger -t "agent-launch" --id=$$ \
        "mode=sandboxed agent=$AGENT_NAME user=$(whoami) uid=$(id -u) repo_scope=top-level-workspace" \
        2>/dev/null || true

      nono_args+=(
        -- ${pkgs.bash}/bin/bash -c "$child_script" bash
        "$AGENT_CHILD_PATH"
        "$AGENT_REAL_BINARY"
        "$CODEX_OPENROUTER_MODEL"
        "$CODEX_OPENROUTER_PROVIDER_ID"
        "$CODEX_OPENROUTER_PROVIDER_NAME"
        "$AGENT_RUN_AS_UID"
        "$AGENT_RUN_AS_GID"
        "$AGENT_RUN_AS_USER"
        "$AGENT_RUN_AS_HOME"
        "$codex_home"
        "$@"
      )

      exec nono "''${nono_args[@]}"
    '';
  };

  launcher = pkgs.writeShellApplication {
    name = launcherName;
    runtimeInputs = [
      pkgs.coreutils
      pkgs.systemd
    ];
    text = ''
      export AGENT_NAME="${cfg.wrapperName}"
      export AGENT_REAL_BINARY="${cfg.package}/bin/codex"
      export AGENT_PROJECT_ROOT="${launcherCfg.projectRoot}"
      export AGENT_NONO_PROFILE="${profilePath}"
      export AGENT_SCOPE_ACCESS="${launcherCfg.scopeAccess}"
      export AGENT_EXTRA_READ_PATHS="${extraReadPathsStr}"
      export AGENT_EXTRA_ALLOW_PATHS="${extraAllowPathsStr}"
      export CODEX_OPENROUTER_MODEL="${cfg.model}"
      export CODEX_OPENROUTER_PROVIDER_ID="${cfg.providerId}"
      export CODEX_OPENROUTER_PROVIDER_NAME="${cfg.providerName}"
      export CODEX_OPENROUTER_SECRET_NAME="${cfg.secretName}"

      if [[ -t 0 && -t 1 ]]; then
        stdio_flag="--pty"
      else
        stdio_flag="--pipe"
      fi

      exec systemd-run \
        "$stdio_flag" --same-dir --collect \
        --unit="agent-${cfg.wrapperName}-$$" \
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
        --setenv=AGENT_SCOPE_ACCESS="$AGENT_SCOPE_ACCESS" \
        --setenv=AGENT_EXTRA_READ_PATHS="$AGENT_EXTRA_READ_PATHS" \
        --setenv=AGENT_EXTRA_ALLOW_PATHS="$AGENT_EXTRA_ALLOW_PATHS" \
        --setenv=AGENT_RUN_AS_USER="${agentCfg.user}" \
        --setenv=AGENT_RUN_AS_UID="${toString agentCfg.uid}" \
        --setenv=AGENT_RUN_AS_GID="${toString agentCfg.gid}" \
        --setenv=AGENT_RUN_AS_HOME="${agentCfg.home}" \
        --setenv=CODEX_OPENROUTER_MODEL="$CODEX_OPENROUTER_MODEL" \
        --setenv=CODEX_OPENROUTER_PROVIDER_ID="$CODEX_OPENROUTER_PROVIDER_ID" \
        --setenv=CODEX_OPENROUTER_PROVIDER_NAME="$CODEX_OPENROUTER_PROVIDER_NAME" \
        --setenv=CODEX_OPENROUTER_SECRET_NAME="$CODEX_OPENROUTER_SECRET_NAME" \
        ${runtime}/bin/${cfg.wrapperName}-runtime "$@"
    '';
  };

  wrapper =
    (pkgs.writeShellApplication {
      name = cfg.wrapperName;
      runtimeInputs = [
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
  options.services.codexOpenRouterAgent = {
    enable = lib.mkEnableOption "OpenRouter-backed Codex CLI with nono sandbox";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.codex;
      description = "Codex package to expose through the OpenRouter-backed sandboxed wrapper.";
    };

    wrapperName = lib.mkOption {
      type = lib.types.strMatching "[A-Za-z0-9._-]+";
      default = "codex-openrouter";
      description = "Name of the OpenRouter-backed Codex wrapper installed in PATH.";
    };

    model = lib.mkOption {
      type = lib.types.str;
      default = "z-ai/glm-5.2";
      description = "Default OpenRouter model for unattended Codex subagents.";
    };

    providerId = lib.mkOption {
      type = lib.types.strMatching "[A-Za-z_][A-Za-z0-9_]*";
      default = "openrouter";
      description = "Codex model provider id used in per-invocation config.";
    };

    providerName = lib.mkOption {
      type = lib.types.str;
      default = "OpenRouter";
      description = "Human-readable Codex provider name.";
    };

    baseUrl = lib.mkOption {
      type = lib.types.str;
      default = "https://openrouter.ai/api/v1";
      description = "OpenRouter OpenAI-compatible upstream base URL used by the nono credential proxy.";
    };

    secretName = lib.mkOption {
      type = lib.types.str;
      default = "openrouter-api-key";
      description = "sops secret name containing the OpenRouter API key.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = config.services.agentLauncher.enable;
        message = "extras/codex-openrouter.nix: services.agentLauncher.enable must be true";
      }
      {
        assertion = config.services.nonoSandbox.enable;
        message = "extras/codex-openrouter.nix: services.nonoSandbox.enable must be true";
      }
      {
        assertion = builtins.hasAttr cfg.secretName config.sops.secrets;
        message = "extras/codex-openrouter.nix: sops.secrets.${cfg.secretName} must be declared";
      }
    ];

    environment.systemPackages = [ wrapper ];
    environment.etc."nono/profiles/${profileName}.json".text = nonoProfile;
    systemd.tmpfiles.rules = [ "d ${codexHome} 0700 ${agentCfg.user} ${agentCfg.user} -" ];

    security.sudo.extraRules = [
      {
        users = launcherCfg.sudoUsers;
        commands = [
          {
            command = "${launcher}/bin/${launcherName}";
            options = [ "NOPASSWD" ];
          }
        ];
      }
    ]
    ++ lib.optionals (launcherCfg.sudoGroups != [ ]) [
      {
        groups = launcherCfg.sudoGroups;
        commands = [
          {
            command = "${launcher}/bin/${launcherName}";
            options = [ "NOPASSWD" ];
          }
        ];
      }
    ];
  };
}
