# extras/codex.nix
# Optional: Codex CLI sandboxed through the generic agent launcher.
# Requires: services.agentLauncher.enable = true and services.nonoSandbox.enable = true.
{ config, lib, pkgs, ... }:
let
  cfg = config.services.codexAgent;
  agentCfg = config.tsurf.agent;
  codexHome = "${agentCfg.home}/.codex-openai";
in
{
  options.services.codexAgent = {
    enable = lib.mkEnableOption "Codex CLI with nono sandbox";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.codex;
      description = "Codex package to expose through the sandboxed wrapper.";
    };

    credentialServices = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "openai" ];
      description = "Credential service names for nono's built-in reverse proxy (e.g., openai).";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = config.services.agentLauncher.enable;
        message = "extras/codex.nix: services.agentLauncher.enable must be true";
      }
      {
        assertion = config.services.nonoSandbox.enable;
        message = "extras/codex.nix: services.nonoSandbox.enable must be true";
      }
    ];

    services.agentLauncher.agents.codex = {
      command = "codex";
      package = cfg.package;
      wrapperName = "codex";
      credentialServices = cfg.credentialServices;
      childEnvironment.CODEX_HOME = codexHome;
      nonoProfile.extraAllow = [ codexHome ];
      persistence.directories = [ ".codex-openai" ];
    };

    systemd.tmpfiles.rules = [
      "d ${codexHome} 0700 ${agentCfg.user} ${agentCfg.user} -"
    ];
  };
}
