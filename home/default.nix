{ config, pkgs, ... }: {
  home.username = "dev";
  home.homeDirectory = "/home/dev";
  home.stateVersion = "25.11";
  programs.home-manager.enable = true;

  imports = [
    ./bash.nix
    ./git.nix
    ./ssh.nix
    ./direnv.nix
    ./cass.nix
    ./beads.nix
    ./agentic-dev-base.nix
  ];
}
