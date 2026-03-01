{ config, lib, pkgs, ... }:
{
  nixpkgs.config.allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) [
    "claude-code"
  ];

  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    auto-optimise-store = true;
    # Private overlay: add your personal binary cache here to speed up private derivation builds.
    # substituters = [ "https://your-cache.cachix.org" ];
    # trusted-public-keys = [ "your-cache.cachix.org-1:..." ];
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
    rsync
    jq
    yq-go
    ripgrep
    fd
    btop
    nodejs    # @decision SEC47-19: agent tooling (Claude Code, npm-based tools)
    cachix    # @decision SEC47-20: deploy.sh post-deploy Cachix push step
  ];

  programs.ssh.startAgent = true;
}
