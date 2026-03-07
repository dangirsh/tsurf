{ lib, pkgs, ... }:
{
  nixpkgs.config.allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) [
    "claude-code"
  ];

  # @decision SYS-02: declarative-only enforcement — no imperative package management.
  # nix-channel is removed so `nix-env` cannot resolve packages by channel name.
  # NIX_PATH is explicitly cleared as belt-and-suspenders.
  # defaultPackages is emptied so nothing lands on the system outside of a Nix declaration.
  nix.channel.enable = false;
  nix.nixPath = lib.mkForce [];
  environment.defaultPackages = lib.mkForce [];

  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    auto-optimise-store = true;
    # @decision CACHE-66: Binary caches for faster builds.
    # Numtide: llm-agents overlay (claude-code, codex, etc.)
    # dan-testing: own Cachix cache pushed by deploy.sh after each successful deploy.
    extra-substituters = [
      "https://cache.numtide.com"
      "https://dan-testing.cachix.org"
    ];
    extra-trusted-public-keys = [
      "niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g="
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
