{ config, pkgs, ... }: {
  programs.tmux = {
    enable = true;
    mouse = true;
    terminal = "screen-256color";
    historyLimit = 50000;
  };
}
