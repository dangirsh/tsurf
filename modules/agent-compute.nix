# modules/agent-compute.nix
# Agent runtime support: cgroup slice, shared tooling, project persistence.
{ config, lib, pkgs, ... }:
let
  cfg = config.services.agentCompute;
in
{
  options.services.agentCompute.enable = lib.mkEnableOption "Agent runtime support (zmx and shared overlays)";

  config = lib.mkIf cfg.enable {
  # @decision SEC-116-01: Raw agent binaries NOT in PATH — sandboxed wrappers only.
  environment.systemPackages = [
    pkgs.zmx
    pkgs.nodejs
  ];

  # @decision SEC-116-02: Dedicated cgroup slice prevents runaway agents from starving services.
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
