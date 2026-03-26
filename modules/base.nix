# modules/base.nix
# Shared base system settings: Nix daemon policy, minimal host packages, and nix-mineral hardening.
# The public core keeps the host lean and expects per-project tooling to come from project flakes.
{
  config,
  lib,
  pkgs,
  ...
}:
{
  nixpkgs.config.allowUnfreePredicate =
    pkg:
    builtins.elem (lib.getName pkg) [
      "claude-code"
    ];

  # @decision SYS-02: declarative-only enforcement — no imperative package management.
  nix.channel.enable = false;
  nix.nixPath = lib.mkForce [ ];
  environment.defaultPackages = lib.mkForce [ ];

  nix.settings = {
    experimental-features = [
      "nix-command"
      "flakes"
    ];
    auto-optimise-store = true;
    # @decision SEC-124-01: Restrict Nix daemon access to root and the dedicated agent user.
    # trusted-users stays root-only so agents cannot add substituters or signing keys at runtime.
    allowed-users = [
      "root"
      config.tsurf.agent.user
    ];
    trusted-users = lib.mkForce [ "root" ];
    extra-substituters = [ "https://cache.numtide.com" ];
    extra-trusted-public-keys = [
      "niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g="
    ];
  };

  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 30d";
  };

  systemd.coredump.enable = false;
  boot.kernel.sysctl."kernel.core_pattern" = lib.mkForce "|/bin/false";

  # @decision SEC-145-05: nix-mineral provides kernel/mount/entropy/debug hardening (~80 settings).
  #   Compatibility preset with agent-workload overrides. Replaces manual sysctl hardening.
  nix-mineral.enable = true;
  nix-mineral.preset = "compatibility";

  # Agent-workload overrides beyond compatibility preset defaults:
  nix-mineral.settings.kernel.cpu-mitigations = "smt-on"; # VPS: hypervisor controls SMT
  nix-mineral.settings.kernel.slab-debug = false; # Performance: heavy alloc overhead
  nix-mineral.settings.etc.generic-machine-id = false; # Conflicts with impermanence /persist
  nix-mineral.settings.misc.dnssec = false; # services.resolved.settings absent in nixos-25.11
  nix-mineral.filesystems.enable = false; # Conflicts with impermanence neededForBoot

  # srvos installs: gitMinimal, curl, dnsutils, htop, jq, tmux.
  # We add full git (for agents) and search/transfer tools. Project-specific
  # deps are declared in each project's flake.nix, not here.
  environment.systemPackages = with pkgs; [
    git # full git (srvos ships gitMinimal; agents need full features)
    rsync # file transfer for backups and deploys
    ripgrep # fast code search (agent tooling)
    fd # fast file finder (agent tooling)
  ];

  # --- srvos overrides ---
  srvos.server.docs.enable = false;
  programs.command-not-found.enable = false;
  # srvos enables systemd initrd by default; we need script-based initrd for BTRFS rollback
  boot.initrd.systemd.enable = lib.mkForce false;
}
