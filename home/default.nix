{ config, pkgs, ... }: {
  home.username = "dangirsh";
  home.homeDirectory = "/home/dangirsh";
  home.stateVersion = "25.11";
  programs.home-manager.enable = true;

  imports = [
    ./bash.nix
    ./tmux.nix
    ./git.nix
    ./ssh.nix
    ./direnv.nix
  ];
}
