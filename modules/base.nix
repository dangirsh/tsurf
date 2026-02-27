{ config, lib, pkgs, ... }:
{
  nixpkgs.config.allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) [
    "claude-code"
  ];

  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    auto-optimise-store = true;
    # @decision CACHE-01: dan-testing.cachix.org as personal binary cache to speed up remote builds.
    # @rationale: Avoids recompiling custom derivations (dangirsh-site, parts, claw-swap) that are
    #   absent from cache.nixos.org. Push via `cachix push dan-testing` after local builds.
    substituters = [ "https://dan-testing.cachix.org" ];
    trusted-public-keys = [
      "dan-testing.cachix.org-1:3o+6K+4nP7KTTZobTF+bhC25LPIG4mDjd5wXegRIdQ4="
    ];
  };

  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 30d";
  };

  # @decision SEC-17-01: Standard Linux server kernel hardening via sysctl
  boot.kernel.sysctl = {
    "kernel.dmesg_restrict" = 1; # Restrict dmesg to root
    "kernel.kptr_restrict" = 2; # Hide kernel pointers from non-root
    "kernel.unprivileged_bpf_disabled" = 1; # Disable unprivileged eBPF
    "net.core.bpf_jit_harden" = 2; # Harden eBPF JIT compiler
    "net.ipv4.conf.all.accept_redirects" = false; # Prevent ICMP redirect MITM
    "net.ipv4.conf.default.accept_redirects" = false;
    "net.ipv4.conf.all.send_redirects" = false;
    "net.ipv6.conf.all.accept_redirects" = false;
    "net.ipv6.conf.default.accept_redirects" = false;
    "net.ipv4.conf.all.log_martians" = true; # Log suspicious packets
  };

  environment.systemPackages = with pkgs; [
    git
    curl
    wget
    rsync
    jq
    yq-go
    ripgrep
    fd
    btop
    nodejs
    cachix
  ];

  programs.ssh.startAgent = true;
}
