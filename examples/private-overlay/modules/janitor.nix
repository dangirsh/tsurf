# modules/janitor.nix
# @decision JANITOR-103-01: Natural-language system prompt replaces bash logic. Cleanup behavior changed by editing English.
# @decision JANITOR-103-02: Custom nono profile (janitor.json) extends claude-code with /tmp, /nix/var, /var/lib/janitor write access.
# @decision JANITOR-103-03: bypassPermissions inside nono sandbox — accepted risk matching SEC98-01.
{ config, lib, pkgs, ... }:
let
  cfg = config.services.janitor;
  reportDir = builtins.dirOf cfg.reportPath;

  janitorProfile = {
    extends = "claude-code";
    meta = {
      name = "janitor";
      version = "1.0.0";
      description = "Agentic janitor profile for scheduled system cleanup";
      author = "tsurf";
    };
    filesystem = {
      allow = [
        "/tmp"
        "/nix/var"
        "/var/lib/janitor"
        reportDir
        "/proc"
      ];
      allow_file = [ cfg.reportPath ];
    };
    network = {
      block = false;
    };
    workdir = {
      access = "readwrite";
    };
    interactive = false;
  };

  janitorProfileFile = pkgs.writeText "janitor-nono-profile.json" (builtins.toJSON janitorProfile);
  systemPromptFile = pkgs.writeText "janitor-system-prompt.txt" cfg.systemPrompt;
  modelArg = lib.optionalString (cfg.model != "") "--model ${lib.escapeShellArg cfg.model}";

  janitorScript = pkgs.writeShellScript "janitor-agent" ''
    set -euo pipefail

    if [ -f "$ANTHROPIC_API_KEY_FILE" ]; then
      export ANTHROPIC_API_KEY
      ANTHROPIC_API_KEY="$(cat "$ANTHROPIC_API_KEY_FILE")"
    else
      echo "ERROR: ANTHROPIC_API_KEY_FILE not found: $ANTHROPIC_API_KEY_FILE" >&2
      timestamp="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
      cat > "${cfg.reportPath}" <<REPORT
    {
      "timestamp": "$timestamp",
      "diskBefore": "unknown",
      "diskAfter": "unknown",
      "zombieCount": -1,
      "filesCleaned": -1,
      "tmpMaxAgeDays": ${toString cfg.tmpMaxAgeDays},
      "nixGcOlderThan": "${cfg.nixGcOlderThan}",
      "error": "missing ANTHROPIC_API_KEY_FILE"
    }
REPORT
      exit 1
    fi

    prompt_text="$(cat ${systemPromptFile})"

    set +e
    nono run \
      --profile /etc/nono/profiles/janitor.json \
      --net-allow \
      -- claude -p \
      --permission-mode=bypassPermissions \
      ${modelArg} \
      --system-prompt "$prompt_text" \
      "Run the maintenance tasks now and write the report."
    exit_code=$?
    set -e

    if [ "$exit_code" -ne 0 ]; then
      timestamp="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
      cat > "${cfg.reportPath}" <<REPORT
    {
      "timestamp": "$timestamp",
      "diskBefore": "unknown",
      "diskAfter": "unknown",
      "zombieCount": -1,
      "filesCleaned": -1,
      "tmpMaxAgeDays": ${toString cfg.tmpMaxAgeDays},
      "nixGcOlderThan": "${cfg.nixGcOlderThan}",
      "error": "claude janitor failed with exit code $exit_code"
    }
REPORT
      exit "$exit_code"
    fi
  '';
in {
  options.services.janitor = {
    enable = lib.mkEnableOption "weekly janitor maintenance service";

    schedule = lib.mkOption {
      type = lib.types.str;
      default = "Mon *-*-* 03:00:00";
      description = "systemd OnCalendar schedule for janitor runs.";
    };

    tmpMaxAgeDays = lib.mkOption {
      type = lib.types.int;
      default = 7;
      description = "Delete /tmp files not accessed for this many days.";
    };

    nixGcOlderThan = lib.mkOption {
      type = lib.types.str;
      default = "7d";
      description = "Age threshold passed to nix-collect-garbage --delete-older-than.";
    };

    reportPath = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/janitor/report.json";
      description = "Path where the janitor JSON report is written.";
    };

    systemPrompt = lib.mkOption {
      type = lib.types.lines;
      default = ''
        You are the janitor maintenance agent running on a NixOS host.

        Execute these tasks in order:
        1. Capture disk usage for /. Store as diskBefore in compact human-readable format.
        2. Count zombie processes and store as zombieCount.
        3. Delete stale regular files from /tmp not accessed for more than ${toString cfg.tmpMaxAgeDays} days.
        4. Run: nix-collect-garbage --delete-older-than ${cfg.nixGcOlderThan}
        5. Capture disk usage for / after cleanup as diskAfter.
        6. Write the cleanup report to ${cfg.reportPath}.

        You must write JSON with this exact schema and keys:
        {
          "timestamp": "ISO-8601 UTC string",
          "diskBefore": "string",
          "diskAfter": "string",
          "zombieCount": number,
          "filesCleaned": number,
          "tmpMaxAgeDays": ${toString cfg.tmpMaxAgeDays},
          "nixGcOlderThan": "${cfg.nixGcOlderThan}"
        }

        Rules:
        - Never modify paths outside /tmp and /nix/var except writing the report file.
        - Never install packages or change system configuration.
        - If a step fails, log the error, continue with remaining safe steps, and still write the JSON report.
        - Do not output markdown; write only valid JSON to ${cfg.reportPath}.
      '';
      description = "Natural-language system prompt controlling janitor behavior.";
    };

    model = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "Claude model override passed as --model when non-empty.";
    };
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      systemd.tmpfiles.rules = [
        "d ${reportDir} 0750 root root - -"
      ];

      environment.etc."nono/profiles/janitor.json".source = janitorProfileFile;

      systemd.services.janitor = {
        description = "Janitor weekly system maintenance";
        path = [ pkgs.coreutils pkgs.nono pkgs.claude-code ];
        serviceConfig = {
          Type = "oneshot";
          ExecStart = "${janitorScript}";
          NoNewPrivileges = true;
          ProtectSystem = "full";
          PrivateTmp = false;
          PrivateDevices = true;
          ProtectControlGroups = true;
          ProtectKernelTunables = true;
          ProtectKernelModules = true;
          LockPersonality = true;
          RestrictSUIDSGID = true;
          ReadWritePaths = [ "/tmp" "/nix/var" reportDir ];
          Restart = "on-failure";
          RestartSec = "60s";
          Environment = [
            "ANTHROPIC_API_KEY_FILE=/run/secrets/anthropic-api-key"
          ];
        };
      };

      systemd.timers.janitor = {
        description = "Run janitor maintenance on schedule";
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = cfg.schedule;
          Persistent = true;
          Unit = "janitor.service";
        };
      };
    }
    (lib.mkIf (config.services ? dashboard) {
      services.dashboard.entries.janitor = {
        name = "Janitor";
        description = "Weekly system maintenance and cleanup";
        icon = "mdi-broom";
        systemdUnit = "janitor.service";
        order = 70;
        module = "janitor.nix";
      };
    })
  ]);
}
