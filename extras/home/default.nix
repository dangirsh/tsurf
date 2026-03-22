{ config, pkgs, ... }: {
  home.username = "dev";
  home.homeDirectory = "/home/dev";
  home.stateVersion = "25.11";
  programs.home-manager.enable = true;

  imports = [
    # Private overlay: add cass.nix, agentic-dev-base.nix, project-specific git config, etc.
  ];

  # Inlined from git.nix — private overlay replaces with real identity.
  # Set your git identity here, or override in your private overlay's home/default.nix.
  programs.git = {
    enable = true;
    userName = "Your Name";
    userEmail = "your@email.com";
    # Recommended: add signing config if you use SSH commit signing:
    #   signing.key = "~/.ssh/id_ed25519.pub";
    #   signing.signByDefault = true;
    #   extraConfig.gpg.format = "ssh";
  };

  programs.gh = {
    enable = true;
    # Do NOT set settings -- breaks gh auth due to read-only config.yml symlink
    # Auth uses GH_TOKEN env var (set in shell profile or via sops-nix)
  };

  # Inlined from ssh.nix
  programs.ssh = {
    enable = true;
    controlMaster = "auto";
    controlPersist = "10m";
    serverAliveInterval = 60;
    hashKnownHosts = true;
  };
  services.ssh-agent.enable = true;

  # Inlined from direnv.nix
  programs.direnv = {
    enable = true;
    enableBashIntegration = true;
    nix-direnv.enable = true;
  };
}
