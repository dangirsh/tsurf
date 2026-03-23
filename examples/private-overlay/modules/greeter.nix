# modules/greeter.nix — Minimal example: a sandboxed agent that runs daily
#
# Uses the agentTimers abstraction from agent-sandbox.nix. The abstraction
# generates the nono profile, launch script, sops env template, systemd
# service, and timer automatically.
{ ... }:
{
  services.agentSandbox.agentTimers.greeter = {
    description = "Example daily greeting agent";
    prompt = "Write a short, cheerful greeting with today's date to /var/lib/greeter/greeting.txt. One sentence only.";
    workingDirectory = "/var/lib/greeter";
    filesystem.allow = [ "/var/lib/greeter" ];
    filesystem.allowFile = [ "/var/lib/greeter/greeting.txt" ];
    credentials = [ "anthropic" ];
    timer.onCalendar = "daily";
  };
}
