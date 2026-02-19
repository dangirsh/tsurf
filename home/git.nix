{ config, pkgs, ... }: {
  programs.git = {
    enable = true;
    userName = "Dan Girshovich";
    userEmail = "dan.girshovich@gmail.com";
  };

  programs.gh = {
    enable = true;
    # Do NOT set settings -- breaks gh auth due to read-only config.yml symlink
    # Auth uses GH_TOKEN env var from bash.nix initExtra
  };
}
