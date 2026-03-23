# modules/agent-compute.nix
# @decision: Package names are `claude-code` and `codex` from llm-agents overlay
#   (not `llm-agents-claude-code` — the overlay adds packages directly to pkgs namespace)
# @decision SANDBOX-11-01: Podman is enabled rootless; dockerCompat=false to avoid
#   — installing a system-wide docker->podman symlink (private overlay may enable Docker).
{ config, lib, pkgs, ... }:
let
  cfg = config.services.agentCompute;
  agentCfg = config.tsurf.agent;
in
{
  options.services.agentCompute.enable = lib.mkEnableOption "Agent runtime support (zmx, podman, shared overlays)";

  config = lib.mkIf cfg.enable {
  # @decision SEC-116-01: Raw agent binaries are NOT installed in PATH. Sandboxed
  #   wrappers in agent-sandbox.nix and opt-in extras reference full store paths
  #   directly (AGENT_REAL_BINARY). Combined with the brokered launch model
  #   (SEC-119-01), interactive sessions run as the agent user — the operator
  #   cannot exec the raw binary with agent credentials.
  environment.systemPackages = [
    pkgs.zmx
    pkgs.nodejs
  ];

  # Rootless Podman for sandboxed agent container workflows.
  # dockerCompat = false because virtualisation.false — avoids system-wide symlink; private overlay may enable Docker.
  virtualisation.podman = {
    enable = true;
    dockerCompat = false;
    defaultNetwork.settings.dns_enabled = true;
  };

  # @decision SEC-116-02: Dedicated cgroup slice for agent workloads.
  #   Aggregate resource ceiling prevents runaway agents from starving critical services.
  #   Individual agent units set tighter per-service limits within this slice.
  systemd.slices.tsurf-agents = {
    description = "Agent workload resource slice";
    sliceConfig = {
      MemoryMax = "8G";
      CPUQuota = "300%";
      TasksMax = 1024;
    };
  };
  }; # end lib.mkIf
}
