# extras/opencode.nix
# Optional: opencode AI coding assistant with nono sandbox.
# Registers opencode as a sandboxed agent via the brokered launch model (SEC-119-01).
# Requires: services.agentSandbox.enable = true (modules/agent-sandbox.nix).
#
# Usage: import this module, then set services.opencodeAgent.enable = true.
# Override the package via services.opencodeAgent.package if opencode is available
# in your nixpkgs (pkgs.opencode) or to pin a specific version.
#
# To find the correct hash for a new version:
#   nix store prefetch-file "https://github.com/sst/opencode/releases/download/vVERSION/opencode-linux-x64"
{ config, lib, pkgs, ... }:
let
  cfg = config.services.opencodeAgent;

  defaultPackage = pkgs.stdenv.mkDerivation rec {
    pname = "opencode";
    version = "0.1.125"; # bump version + update hash together
    src = pkgs.fetchurl {
      url = "https://github.com/sst/opencode/releases/download/v${version}/opencode-linux-x64";
      # Replace with the actual hash:
      #   nix store prefetch-file "https://github.com/sst/opencode/releases/download/v${version}/opencode-linux-x64"
      hash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
    };
    nativeBuildInputs = [ pkgs.autoPatchelfHook ];
    buildInputs = [ pkgs.stdenv.cc.cc.lib ];
    dontUnpack = true;
    installPhase = ''
      runHook preInstall
      install -m755 -D $src $out/bin/opencode
      runHook postInstall
    '';
    meta = with lib; {
      description = "AI coding assistant";
      homepage = "https://opencode.ai";
      platforms = [ "x86_64-linux" ];
    };
  };
in
{
  options.services.opencodeAgent = {
    enable = lib.mkEnableOption "opencode AI coding assistant with nono sandbox";

    package = lib.mkOption {
      type = lib.types.package;
      default = defaultPackage;
      description = ''
        opencode package to use. Override with pkgs.opencode if available in your nixpkgs,
        or provide a custom derivation pinned to a specific version.
      '';
    };

    credentials = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "anthropic:ANTHROPIC_API_KEY:anthropic-api-key" "openai:OPENAI_API_KEY:openai-api-key" ];
      description = ''
        Credential triples for nono proxy injection (SERVICE:ENV_VAR:secret-file-name).
        Only triples whose secrets exist in /run/secrets/ are activated at runtime.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [{
      assertion = config.services.agentSandbox.enable;
      message = "extras/opencode.nix: services.agentSandbox.enable must be true";
    }];

    services.agentSandbox.extraAgents = [{
      name = "opencode";
      package = cfg.package;
      binary = "opencode";
      credentials = cfg.credentials;
    }];
  };
}
