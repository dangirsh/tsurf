{ config, pkgs, ... }: {
  home.username = "dev";
  home.homeDirectory = "/home/dev";
  home.stateVersion = "25.11";
  programs.home-manager.enable = true;

  imports = [
    ./bash.nix
    ./cass.nix
    # Private overlay: add agentic-dev-base.nix, project-specific git config, etc.
  ];

  # Inlined from git.nix
  programs.git = {
    enable = true;
    userName = "Your Name";
    userEmail = "your@email.com";
  };

  programs.gh = {
    enable = true;
    # Do NOT set settings -- breaks gh auth due to read-only config.yml symlink
    # Auth uses GH_TOKEN env var from bash.nix initExtra
  };

  # Inlined from ssh.nix
  programs.ssh = {
    enable = true;
    controlMaster = "auto";
    controlPersist = "10m";
    serverAliveInterval = 60;
    hashKnownHosts = true;
  };

  # Inlined from direnv.nix
  programs.direnv = {
    enable = true;
    enableBashIntegration = true;
    nix-direnv.enable = true;
  };
}
