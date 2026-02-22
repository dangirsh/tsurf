# home/agent-config.nix
# @decision AGENT-01, AGENT-02: ~/.claude and ~/.codex symlinked to global-agent-conf
# @decision AGENT-03: disable-mouse.js deployed to ~/.local/lib for NODE_OPTIONS --require
{ config, lib, ... }: {
  home.file.".claude".source =
    config.lib.file.mkOutOfStoreSymlink "/data/projects/global-agent-conf";

  home.file.".codex".source =
    config.lib.file.mkOutOfStoreSymlink "/data/projects/global-agent-conf";

  home.file.".local/lib/disable-mouse.js".source = ../scripts/disable-mouse.js;
}
