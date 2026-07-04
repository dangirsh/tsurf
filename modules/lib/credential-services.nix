{ lib }:

let
  # Well-known credential service defaults shared by nono and Iron credential
  # proxy wiring.
  credentialServiceDefaults = {
    anthropic = {
      upstream = "https://api.anthropic.com";
      hosts = [ "*.anthropic.com" ];
      injectHeader = "x-api-key";
      matchHeaders = [ "x-api-key" ];
      credentialFormat = "{}";
      envVar = "ANTHROPIC_API_KEY";
      secretName = "anthropic-api-key";
    };
    openai = {
      upstream = "https://api.openai.com";
      hosts = [ "api.openai.com" ];
      injectHeader = "authorization";
      matchHeaders = [ "authorization" ];
      credentialFormat = "Bearer {}";
      envVar = "OPENAI_API_KEY";
      secretName = "openai-api-key";
    };
    openrouter = {
      upstream = "https://openrouter.ai/api/v1";
      hosts = [ "openrouter.ai" ];
      injectHeader = "authorization";
      matchHeaders = [ "authorization" ];
      credentialFormat = "Bearer {}";
      envVar = "OPENROUTER_API_KEY";
      secretName = "openrouter-api-key";
    };
    xai = {
      upstream = "https://api.x.ai";
      hosts = [ "api.x.ai" ];
      injectHeader = "authorization";
      matchHeaders = [ "authorization" ];
      credentialFormat = "Bearer {}";
      envVar = "XAI_API_KEY";
      secretName = "xai-api-key";
    };
  };

  credentialDefaultsFor =
    agentDef: svc:
    credentialServiceDefaults.${svc}
    // lib.filterAttrs (_: value: value != null) (agentDef.credentialOverrides.${svc} or { });

  ironProxyTokenNameFor =
    svc: defaults:
    "TSURF_IRON_TOKEN_${lib.toUpper (builtins.replaceStrings [ "-" ] [ "_" ] svc)}_${defaults.envVar}";

  urlHost =
    url:
    let
      match = builtins.match "https?://([^/:]+).*" url;
    in
    if match == null then url else builtins.elemAt match 0;
in
{
  inherit
    credentialDefaultsFor
    credentialServiceDefaults
    ironProxyTokenNameFor
    urlHost
    ;
}
