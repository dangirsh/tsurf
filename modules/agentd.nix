# modules/agentd.nix
# @decision AGENTD-40-01: agentd manages lifecycle; custom harness executes a generated `agent` wrapper.
# @decision AGENTD-40-02: bwrap wrapper preserves the existing agent-spawn sandbox policy and keeps secrets env-only.
{ config, lib, pkgs, ... }:
let
  zmx = pkgs.callPackage ../packages/zmx.nix { };

  sandbox-docker-compat = pkgs.runCommandNoCC "sandbox-docker-compat" { } ''
    mkdir -p "$out/bin"
    ln -s ${pkgs.podman}/bin/podman "$out/bin/docker"
  '';

  mkDuplicateProxyPortAssertion = enabledAgents:
    let
      proxyPorts =
        map (agentCfg: agentCfg.apiProxyPort)
          (lib.attrValues enabledAgents);
      nonNullProxyPorts = lib.filter (port: port != null) proxyPorts;
    in
    {
      assertion = (lib.length nonNullProxyPorts) == (lib.length (lib.unique nonNullProxyPorts));
      message = "services.agentd.agents.*.apiProxyPort must be unique across enabled agents.";
    };

  mkCustomHarnessAssertion = agents: {
    assertion =
      lib.all
        (agentCfg: !(agentCfg.enable && agentCfg.harness == "custom" && (!agentCfg.sandbox) && agentCfg.command == null))
        (lib.attrValues agents);
    message = "services.agentd.agents.<name>.command is required when harness=custom and sandbox=false.";
  };

  mkAgentWrapper = name: agentCfg:
    let
      runtimeCommand = if agentCfg.command != null then agentCfg.command else agentCfg.agentBinary;
      homeDir = "/home/${agentCfg.user}";
    in
    pkgs.writeShellScriptBin "agent" ''
      set -euo pipefail

      NAME=${lib.escapeShellArg name}
      PROJECT_DIR=${lib.escapeShellArg agentCfg.workdir}
      USER_NAME=${lib.escapeShellArg agentCfg.user}
      HOME_DIR=${lib.escapeShellArg homeDir}
      RUNTIME_UID="$(id -u)"
      RUNTIME_GID="$(id -g)"
      RUNTIME_DIR="/run/user/$RUNTIME_UID"
      TERM_VALUE="''${TERM:-xterm-256color}"

      AUDIT_DIR="/data/projects/.agent-audit"
      mkdir -p "$AUDIT_DIR" || true
      printf "%s SPAWN agentd=%s project=%s sandbox=%s\n" \
        "$(date -Iseconds)" "$NAME" "$PROJECT_DIR" "${if agentCfg.sandbox then "on" else "off"}" >> "$AUDIT_DIR/spawn.log" || true
      printf "AGENTD_SPAWN name=%s project=%s sandbox=%s" \
        "$NAME" "$PROJECT_DIR" "${if agentCfg.sandbox then "on" else "off"}" | systemd-cat -t agentd-spawn -p info || true

      if [ "${if agentCfg.sandbox then "1" else "0"}" != "1" ]; then
        exec ${lib.escapeShellArg runtimeCommand} "$@"
      fi

      BWRAP_ARGS=(
        --unshare-user --uid "$RUNTIME_UID" --gid "$RUNTIME_GID"
        --unshare-ipc
        --unshare-uts
        --unshare-pid
        --unshare-cgroup
        --disable-userns
        --hostname "sandbox-$NAME"
        --die-with-parent
        --new-session

        --ro-bind /nix/store /nix/store
        --bind /nix/var/nix/daemon-socket /nix/var/nix/daemon-socket
        --ro-bind /nix/var/nix/db /nix/var/nix/db
        --ro-bind /nix/var/nix/gcroots /nix/var/nix/gcroots

        --ro-bind /run/current-system /run/current-system
        --ro-bind-try /etc/profiles/per-user/$USER_NAME /etc/profiles/per-user/$USER_NAME
        --ro-bind-try $HOME_DIR/.nix-profile $HOME_DIR/.nix-profile

        --ro-bind /etc/resolv.conf /etc/resolv.conf
        --ro-bind /etc/passwd /etc/passwd
        --ro-bind /etc/group /etc/group
        --ro-bind /etc/ssl /etc/ssl
        --ro-bind /etc/nix /etc/nix
        --ro-bind /etc/static /etc/static
        --ro-bind-try /etc/hosts /etc/hosts
        --ro-bind-try /etc/nsswitch.conf /etc/nsswitch.conf
        --ro-bind-try /etc/login.defs /etc/login.defs
        --ro-bind-try /etc/subuid /etc/subuid
        --ro-bind-try /etc/subgid /etc/subgid
        --ro-bind-try /etc/containers /etc/containers

        --proc /proc
        --dev /dev
        --size 4294967296 --tmpfs /tmp

        --ro-bind /data/projects /data/projects
        --bind "$PROJECT_DIR" "$PROJECT_DIR"

        --dir $HOME_DIR
        --dir $HOME_DIR/.config
        --dir $HOME_DIR/.local
        --dir $HOME_DIR/.local/share
        --ro-bind-try $HOME_DIR/.gitconfig $HOME_DIR/.gitconfig
        --ro-bind-try $HOME_DIR/.npmrc $HOME_DIR/.npmrc
        --ro-bind-try $HOME_DIR/.claude $HOME_DIR/.claude
        --ro-bind-try $HOME_DIR/.codex $HOME_DIR/.codex
        --ro-bind-try $HOME_DIR/.config/opencode $HOME_DIR/.config/opencode
        --ro-bind-try $HOME_DIR/.config/git $HOME_DIR/.config/git
        --bind-try $HOME_DIR/.local/share/opencode $HOME_DIR/.local/share/opencode
        --bind-try $HOME_DIR/.pi/agent $HOME_DIR/.pi/agent
        --bind-try $HOME_DIR/.gemini $HOME_DIR/.gemini
        --bind-try $HOME_DIR/.local/share/containers $HOME_DIR/.local/share/containers

        --dir /run/user
        --dir "$RUNTIME_DIR"
        --bind-try "$RUNTIME_DIR/containers" "$RUNTIME_DIR/containers"
        --ro-bind-try "$RUNTIME_DIR/podman" "$RUNTIME_DIR/podman"

        --clearenv
        --setenv HOME "$HOME_DIR"
        --setenv USER "$USER_NAME"
        --setenv SHELL /bin/bash
        --setenv TERM "$TERM_VALUE"
        --setenv LANG C.UTF-8
        --setenv PATH ${sandbox-docker-compat}/bin:${zmx}/bin:/run/current-system/sw/bin:/etc/profiles/per-user/$USER_NAME/bin:$HOME_DIR/.nix-profile/bin:/nix/var/nix/profiles/default/bin
        --setenv SANDBOX 1
        --setenv SANDBOX_NAME "$NAME"
        --setenv SANDBOX_PROJECT "$PROJECT_DIR"
        --setenv NIX_REMOTE daemon
        --chdir "$PROJECT_DIR"
      )

      if [ -n "''${NIX_PATH:-}" ]; then
        BWRAP_ARGS+=( --setenv NIX_PATH "$NIX_PATH" )
      fi

      if [ -n "''${ANTHROPIC_API_KEY:-}" ]; then
        BWRAP_ARGS+=( --setenv ANTHROPIC_API_KEY "$ANTHROPIC_API_KEY" )
      fi
      if [ -n "''${ANTHROPIC_BASE_URL:-}" ]; then
        BWRAP_ARGS+=( --setenv ANTHROPIC_BASE_URL "$ANTHROPIC_BASE_URL" )
      fi
      if [ -n "''${OPENAI_API_KEY:-}" ]; then
        BWRAP_ARGS+=( --setenv OPENAI_API_KEY "$OPENAI_API_KEY" )
      fi
      if [ -n "''${GITHUB_TOKEN:-}" ]; then
        BWRAP_ARGS+=( --setenv GITHUB_TOKEN "$GITHUB_TOKEN" )
      fi
      if [ -n "''${GH_TOKEN:-}" ]; then
        BWRAP_ARGS+=( --setenv GH_TOKEN "$GH_TOKEN" )
      fi
      if [ -n "''${GEMINI_API_KEY:-}" ]; then
        BWRAP_ARGS+=( --setenv GEMINI_API_KEY "$GEMINI_API_KEY" )
      fi
      if [ -n "''${GOOGLE_API_KEY:-}" ]; then
        BWRAP_ARGS+=( --setenv GOOGLE_API_KEY "$GOOGLE_API_KEY" )
      fi
      if [ -n "''${XAI_API_KEY:-}" ]; then
        BWRAP_ARGS+=( --setenv XAI_API_KEY "$XAI_API_KEY" )
      fi
      if [ -n "''${OPENROUTER_API_KEY:-}" ]; then
        BWRAP_ARGS+=( --setenv OPENROUTER_API_KEY "$OPENROUTER_API_KEY" )
      fi

      exec ${pkgs.bubblewrap}/bin/bwrap "''${BWRAP_ARGS[@]}" -- ${lib.escapeShellArg agentCfg.agentBinary} "$@"
    '';

  mkJcard = name: agentCfg:
    let
      sessionName = if agentCfg.session != "" then agentCfg.session else name;
      baseAgent = {
        type = "native";
        harness = agentCfg.harness;
        prompt = agentCfg.prompt;
        workdir = agentCfg.workdir;
        restart = agentCfg.restart;
        max_restarts = agentCfg.maxRestarts;
        grace_period = agentCfg.gracePeriod;
        session = sessionName;
        env = agentCfg.env;
      } // lib.optionalAttrs (agentCfg.promptFile != null) {
        prompt_file = toString agentCfg.promptFile;
      } // lib.optionalAttrs (agentCfg.timeout != "") {
        timeout = agentCfg.timeout;
      };
    in
    lib.generators.toTOML { } {
      agent = baseAgent;
    };

  mkExecStart = name: agentCfg:
    let
      args = [
        "-config" "/etc/agentd/${name}/jcard.toml"
        "-api-socket" "/run/agentd/${name}/agentd.sock"
        "-tmux-socket" "/run/agentd/${name}/tmux.sock"
        "-secret-dir" "/run/agentd/${name}/secrets/"
      ] ++ agentCfg.extraArgs;
    in
    "${agentCfg.package}/bin/agentd ${lib.escapeShellArgs args}";

  defaultEnvironmentFile = "/run/secrets/rendered/agentd-env";

  mkAgentService = name: agentCfg:
    let
      wrapper = mkAgentWrapper name agentCfg;
      environmentFile =
        if agentCfg.environmentFile != null then
          agentCfg.environmentFile
        else
          defaultEnvironmentFile;
    in
    {
      description = "agentd agent: ${name}";
      after = [ "network-online.target" "sops-nix.service" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
      path = [ wrapper ] ++ (with pkgs; [ tmux sudo bubblewrap coreutils ]);
      serviceConfig = {
        ExecStart = mkExecStart name agentCfg;
        RuntimeDirectory = "agentd/${name}";
        RuntimeDirectoryMode = "0750";
        DynamicUser = false;
        User = "root";
        Restart = "on-failure";
        RestartSec = 5;
        EnvironmentFile = environmentFile;
      };
    };

  mkProxyService = name: agentCfg:
    lib.mkIf (agentCfg.apiProxyPort != null) {
      description = "TCP proxy for agentd-${name} API";
      after = [ "agentd-${name}.service" ];
      bindsTo = [ "agentd-${name}.service" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        ExecStart = "${pkgs.socat}/bin/socat TCP-LISTEN:${toString agentCfg.apiProxyPort},fork,reuseaddr UNIX-CONNECT:/run/agentd/${name}/agentd.sock";
        Restart = "on-failure";
        RestartSec = 3;
      };
    };
in
{
  options.services.agentd = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable agentd managed services defined under services.agentd.agents.";
    };

    agents = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule ({ ... }: {
        options = {
          enable = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Enable this agentd-managed agent.";
          };

          package = lib.mkOption {
            type = lib.types.package;
            default = pkgs.agentd;
            description = "agentd package to execute for this agent instance.";
          };

          harness = lib.mkOption {
            type = lib.types.enum [ "claude-code" "opencode" "gemini-cli" "custom" ];
            default = "custom";
            description = "Agent harness configured in jcard.toml.";
          };

          command = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = "Binary path used when sandbox=false and harness=custom.";
          };

          agentBinary = lib.mkOption {
            type = lib.types.str;
            default = "claude";
            description = "Agent CLI binary launched by the wrapper inside bubblewrap.";
          };

          prompt = lib.mkOption {
            type = lib.types.str;
            default = "";
            description = "Inline startup prompt. Empty means interactive mode.";
          };

          promptFile = lib.mkOption {
            type = lib.types.nullOr lib.types.path;
            default = null;
            description = "Path to prompt file. Takes precedence over prompt.";
          };

          workdir = lib.mkOption {
            type = lib.types.str;
            default = "/data/projects";
            description = "Agent working directory.";
          };

          restart = lib.mkOption {
            type = lib.types.enum [ "no" "on-failure" "always" ];
            default = "no";
            description = "Restart policy for the agent in jcard.toml.";
          };

          maxRestarts = lib.mkOption {
            type = lib.types.int;
            default = 0;
            description = "Maximum restart attempts. 0 means unlimited.";
          };

          timeout = lib.mkOption {
            type = lib.types.str;
            default = "";
            description = "Optional agent timeout (Go duration string).";
          };

          gracePeriod = lib.mkOption {
            type = lib.types.str;
            default = "30s";
            description = "Grace period between SIGINT and forced shutdown.";
          };

          session = lib.mkOption {
            type = lib.types.str;
            default = "";
            description = "tmux session name. Empty defaults to agent attr name.";
          };

          env = lib.mkOption {
            type = lib.types.attrsOf lib.types.str;
            default = { };
            description = "Extra environment variables rendered into jcard.toml [agent.env].";
          };

          environmentFile = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = "Optional systemd EnvironmentFile containing API keys for this agent.";
          };

          extraArgs = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [ ];
            description = "Extra CLI flags passed to agentd.";
          };

          sandbox = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Run through bubblewrap wrapper when true.";
          };

          user = lib.mkOption {
            type = lib.types.str;
            default = "myuser";
            description = "Identity used inside the bubblewrap sandbox (paths and env).";
          };

          apiProxyPort = lib.mkOption {
            type = lib.types.nullOr (lib.types.ints.between 1 65535);
            default = null;
            description = "Optional TCP port for a local socat proxy to the agentd API socket.";
          };
        };
      }));
      default = { };
      description = "agentd agent definitions keyed by agent name.";
    };
  };

  config = lib.mkIf config.services.agentd.enable (
    let
      enabledAgents = lib.filterAttrs (_: agentCfg: agentCfg.enable) config.services.agentd.agents;
    in
    {
      assertions = [
        (mkCustomHarnessAssertion config.services.agentd.agents)
        (mkDuplicateProxyPortAssertion enabledAgents)
      ];

      sops.templates = lib.mkIf (enabledAgents != { }) {
        "agentd-env" = {
          content = ''
            ANTHROPIC_API_KEY=${config.sops.placeholder."anthropic-api-key"}
          '';
          owner = "root";
        };
      };

      environment.etc = lib.mapAttrs'
        (name: agentCfg: {
          name = "agentd/${name}/jcard.toml";
          value.text = mkJcard name agentCfg;
        })
        enabledAgents;

      systemd.services =
        (lib.mapAttrs'
          (name: agentCfg: lib.nameValuePair "agentd-${name}" (mkAgentService name agentCfg))
          enabledAgents)
        //
        (lib.mapAttrs'
          (name: agentCfg: lib.nameValuePair "agentd-proxy-${name}" (mkProxyService name agentCfg))
          enabledAgents);
    }
  );
}
