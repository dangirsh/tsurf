# extras/pi.nix
# Optional: pi coding agent sandboxed through the shared brokered launch model.
# Requires: services.agentSandbox.enable = true (modules/agent-sandbox.nix)
# and services.nonoSandbox.enable = true (modules/nono.nix).
# @decision SEC-127-EXTRAS-01: Optional extra-agent persistence derives from
#   tsurf.agent.home, not a literal /home/agent path.
{ config, lib, pkgs, ... }:
let
  cfg = config.services.piAgent;
  agentHome = config.tsurf.agent.home;
  devHome = config.users.users.dev.home;
in
{
  options.services.piAgent = {
    enable = lib.mkEnableOption "pi coding agent with nono sandbox";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.pi-coding-agent;
      description = "pi package to expose through the sandboxed wrapper.";
    };

    credentials = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "anthropic:ANTHROPIC_API_KEY:anthropic-api-key" ];
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
        message = "extras/pi.nix: services.agentSandbox.enable must be true";
      }
      {
        assertion = config.services.nonoSandbox.enable;
        message = "extras/pi.nix: services.nonoSandbox.enable must be true";
      }
    ];

    services.agentSandbox.extraAgents = [{
      name = "pi";
      package = cfg.package;
      binary = "pi";
      credentials = cfg.credentials;
    }];

    services.nonoSandbox.extraAllow = [
      "${agentHome}/.pi"
      "${agentHome}/.pi/agent"
    ];

    services.nonoSandbox.extraAllowFile = [
      "${agentHome}/.pi/agent/auth.json"
      "${agentHome}/.pi/agent/settings.json"
    ];

    environment.persistence."/persist".directories = [
      "${devHome}/.pi"
      "${agentHome}/.pi"
    ];
  };
}
