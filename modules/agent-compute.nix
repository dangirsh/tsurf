# @decision: Package names are `claude-code` and `codex` from llm-agents overlay
#   (not `llm-agents-claude-code` — the overlay adds packages directly to pkgs namespace)
# @decision AGENTD-40-01: Agent lifecycle managed by agentd (modules/agentd.nix);
#   agent-compute.nix provides CLI packages and sandbox infrastructure only.
# @decision SANDBOX-11-01: Podman is enabled rootless; dockerCompat=false (conflicts with Docker)
#   — sandbox uses a PATH-local docker->podman symlink derivation instead.
# @decision SEC47-13: --no-sandbox agent = effective root access (accepted risk)
# @rationale: The chain is: --no-sandbox -> runs as myuser -> wheel group
#   -> passwordless sudo -> root. Also: docker group -> root-equivalent.
#   This is inherent to the design: trusted operators use --no-sandbox for
#   operations requiring system access (deploy, sops, host config). The
#   default is sandbox-on (bubblewrap). Only explicit --no-sandbox bypasses it.
#   Mitigation: default sandbox, audit log (agentd-spawn), operator awareness.
#
# Blast radius matrix:
# - Sandboxed agent: project dir (rw), other projects (ro), API keys (env),
#   Nix daemon. CANNOT: /run/secrets, ~/.ssh, Docker, sudo, PID namespace.
# - --no-sandbox agent: full myuser access = all sops secrets, Docker socket,
#   passwordless sudo = effective root. Use only for trusted operations.
{ config, pkgs, ... }:

let
  zmx = pkgs.callPackage ../packages/zmx.nix {};
in
{
  # Agent CLI packages from llm-agents.nix overlay
  environment.systemPackages = [
    pkgs.claude-code
    pkgs.codex
    pkgs.opencode
    pkgs.gemini-cli
    pkgs.llm-agents.pi
    zmx
  ];

  # Rootless Podman for sandboxed agent container workflows.
  # dockerCompat = false because virtualisation.docker.enable = true in docker.nix —
  # NixOS asserts they cannot coexist. Instead, a sandbox-local docker->podman symlink
  # (sandbox-docker-compat derivation in agentd.nix) is added to the sandbox PATH so
  # agents see `docker` resolving to `podman` without affecting the host Docker daemon.
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

  # Pre-create audit log directory for agentd spawn logging.
  systemd.tmpfiles.rules = [
    "d /data/projects/.agent-audit 0750 myuser users -"
  ];

  # User linger for persistent systemd user instance
  users.users.myuser.linger = true;
}
