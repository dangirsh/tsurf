# modules/code-review.nix — Example: a scheduled code review agent
#
# Shows how to use the generic agent launcher to define a custom agent
# in ~20 lines. This agent reviews open PRs daily and posts summaries.
#
# Prerequisites:
#   - Import agent-launcher.nix, agent-compute.nix, nono.nix in your host config
#   - sops secret "anthropic-api-key" configured
#   - A git repo at /data/projects/my-project
{ config, pkgs, ... }:
{
  # Register a custom agent via the generic launcher
  services.agentLauncher.agents.code-review = {
    command = "claude";
    package = pkgs.claude-code;
    wrapperName = "code-review";
    credentials = [
      "anthropic:ANTHROPIC_API_KEY:anthropic-api-key"
    ];
    defaultArgs = [
      "-p"
      "Review the git log for the last 24 hours. Summarize changes, flag potential issues, and write a brief report to ./REVIEW.md."
    ];
    nonoProfile.extraAllow = [
      "/data/projects/my-project"
    ];
  };

  # Run the review agent daily at 6am
  systemd.services.code-review = {
    description = "Daily code review agent";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${config.services.agentLauncher.agents.code-review.package}/bin/claude -p \"Review the git log for the last 24 hours. Summarize changes, flag potential issues, and write a brief report to ./REVIEW.md.\"";
      WorkingDirectory = "/data/projects/my-project";
      User = config.tsurf.agent.user;
      Slice = "tsurf-agents.slice";
    };
  };

  systemd.timers.code-review = {
    description = "Run code review agent daily";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*-*-* 06:00:00";
      Persistent = true;
    };
  };
}
