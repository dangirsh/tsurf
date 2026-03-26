# extras/home/default.nix
# Home-manager profile for the dedicated agent user: git, ssh, gh, and direnv defaults.
# Private overlays replace the placeholder git identity and typically layer an agent-focused base profile here.
{
  config,
  lib,
  pkgs,
  ...
}:
{
  # Default to agent user; the alt-agent fixture overrides these via home-manager config.
  home.username = lib.mkDefault "agent";
  home.homeDirectory = lib.mkDefault "/home/agent";
  home.stateVersion = "25.11";
  programs.home-manager.enable = true;

  imports = [
    # Private overlay: add agentic-dev-base and project-specific home modules here.
  ];

  # Inlined from git.nix — private overlay replaces with real identity.
  # Set your git identity here, or override in your private overlay's home/default.nix.
  programs.git = {
    enable = true;
    settings.user.name = "Your Name";
    settings.user.email = "your@email.com";
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
    enableDefaultConfig = false;
    matchBlocks."*" = {
      controlMaster = "auto";
      controlPersist = "10m";
      hashKnownHosts = true;
      serverAliveInterval = 60;
    };
  };
  services.ssh-agent.enable = true;

  # Inlined from direnv.nix
  programs.direnv = {
    enable = true;
    enableBashIntegration = true;
    nix-direnv.enable = true;
  };
}
