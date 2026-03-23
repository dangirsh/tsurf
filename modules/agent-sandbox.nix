# modules/agent-sandbox.nix
# @decision SANDBOX-73-01: Wrapper scripts replace bare agent binaries on dev hosts.
#   Public wrappers always route through nono; unsandboxed execution is private-overlay-only.
# @decision AUDIT-117-01: Launch logging via journald only (logger -t agent-launch).
#   File-based audit log removed — was user-owned/tamperable and leaked raw arguments.
# @decision NONO-118-02: API keys loaded from /run/secrets/ by scripts/agent-wrapper.sh
#   into the parent env. nono's reverse proxy reads them via env:// URIs and injects
#   per-session phantom tokens into the sandboxed child (--credential flag).
#   The child never sees real API keys.
# @decision SEC-119-01: Brokered launch model — interactive agent sessions run as the
#   agent user via systemd-run, not as the calling operator. Eliminates same-user
#   sandbox bypass. Operator invokes wrapper → sudo tsurf-launch-<agent> → systemd-run
#   --uid=agent → agent-wrapper.sh. When already running as agent (e.g. dev-agent.nix),
#   the wrapper execs agent-wrapper.sh directly (no double privilege drop).
# @decision SEC-135-01: The privileged sudo boundary exposes immutable per-agent launchers,
#   not a generic env-configured root helper. Real binary, profile, credentials, and
#   daemon access are baked into each launcher, so sudoers no longer needs SETENV.
{ config, lib, pkgs, ... }:
let
  cfg = config.services.agentSandbox;
  agentCfg = config.tsurf.agent;
  nonoCfg = config.services.nonoSandbox;
  agentRuntimePath = lib.makeBinPath [ pkgs.bash pkgs.coreutils pkgs.git pkgs.nono pkgs.util-linux ];

  mkAgent = { name, realPkg, realBin, credentials }:
    let
      launcherName = "tsurf-launch-${name}";
      launcher = pkgs.writeShellApplication {
        name = launcherName;
        runtimeInputs = [ pkgs.systemd pkgs.coreutils ];
        text = ''
          export AGENT_NAME="${name}"
          export AGENT_REAL_BINARY="${realPkg}/bin/${realBin}"
          export AGENT_PROJECT_ROOT="${cfg.projectRoot}"
          export AGENT_NONO_PROFILE="/etc/nono/profiles/tsurf.json"
          export AGENT_CREDENTIALS="${lib.concatStringsSep " " credentials}"
          ${lib.optionalString cfg.allowNixDaemon "export AGENT_ALLOW_NIX_DAEMON=1"}

          case "$AGENT_REAL_BINARY" in
            /nix/store/*) ;;
            *) echo "ERROR: AGENT_REAL_BINARY must be in /nix/store" >&2; exit 1 ;;
          esac

          if [[ -t 0 && -t 1 ]]; then
            stdio_flag="--pty"
          else
            stdio_flag="--pipe"
          fi

          exec systemd-run \
            --uid="${agentCfg.user}" --gid="${toString agentCfg.gid}" \
            "$stdio_flag" --same-dir --collect \
            --unit="agent-${name}-$$" \
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
            ${lib.optionalString cfg.allowNixDaemon "--setenv=AGENT_ALLOW_NIX_DAEMON=1 \\"}
            ${pkgs.bash}/bin/bash ${../scripts/agent-wrapper.sh} "$@"
        '';
      };
      wrapper = (pkgs.writeShellApplication {
        inherit name;
        runtimeInputs = [ pkgs.nono pkgs.git pkgs.coreutils pkgs.util-linux ];
        text = ''
          export AGENT_NAME="${name}"
          export AGENT_REAL_BINARY="${realPkg}/bin/${realBin}"
          export AGENT_PROJECT_ROOT="${cfg.projectRoot}"
          export AGENT_NONO_PROFILE="/etc/nono/profiles/tsurf.json"
          export AGENT_CREDENTIALS="${lib.concatStringsSep " " credentials}"
          ${lib.optionalString cfg.allowNixDaemon "export AGENT_ALLOW_NIX_DAEMON=1"}

          if [[ "$(id -un)" == "${agentCfg.user}" ]]; then
            exec bash ${../scripts/agent-wrapper.sh} "$@"
          fi

          exec /run/wrappers/bin/sudo ${launcher}/bin/${launcherName} "$@"
        '';
      }).overrideAttrs (old: { meta = (old.meta or {}) // { priority = 4; }; });
    in {
      inherit launcher launcherName wrapper;
    };

  registeredAgents =
    map
      mkAgent
      ([{
        name = "claude";
        realPkg = pkgs.claude-code;
        realBin = "claude";
        credentials = [ "anthropic:ANTHROPIC_API_KEY:anthropic-api-key" ];
      }] ++ map (a: {
        name = a.name;
        realPkg = a.package;
        realBin = a.binary;
        credentials = a.credentials;
      }) cfg.extraAgents);

  mkTimerCredential = credName:
    let
      cred = nonoCfg._credentialDefs.${credName};
    in {
      inherit (cred) upstream inject_header credential_format;
      credential_key = "env://${cred.envVar}";
      env_var = cred.envVar;
    };

  mkTimerProfile = name: timerCfg: {
    extends = "claude-code";
    meta = {
      inherit name;
      version = "1.0.0";
      description = timerCfg.description;
      author = "tsurf";
    };
    filesystem = {
      allow = timerCfg.filesystem.allow;
      allow_file = timerCfg.filesystem.allowFile;
    };
    network = {
      block = false;
      custom_credentials = lib.genAttrs timerCfg.credentials mkTimerCredential;
    };
    workdir.access = "readwrite";
    interactive = false;
  };

  mkTimerScript = name: timerCfg:
    let
      credentialFlags = lib.concatMapStringsSep " " (credName: "--credential ${credName}") timerCfg.credentials;
      cliArgs =
        if timerCfg.cliArgs == [ ]
        then ""
        else lib.concatMapStringsSep " " lib.escapeShellArg timerCfg.cliArgs;
      promptArg = lib.escapeShellArg timerCfg.prompt;
      envChecks = lib.concatMapStrings (credName:
        let cred = nonoCfg._credentialDefs.${credName}; in
        ": \"\${${cred.envVar}:?set by systemd EnvironmentFile}\"\n"
      ) timerCfg.credentials;
      commandParts = builtins.filter (part: part != "") [
        "exec nono run"
        "--profile /etc/nono/profiles/${name}.json"
        "--net-allow"
        credentialFlags
        "-- ${timerCfg.package}/bin/${timerCfg.binary}"
        cliArgs
        promptArg
      ];
      commandText = lib.concatStringsSep " \\\n  " commandParts;
    in
    pkgs.writeShellScript "${name}-agent" ''
      set -euo pipefail
      ${envChecks}${commandText}
    '';

  timerProfileEtc =
    lib.mapAttrs'
      (name: timerCfg:
        lib.nameValuePair "nono/profiles/${name}.json" {
          source = pkgs.writeText "${name}-nono-profile.json" (builtins.toJSON (mkTimerProfile name timerCfg));
        })
      cfg.agentTimers;

  timerEnvTemplates =
    lib.mapAttrs'
      (name: timerCfg:
        lib.nameValuePair "${name}-env" {
          content = lib.concatMapStrings (credName:
            let cred = nonoCfg._credentialDefs.${credName}; in
            "${cred.envVar}=${config.sops.placeholder.${cred.secretName}}\n"
          ) timerCfg.credentials;
        })
      cfg.agentTimers;

  timerServices =
    lib.mapAttrs
      (name: timerCfg: {
        description = timerCfg.description;
        wants = [ "network-online.target" ];
        after = [ "network-online.target" ];
        serviceConfig = {
          Type = "oneshot";
          User = agentCfg.user;
          WorkingDirectory = timerCfg.workingDirectory;
          ExecStart = mkTimerScript name timerCfg;
          EnvironmentFile = config.sops.templates."${name}-env".path;
          Slice = "tsurf-agents.slice";
          MemoryMax = timerCfg.memoryMax;
          TasksMax = timerCfg.tasksMax;
          NoNewPrivileges = true;
          PrivateTmp = true;
          ProtectClock = true;
          ProtectKernelTunables = true;
          ProtectKernelModules = true;
          ProtectKernelLogs = true;
          ProtectControlGroups = true;
          LockPersonality = true;
          RestrictRealtime = true;
          RestrictSUIDSGID = true;
        };
      })
      cfg.agentTimers;

  timerTimers =
    lib.mapAttrs'
      (name: timerCfg:
        lib.nameValuePair name {
          description = "Run ${name} agent on schedule";
          wantedBy = [ "timers.target" ];
          timerConfig = {
            OnCalendar = timerCfg.timer.onCalendar;
            Persistent = timerCfg.timer.persistent;
          };
        })
      (lib.filterAttrs (_: timerCfg: timerCfg.timer.onCalendar != null) cfg.agentTimers);

  timerTmpfiles =
    lib.mapAttrsToList
      (_: timerCfg: "d ${timerCfg.workingDirectory} 0755 ${agentCfg.user} users -")
      cfg.agentTimers;

in
{
  options.services.agentSandbox = {
    enable = lib.mkEnableOption "sandboxed claude wrapper plus opt-in extra agent wrappers";

    extraAgents = lib.mkOption {
      type = lib.types.listOf (lib.types.submodule ({ config, ... }: {
        options = {
          name = lib.mkOption {
            type = lib.types.str;
            description = "Wrapper binary name (exposed in PATH).";
          };
          package = lib.mkOption {
            type = lib.types.package;
            description = "Package containing the agent binary.";
          };
          binary = lib.mkOption {
            type = lib.types.str;
            default = config.name;
            description = "Binary name within the package (defaults to name).";
          };
          credentials = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [];
            description = "Credential triples for nono proxy (SERVICE:ENV_VAR:secret-file-name).";
          };
        };
      }));
      default = [];
      description = "Additional agents to register with the brokered sandbox (used by extras modules).";
    };

    projectRoot = lib.mkOption {
      type = lib.types.str;
      default = config.tsurf.agent.projectRoot;
      description = "Root directory for sandboxed agent execution. PWD must be inside this path.";
    };

    allowNixDaemon = lib.mkEnableOption "access to /nix/var/nix/daemon-socket inside the sandbox";

    egressControl = {
      enable = lib.mkEnableOption "UID-based nftables egress filtering for agent user";
      allowedPorts = lib.mkOption {
        type = lib.types.listOf lib.types.port;
        default = [ 53 80 443 22 9418 ];
        description = "TCP destination ports the agent user may connect to.";
      };
      # @decision SEC-115-03: Egress control defaults to agent user, not operator.
      user = lib.mkOption {
        type = lib.types.str;
        default = config.tsurf.agent.user;
        description = "Username whose egress is restricted.";
      };
    };

    agentTimers = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule {
        options = {
          description = lib.mkOption {
            type = lib.types.str;
            description = "Systemd service description.";
          };
          prompt = lib.mkOption {
            type = lib.types.str;
            description = "Prompt passed to the agent CLI as the final argument.";
          };
          package = lib.mkOption {
            type = lib.types.package;
            default = pkgs.claude-code;
            description = "Package containing the timer agent binary.";
          };
          binary = lib.mkOption {
            type = lib.types.str;
            default = "claude";
            description = "Binary name within the timer agent package.";
          };
          cliArgs = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [ "-p" "--permission-mode=bypassPermissions" ];
            description = "CLI arguments inserted between the binary and prompt.";
          };
          workingDirectory = lib.mkOption {
            type = lib.types.str;
            description = "Working directory for the systemd service.";
          };
          filesystem = {
            allow = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [ ];
              description = "Extra directories granted to the generated nono profile.";
            };
            allowFile = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [ ];
              description = "Extra files granted to the generated nono profile.";
            };
          };
          credentials = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [ "anthropic" ];
            description = "Credential names from services.nonoSandbox credential definitions.";
          };
          timer = {
            onCalendar = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              description = "systemd OnCalendar expression. Null disables the timer.";
            };
            persistent = lib.mkOption {
              type = lib.types.bool;
              default = true;
              description = "Whether missed timer runs should execute on boot.";
            };
          };
          memoryMax = lib.mkOption {
            type = lib.types.str;
            default = "2G";
            description = "MemoryMax applied to the generated systemd service.";
          };
          tasksMax = lib.mkOption {
            type = lib.types.ints.positive;
            default = 64;
            description = "TasksMax applied to the generated systemd service.";
          };
        };
      });
      default = { };
      description = ''
        Declarative oneshot and timer-driven agent services that auto-generate
        their nono profile, environment template, launch script, and systemd units.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    # Replace bare agent binaries with sandboxed wrappers (meta.priority = 4 wins over default 5).
    environment.systemPackages = map (agent: agent.wrapper) registeredAgents;

    # When Nix daemon socket access is enabled in the sandbox, also allow the agent
    # user to authenticate with the daemon (complements the Landlock socket grant).
    nix.settings.allowed-users = lib.mkIf cfg.allowNixDaemon [ agentCfg.user ];

    # @decision SEC-119-02: Targeted NOPASSWD sudoers rules for the immutable brokered launchers.
    #   Scoped to %wheel group (compatible with execWheelOnly=true in users.nix).
    #   Agent user is NOT in wheel (enforced by assertions), so cannot use this rule.
    #   Launch configuration is baked into each root-owned launcher, so callers cannot
    #   swap binaries, profiles, or credential tuples across the sudo boundary.
    security.sudo.extraRules = [{
      groups = [ "wheel" ];
      commands = map (agent: {
        command = "${agent.launcher}/bin/${agent.launcherName}";
        options = [ "NOPASSWD" ];
      }) registeredAgents;
    }];

    # --- Persistence: agent user home state ---
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

    environment.etc = timerProfileEtc;
    sops.templates = timerEnvTemplates;
    systemd.services = timerServices;
    systemd.timers = timerTimers;
    systemd.tmpfiles.rules = timerTmpfiles;

    # @decision SANDBOX-NET-01: UID-based nftables egress filtering restricts the agent
    #   user to a whitelist of TCP destination ports. DNS (UDP 53) is always allowed.
    #   Tailscale traffic is unrestricted. All other outbound traffic is dropped.
    # @decision SEC-115-03: Egress control uses numeric UIDs (agentCfg.uid) in nftables
    #   rules so checkRuleset can remain enabled. Symbolic usernames require /etc/passwd
    #   at build time (unavailable in nix sandbox) — numeric UIDs do not.

    networking.nftables.tables.agent-egress = lib.mkIf cfg.egressControl.enable {
      family = "inet";
      content =
        let
          portList = lib.concatMapStringsSep ", " toString cfg.egressControl.allowedPorts;
          agentUid = toString agentCfg.uid;
        in ''
          chain output {
            type filter hook output priority 0; policy accept;
            meta skuid != ${agentUid} accept
            oifname "lo" accept
            ct state established,related accept
            meta l4proto udp th dport 53 accept
            meta l4proto tcp th dport { ${portList} } accept
            # Agent egress to tailnet peers (e.g., syncthing, other hosts). This is
            # outbound egress control, separate from the host firewall's ingress rules.
            # The host no longer trusts tailscale0 as an interface (NET-122-01).
            oifname "tailscale0" accept
            log prefix "agent-egress-deny: " drop
          }
        '';
    };
  };
}
