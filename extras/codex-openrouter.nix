# extras/codex-openrouter.nix
# Optional: OpenRouter-backed Codex CLI through the generic sandboxed launcher.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.codexOpenRouterAgent;
  agentCfg = config.tsurf.agent;
  codexHome = "${agentCfg.home}/.codex-openrouter";

  codexChild = pkgs.writeShellApplication {
    name = "${cfg.wrapperName}-child";
    text = ''
      : "''${NONO_PROXY_TOKEN:?missing nono proxy token}"
      : "''${OPENROUTER_BASE_URL:?missing OpenRouter proxy base URL}"

      exec ${cfg.package}/bin/codex \
        -m ${lib.escapeShellArg cfg.model} \
        -c ${lib.escapeShellArg "model_provider=\"${cfg.providerId}\""} \
        -c ${lib.escapeShellArg "model_providers.${cfg.providerId}.name=\"${cfg.providerName}\""} \
        -c "model_providers.${cfg.providerId}.base_url=\"$OPENROUTER_BASE_URL\"" \
        -c ${lib.escapeShellArg "model_providers.${cfg.providerId}.wire_api=\"responses\""} \
        -c ${lib.escapeShellArg "model_providers.${cfg.providerId}.env_key=\"NONO_PROXY_TOKEN\""} \
        "$@"
    '';
  };
in
{
  options.services.codexOpenRouterAgent = {
    enable = lib.mkEnableOption "OpenRouter-backed Codex CLI with nono sandbox";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.codex;
      description = "Codex package to expose through the OpenRouter-backed sandboxed wrapper.";
    };

    wrapperName = lib.mkOption {
      type = lib.types.strMatching "[A-Za-z0-9._-]+";
      default = "codex-openrouter";
      description = "Name of the OpenRouter-backed Codex wrapper installed in PATH.";
    };

    model = lib.mkOption {
      type = lib.types.str;
      default = "z-ai/glm-5.2";
      description = "Default OpenRouter model for unattended Codex subagents.";
    };

    providerId = lib.mkOption {
      type = lib.types.strMatching "[A-Za-z_][A-Za-z0-9_]*";
      default = "openrouter";
      description = "Codex model provider id used in per-invocation config.";
    };

    providerName = lib.mkOption {
      type = lib.types.str;
      default = "OpenRouter";
      description = "Human-readable Codex provider name.";
    };

    baseUrl = lib.mkOption {
      type = lib.types.str;
      default = "https://openrouter.ai/api/v1";
      description = "OpenRouter OpenAI-compatible upstream base URL used by the nono credential proxy.";
    };

    secretName = lib.mkOption {
      type = lib.types.str;
      default = "openrouter-api-key";
      description = "sops secret name containing the OpenRouter API key.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = config.services.agentLauncher.enable;
        message = "extras/codex-openrouter.nix: services.agentLauncher.enable must be true";
      }
      {
        assertion = config.services.nonoSandbox.enable;
        message = "extras/codex-openrouter.nix: services.nonoSandbox.enable must be true";
      }
      {
        assertion = builtins.hasAttr cfg.secretName config.sops.secrets;
        message = "extras/codex-openrouter.nix: sops.secrets.${cfg.secretName} must be declared";
      }
    ];

    services.agentLauncher.agents.${cfg.wrapperName} = {
      command = "${cfg.wrapperName}-child";
      package = codexChild;
      wrapperName = cfg.wrapperName;
      credentialServices = [ "openrouter" ];
      credentialOverrides.openrouter = {
        upstream = cfg.baseUrl;
        secretName = cfg.secretName;
      };
      childEnvironment.CODEX_HOME = codexHome;
      nonoProfile.extraAllow = [ codexHome ];
      nonoProfile.extraAllowFile = [
        "/proc/sys/kernel/overflowuid"
        "/proc/sys/kernel/overflowgid"
      ];
      persistence.directories = [ ".codex-openrouter" ];
    };

    systemd.tmpfiles.rules = [ "d ${codexHome} 0700 ${agentCfg.user} ${agentCfg.user} -" ];
  };
}
