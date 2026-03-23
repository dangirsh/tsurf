# modules/greeter.nix — Minimal example: a sandboxed agent that runs daily
#
# Core no longer ships agentTimers, so this example is explicit:
# one nono profile file + one oneshot service + one timer.
{ config, pkgs, ... }:
let
  workDir = "/var/lib/greeter";
  prompt = "Write a short, cheerful greeting with today's date to /var/lib/greeter/greeting.txt. One sentence only.";
  profile = pkgs.writeText "greeter-nono-profile.json" (builtins.toJSON {
    extends = "tsurf";
    meta = {
      name = "greeter";
      version = "1.0.0";
      description = "Example daily greeting agent";
      author = "tsurf";
    };
    filesystem = {
      allow = [ workDir ];
      allow_file = [ "${workDir}/greeting.txt" ];
    };
    workdir = { access = "readwrite"; };
    interactive = false;
  });
  runGreeter = pkgs.writeShellScript "greeter-agent" ''
    set -euo pipefail
    : "''${ANTHROPIC_API_KEY:?set by systemd EnvironmentFile}"
    exec ${pkgs.nono}/bin/nono run \
      --profile /etc/nono/profiles/greeter.json \
      --credential anthropic \
      -- ${pkgs.claude-code}/bin/claude -p ${pkgs.lib.escapeShellArg prompt}
  '';
in
{
  environment.etc."nono/profiles/greeter.json".source = profile;

  sops.templates."greeter-env" = {
    content = ''
      ANTHROPIC_API_KEY=${config.sops.placeholder."anthropic-api-key"}
    '';
  };

  systemd.services.greeter = {
    description = "Example daily greeting agent";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    serviceConfig = {
      Type = "oneshot";
      User = config.tsurf.agent.user;
      WorkingDirectory = workDir;
      EnvironmentFile = config.sops.templates."greeter-env".path;
      ExecStart = runGreeter;
      Slice = "tsurf-agents.slice";
    };
  };

  systemd.timers.greeter = {
    description = "Run greeter agent daily";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "daily";
      Persistent = true;
    };
  };

  systemd.tmpfiles.rules = [
    "d ${workDir} 0755 ${config.tsurf.agent.user} users -"
  ];
}
