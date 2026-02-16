# home/agent-config.nix
# @decision AGENT-01, AGENT-02: ~/.claude and ~/.codex symlinked to global-agent-conf
{ config, lib, ... }: {
  home.file.".claude".source =
    config.lib.file.mkOutOfStoreSymlink "/data/projects/global-agent-conf";

  home.file.".codex".source =
    config.lib.file.mkOutOfStoreSymlink "/data/projects/global-agent-conf";
}
