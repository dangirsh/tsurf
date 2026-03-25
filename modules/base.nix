{ lib, pkgs, ... }:
{
  nixpkgs.config.allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) [
    "claude-code"
  ];

  # @decision SYS-02: declarative-only enforcement — no imperative package management.
  nix.channel.enable = false;
  nix.nixPath = lib.mkForce [];
  environment.defaultPackages = lib.mkForce [];

  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    auto-optimise-store = true;
    # @decision SEC-124-01: Restrict Nix daemon access to root and wheel group.
    #   trusted-users is root-only (overrides srvos @wheel default) to prevent
    #   wheel users from adding arbitrary substituters or signing keys at runtime.
    allowed-users = [ "root" "@wheel" ];
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

  # @decision SEC-17-01: Standard Linux server kernel hardening via sysctl
  boot.kernel.sysctl = {
    "kernel.dmesg_restrict" = 1;
    "kernel.kptr_restrict" = 2;
    "kernel.unprivileged_bpf_disabled" = 1;
    "net.core.bpf_jit_harden" = 2;
    "net.ipv4.conf.all.accept_redirects" = false;
    "net.ipv4.conf.default.accept_redirects" = false;
    "net.ipv4.conf.all.send_redirects" = false;
    "net.ipv6.conf.all.accept_redirects" = false;
    "net.ipv6.conf.default.accept_redirects" = false;
    "net.ipv4.conf.all.log_martians" = true;
  };

  # @decision SEC-153-01: Disable coredumps — no diagnostic value on headless agent servers,
  #   prevents leaking in-memory secrets to disk.
  systemd.coredump.enable = false;

  # @decision SEC-153-02: Prevent kexec-based kernel replacement (rootkit vector).
  security.protectKernelImage = true;

  # srvos installs: gitMinimal, curl, dnsutils, htop, jq, tmux.
  # We add full git (for agents) and search/transfer tools. Project-specific
  # deps are declared in each project's flake.nix, not here.
  environment.systemPackages = with pkgs; [
    git       # full git (srvos ships gitMinimal; agents need full features)
    rsync     # file transfer for backups and deploys
    ripgrep   # fast code search (agent tooling)
    fd        # fast file finder (agent tooling)
  ];

  # --- srvos overrides ---
  srvos.server.docs.enable = false;
  programs.command-not-found.enable = false;
  # srvos enables systemd initrd by default; we need script-based initrd for BTRFS rollback
  boot.initrd.systemd.enable = lib.mkForce false;
}
