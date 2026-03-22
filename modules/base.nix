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
    # @decision SEC-124-01: Restrict Nix daemon access to root and wheel group.
    #   Agent user is excluded by default — added conditionally via agent-sandbox.nix
    #   when allowNixDaemon is enabled. trusted-users is root-only (no @wheel) to prevent
    #   wheel users from adding arbitrary substituters or signing keys at runtime.
    allowed-users = [ "root" "@wheel" ];
    trusted-users = [ "root" ];
    # Numtide: llm-agents overlay (claude-code, codex, etc.)
    # Private overlay: add your own Cachix binary cache.
    # After creating a cache at https://app.cachix.org, add:
    #   "https://your-cache.cachix.org"
    # And add the corresponding public key to extra-trusted-public-keys:
    #   "your-cache.cachix.org-1:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="
    # Then in scripts/deploy-post.sh, push closures after deploy:
    #   nix path-info --recursive /nix/var/nix/profiles/system | cachix push your-cache
    extra-substituters = [
      "https://cache.numtide.com"
    ];
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
    nodejs    # @decision SEC47-19: agent tooling (Claude Code, npm-based tools)
  ];

  programs.ssh.startAgent = true;

  # --- srvos overrides (shared across all hosts) ---
  # Agents don't need man pages or command-not-found suggestions
  srvos.server.docs.enable = false;
  programs.command-not-found.enable = false;

  # Operator convenience (opt-in for human sessions, not needed for agents):
  #   environment.systemPackages = [ pkgs.btop ];
  #   srvos.server.docs.enable = true;
  #   programs.command-not-found.enable = true;
  # Guard against future srvos enabling systemd initrd
  boot.initrd.systemd.enable = lib.mkForce false;
}
