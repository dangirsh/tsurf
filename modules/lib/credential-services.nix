{ lib }:

let
  # Well-known credential service defaults for Iron credential replacement.
  credentialServiceDefaults = {
    anthropic = {
      upstream = "https://api.anthropic.com";
      hosts = [ "*.anthropic.com" ];
      injectHeader = "x-api-key";
      matchHeaders = [ "x-api-key" ];
      envVar = "ANTHROPIC_API_KEY";
      secretName = "anthropic-api-key";
    };
    openai = {
      upstream = "https://api.openai.com";
      hosts = [ "api.openai.com" ];
      injectHeader = "authorization";
      matchHeaders = [ "authorization" ];
      envVar = "OPENAI_API_KEY";
      secretName = "openai-api-key";
    };
    openrouter = {
      upstream = "https://openrouter.ai/api/v1";
      hosts = [ "openrouter.ai" ];
      injectHeader = "authorization";
      matchHeaders = [ "authorization" ];
      envVar = "OPENROUTER_API_KEY";
      secretName = "openrouter-api-key";
    };
    xai = {
      upstream = "https://api.x.ai";
      hosts = [ "api.x.ai" ];
      injectHeader = "authorization";
      matchHeaders = [ "authorization" ];
      envVar = "XAI_API_KEY";
      secretName = "xai-api-key";
    };
  };

  credentialDefaultsFor =
    agentDef: svc:
    let
      overrides = lib.filterAttrs (_: value: value != null) (agentDef.credentialOverrides.${svc} or { });
      merged = credentialServiceDefaults.${svc} // overrides;
    in
    merged
    // lib.optionalAttrs (overrides ? upstream) {
      # Keep the Iron allowlist and secret-replacement rule aligned with a
      # caller-provided upstream instead of retaining the default host.
      hosts = [ (urlHost overrides.upstream) ];
    };

  credentialAuthorityFor = agentName: svc: defaults: {
    agent = agentName;
    service = svc;
    childEnvVar = defaults.envVar;
    secretName = defaults.secretName;
    upstream = defaults.upstream;
    hosts = lib.sort builtins.lessThan (lib.unique defaults.hosts);
    injectHeader = defaults.injectHeader;
    matchHeaders = lib.sort builtins.lessThan (lib.unique defaults.matchHeaders);
  };

  credentialAuthorityIdFor =
    agentName: svc: defaults:
    builtins.hashString "sha256" (builtins.toJSON (credentialAuthorityFor agentName svc defaults));

  ironProxyTokenNameFor =
    agentName: svc: defaults:
    "TSURF_IRON_TOKEN_${lib.toUpper (credentialAuthorityIdFor agentName svc defaults)}";

  ironProxySourceEnvVarFor =
    agentName: svc: defaults:
    "TSURF_IRON_SECRET_${lib.toUpper (credentialAuthorityIdFor agentName svc defaults)}";

  urlHost =
    url:
    let
      match = builtins.match "https?://([^/:]+).*" url;
    in
    if match == null then url else builtins.elemAt match 0;
in
{
  inherit
    credentialAuthorityFor
    credentialAuthorityIdFor
    credentialDefaultsFor
    credentialServiceDefaults
    ironProxySourceEnvVarFor
    ironProxyTokenNameFor
    urlHost
    ;
}
