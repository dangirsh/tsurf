# extras/codex.nix
# Optional: Codex CLI sandboxed through the shared brokered launch model.
# Requires: services.agentSandbox.enable = true (modules/agent-sandbox.nix)
# and services.nonoSandbox.enable = true (modules/nono.nix).
{ config, lib, pkgs, ... }:
let
  cfg = config.services.codexAgent;
in
{
  options.services.codexAgent = {
    enable = lib.mkEnableOption "Codex CLI with nono sandbox";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.codex;
      description = "Codex package to expose through the sandboxed wrapper.";
    };

    credentials = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "openai:OPENAI_API_KEY:openai-api-key" ];
      description = ''
        Credential triples for nono proxy injection (SERVICE:ENV_VAR:secret-file-name).
        Only triples whose secrets exist in /run/secrets/ are activated at runtime.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = config.services.agentSandbox.enable;
        message = "extras/codex.nix: services.agentSandbox.enable must be true";
      }
      {
        assertion = config.services.nonoSandbox.enable;
        message = "extras/codex.nix: services.nonoSandbox.enable must be true";
      }
    ];

    services.agentSandbox.extraAgents = [{
      name = "codex";
      package = cfg.package;
      binary = "codex";
      credentials = cfg.credentials;
    }];

    services.nonoSandbox.extraAllow = [
      "${config.tsurf.agent.home}/.codex"
    ];

    environment.persistence."/persist".directories = [
      "/home/dev/.codex"
      "/home/agent/.codex"
    ];
  };
}
