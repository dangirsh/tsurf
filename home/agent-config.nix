# home/agent-config.nix
# @decision AGENT-01, AGENT-02: ~/.claude and ~/.codex symlinked to agentic-dev-base
# agentic-dev-base is the shared agent development environment (skills, hooks, CLAUDE.md, etc.)
# cloned by modules/repos.nix activation script.
{ config, lib, ... }: {
  home.file.".claude".source =
    config.lib.file.mkOutOfStoreSymlink "/data/projects/agentic-dev-base";

  home.file.".codex".source =
    config.lib.file.mkOutOfStoreSymlink "/data/projects/agentic-dev-base";
}
