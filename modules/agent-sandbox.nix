# modules/agent-sandbox.nix
# Claude agent declaration on top of the generic agent launcher.
# @decision SANDBOX-73-01: Public core exposes one sandboxed Claude wrapper. Additional
#   wrappers build on the same generic launcher infrastructure.
# @decision LAUNCHER-152-02: Agents must not deploy changes to their own security boundaries.
#   Enforced by operational policy, not technical controls.
# @decision SEC-145-04: Claude-level deny rules provide defense-in-depth atop Landlock.
#   enableAllProjectMcpServers=false prevents malicious repos from injecting MCP servers.
# @decision SEC-AGENT-AUTH-02: Do not grant Claude's raw auth/session cache
#   under ~/.claude, ~/.config/claude, or ~/.claude.json to prompt-controlled runs.
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
      credentialServices = [ "anthropic" ];

      managedSettings = {
        permissions = {
          deny = [
            "Read(/run/secrets/**)"
            "Read(${agentCfg.home}/.ssh/**)"
            "Read(${agentCfg.home}/.claude/**)"
            "Read(${agentCfg.home}/.config/claude/**)"
            "Read(${agentCfg.home}/.claude.json)"
            "Read(${agentCfg.home}/.claude.json.lock)"
            "Read(/etc/nono/**)"
            "Read(.env)"
            "Read(.envrc)"
            "Edit(.git/hooks/**)"
            "Edit(.envrc)"
            "Edit(.env)"
            "Edit(.mcp.json)"
            "Edit(.devcontainer/**)"
            "Edit(.github/workflows/**)"
            "Edit(.claude/**)"
          ];
        };
        enableAllProjectMcpServers = false;
      };

      persistence.directories = [
        ".config/git"
        ".local/share/direnv"
      ];
      persistence.files = [
        ".gitconfig"
      ];
    };
  };
}
