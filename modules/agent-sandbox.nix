# modules/agent-sandbox.nix
# Claude agent declaration on top of the generic agent launcher.
# @decision SANDBOX-73-01: Public core exposes one sandboxed Claude wrapper. Additional
#   wrappers build on the same generic launcher infrastructure.
# @decision LAUNCHER-152-02: Agents must not deploy changes to their own security boundaries.
#   Enforced by operational policy, not technical controls.
# @decision SEC-145-04: Claude-level deny rules provide defense-in-depth atop Landlock.
#   enableAllProjectMcpServers=false prevents malicious repos from injecting MCP servers.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.agentSandbox;
  agentCfg = config.tsurf.agent;
in
{
  options.services.agentSandbox = {
    enable = lib.mkEnableOption "sandboxed Claude wrapper for the dedicated agent user";

    projectRoot = lib.mkOption {
      type = lib.types.str;
      default = config.tsurf.agent.projectRoot;
      description = "Root directory for sandboxed agent execution. PWD must be inside this path.";
    };
  };

  config = lib.mkIf cfg.enable {
    services.agentLauncher.enable = true;
    services.agentLauncher.projectRoot = cfg.projectRoot;

    services.agentLauncher.agents.claude = {
      command = "claude";
      package = pkgs.claude-code;
      wrapperName = "claude";
      credentials = [ "anthropic:ANTHROPIC_API_KEY:anthropic-api-key" ];
      nonoProfile = {
        extraAllow = [
          "${agentCfg.home}/.claude"
          "${agentCfg.home}/.config/claude"
        ];
        extraAllowFile = [
          "${agentCfg.home}/.claude.json"
          "${agentCfg.home}/.claude.json.lock"
        ];
      };

      managedSettings = {
        permissions = {
          deny = [
            "Read(/run/secrets/**)"
            "Read(${agentCfg.home}/.ssh/**)"
            "Read(/etc/nono/**)"
            "Read(.env)"
            "Read(.envrc)"
            "Edit(.git/hooks/**)"
            "Edit(.envrc)"
            "Edit(.env)"
            "Edit(.mcp.json)"
            "Edit(.devcontainer/**)"
          ];
        };
        enableAllProjectMcpServers = false;
      };

      persistence.directories = [
        ".claude"
        ".config/claude"
        ".config/git"
        ".local/share/direnv"
      ];
      persistence.files = [
        ".gitconfig"
        ".bash_history"
      ];
    };
  };
}
