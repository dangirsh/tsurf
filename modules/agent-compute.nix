# modules/agent-compute.nix
# @decision: Package names are `claude-code` and `codex` from llm-agents overlay
#   (not `llm-agents-claude-code` — the overlay adds packages directly to pkgs namespace)
# @decision SANDBOX-11-01: Podman is enabled rootless; dockerCompat=false (conflicts with Docker)
#   — sandbox uses a PATH-local docker->podman symlink derivation.
# @decision SEC47-13: --no-sandbox agent = effective root access (accepted risk)
# @rationale: --no-sandbox -> dev -> wheel -> passwordless sudo -> root.
#   Mitigated by default sandbox-on, audit log, operator awareness.
{ config, pkgs, ... }:

let
  # @decision: zmx pre-built static binary from zmx.sh (zig2nix flake build requires
  #   bwrap which fails under apparmor-restricted user namespaces). Inlined from packages/zmx.nix.
  zmx = pkgs.stdenv.mkDerivation rec {
    pname = "zmx";
    version = "0.3.0";
    src = pkgs.fetchurl {
      url = "https://zmx.sh/a/zmx-${version}-linux-x86_64.tar.gz";
      hash = "sha256-/K/xWB61pqPll4Gq13qMoGm0Q1vC/sQT3TI7RaTf3zI=";
    };
    sourceRoot = ".";
    installPhase = ''
      runHook preInstall
      install -m755 -D zmx $out/bin/zmx
      runHook postInstall
    '';
    meta = with pkgs.lib; {
      description = "Session persistence for terminal processes";
      homepage = "https://github.com/neurosnap/zmx";
      platforms = [ "x86_64-linux" ];
    };
  };
in
{
  # Agent CLI packages from llm-agents.nix overlay
  environment.systemPackages = [
    pkgs.claude-code
    pkgs.codex
    zmx
  ];

  # Rootless Podman for sandboxed agent container workflows.
  # dockerCompat = false because virtualisation.docker.enable = true in docker.nix —
  # NixOS asserts they cannot coexist.
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

  # Pre-create audit log directory for agent spawn logging.
  systemd.tmpfiles.rules = [
    "d /data/projects/.agent-audit 0750 dev users -"
  ];

  # User linger for persistent systemd user instance
  users.users.dev.linger = true;
  services.dashboard.entries.agent-compute = {
    name = "Agent Compute";
    module = "agent-compute.nix";
    description = "Claude Code, Codex, Podman sandbox";
    icon = "terminal";
    order = 70;
  };
}
