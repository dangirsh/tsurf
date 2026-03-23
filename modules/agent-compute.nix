# modules/agent-compute.nix
# @decision: Package names are `claude-code` and `codex` from llm-agents overlay
#   (not `llm-agents-claude-code` — the overlay adds packages directly to pkgs namespace)
# @decision SANDBOX-139-01: Core agent-compute no longer enables Podman by default.
#   Container runtime integration is optional and belongs in private overlay/extras.
{ config, lib, pkgs, ... }:
let
  cfg = config.services.agentCompute;
in
{
  options.services.agentCompute.enable = lib.mkEnableOption "Agent runtime support (zmx and shared overlays)";

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
  # --- Persistence: project workspace ---
  environment.persistence."/persist".directories = [
    "/data/projects"
  ];

  }; # end lib.mkIf
}
