# @decision AGENTD-40-01: Agent lifecycle managed by agentd (modules/agentd.nix); agent-compute.nix provides CLI packages and sandbox infrastructure only.
# @decision: Package names are `claude-code` and `codex` from llm-agents overlay
#   (not `llm-agents-claude-code` — the overlay adds packages directly to pkgs namespace)
# @decision SANDBOX-11-01: Podman is enabled rootless; dockerCompat=false
{ pkgs, ... }:

let
  zmx = pkgs.callPackage ../packages/zmx.nix {};
in {
  # Agent CLI packages from llm-agents.nix overlay
  environment.systemPackages = [
    pkgs.claude-code
    pkgs.codex
    pkgs.opencode
    pkgs.gemini-cli
    pkgs.llm-agents.pi
    zmx
  ];

  # Rootless Podman for agent container workflows.
  virtualisation.podman = {
    enable = true;
    dockerCompat = false;
    defaultNetwork.settings.dns_enabled = true;
  };

  # Numtide binary cache for fast agent CLI builds
  nix.settings = {
    substituters = [
      "https://cache.numtide.com"
    ];
    trusted-public-keys = [
      "niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g="
    ];
  };

  # Systemd cgroup slice for agent workload isolation
  systemd.slices."agent" = {
    description = "Agent workload isolation slice";
    sliceConfig = {
      CPUWeight = 100;
      TasksMax = 4096;
    };
  };

  systemd.tmpfiles.rules = [
    "d /data/projects/.agent-audit 0750 myuser users -"
  ];

  users.users.myuser.linger = true;
}
