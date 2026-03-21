# modules/agent-compute.nix
# @decision: Package names are `claude-code` and `codex` from llm-agents overlay
#   (not `llm-agents-claude-code` — the overlay adds packages directly to pkgs namespace)
# @decision SANDBOX-11-01: Podman is enabled rootless; dockerCompat=false (conflicts with Docker)
#   — sandbox uses a PATH-local docker->podman symlink derivation.
# @decision SEC47-13: --no-sandbox agent = effective root access (accepted risk)
# @rationale: --no-sandbox -> dev -> wheel -> passwordless sudo -> root.
#   Mitigated by default sandbox-on, journald launch logging, operator awareness.
{ config, lib, pkgs, ... }:
let
  cfg = config.services.agentCompute;
  agentCfg = config.tsurf.agent;
in
{
  options.services.agentCompute.enable = lib.mkEnableOption "Agent CLI tools (claude, codex, pi, zmx)";

  config = lib.mkIf cfg.enable {
  # @decision: zmx pre-built static binary from zmx.sh (a zig2nix flake build
  #   fails under apparmor-restricted user namespaces). Exposed via pkgs overlay
  #   so all modules use one canonical zmx derivation.
  nixpkgs.overlays = [
    (final: prev: {
      zmx = final.stdenv.mkDerivation rec {
        pname = "zmx";
        version = "0.3.0";
        src = final.fetchurl {
          url = "https://zmx.sh/a/zmx-${version}-linux-x86_64.tar.gz";
          hash = "sha256-/K/xWB61pqPll4Gq13qMoGm0Q1vC/sQT3TI7RaTf3zI=";
        };
        sourceRoot = ".";
        installPhase = ''
          runHook preInstall
          install -m755 -D zmx $out/bin/zmx
          runHook postInstall
        '';
        meta = with final.lib; {
          description = "Session persistence for terminal processes";
          homepage = "https://github.com/neurosnap/zmx";
          platforms = [ "x86_64-linux" ];
        };
      };
    })
  ];

  # @decision SEC-116-01: Raw agent binaries (claude-code, codex, pi-coding-agent) are NOT
  #   installed in PATH. They are only accessible via sandboxed wrappers in agent-sandbox.nix
  #   which reference full store paths (AGENT_REAL_BINARY). This makes the sandbox launcher
  #   the enforcement boundary, not PATH priority.
  environment.systemPackages = [
    pkgs.zmx
  ];

  # Rootless Podman for sandboxed agent container workflows.
  # dockerCompat = false because virtualisation.docker.enable = true in docker.nix —
  # NixOS asserts they cannot coexist.
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
