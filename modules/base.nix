{ config, lib, pkgs, ... }: {
  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    auto-optimise-store = true;
  };

  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 30d";
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
    tmux
    btop
    nodejs
  ];

  programs.ssh.startAgent = true;
}
