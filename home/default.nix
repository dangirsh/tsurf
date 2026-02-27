{ config, pkgs, ... }: {
  home.username = "myuser";
  home.homeDirectory = "/home/myuser";
  home.stateVersion = "25.11";
  programs.home-manager.enable = true;

  imports = [
    ./bash.nix
    ./git.nix
    ./ssh.nix
    ./direnv.nix
    ./cass.nix
    ./beads.nix
    ./agent-config.nix
  ];
}
