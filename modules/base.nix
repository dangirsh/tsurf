{ config, lib, pkgs, ... }:
let
  zmx = pkgs.callPackage ../packages/zmx.nix {};
in
{
  nixpkgs.config.allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) [
    "claude-code"
  ];

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
    zmx
    btop
    nodejs
  ];

  programs.ssh.startAgent = true;
}
