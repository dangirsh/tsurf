# extras/cass.nix
# Low-priority CASS indexing as a system timer for the dedicated agent user.
# This keeps session search warm without depending on user lingering or an interactive shell.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.cassIndexer;
  agentCfg = config.tsurf.agent;
  cass = pkgs.stdenv.mkDerivation rec {
    pname = "cass";
    version = "0.1.64";
    src = pkgs.fetchurl {
      url = "https://github.com/Dicklesworthstone/coding_agent_session_search/releases/download/v${version}/cass-linux-amd64.tar.gz";
      hash = "sha256-bqMZQO9wKGtZjtNeZlqyDTt0JKOuNvqSs+oBC8pQkWU=";
    };
    nativeBuildInputs = [ pkgs.autoPatchelfHook ];
    buildInputs = [
      pkgs.stdenv.cc.cc.lib
      pkgs.openssl
      pkgs.zlib
    ];
    sourceRoot = ".";
    installPhase = ''
      runHook preInstall
      install -m755 -D cass $out/bin/cass
      runHook postInstall
    '';
    meta = with pkgs.lib; {
      description = "Unified CLI/TUI to index and search coding agent session history";
      homepage = "https://github.com/Dicklesworthstone/coding_agent_session_search";
      platforms = [ "x86_64-linux" ];
    };
  };
  cassIndex = pkgs.writeShellScript "tsurf-cass-index" ''
    set -euo pipefail
    if ${cass}/bin/cass health --json >/dev/null 2>&1; then
      exit 0
    fi
    exec ${cass}/bin/cass index --full
  '';
in
{
  options.services.cassIndexer.enable = lib.mkEnableOption "CASS session indexer timer";

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ cass ];

    systemd.services.tsurf-cass-index = {
      description = "tsurf CASS session indexer";
      serviceConfig = {
        Type = "oneshot";
        User = agentCfg.user;
        Group = agentCfg.user;
        WorkingDirectory = agentCfg.home;
        Environment = [
          "HOME=${agentCfg.home}"
          "CASS_DATA_DIR=${agentCfg.home}/.local/share/coding-agent-search"
          "CODING_AGENT_SEARCH_NO_UPDATE_PROMPT=1"
          "TUI_HEADLESS=1"
        ];
        ExecStart = cassIndex;
        Nice = 10;
        IOSchedulingClass = "idle";
        CPUQuota = "25%";
        MemoryMax = "512M";
        TimeoutStartSec = "1h";
        UMask = "0077";
        NoNewPrivileges = true;
        PrivateTmp = true;
        RestrictAddressFamilies = [ "AF_UNIX" ];
        LockPersonality = true;
        RestrictNamespaces = true;
        SystemCallArchitectures = "native";
        CapabilityBoundingSet = "";
      };
    };

    systemd.timers.tsurf-cass-index = {
      description = "Refresh the tsurf CASS search index";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "hourly";
        RandomizedDelaySec = "15m";
        Persistent = true;
      };
    };

    environment.persistence."/persist".directories = [
      "${agentCfg.home}/.local/share/coding-agent-search"
    ];
  };
}
