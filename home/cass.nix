# home/cass.nix
# @decision SVC-03: CASS indexer as oneshot systemd user timer, every 30 minutes
# @decision SVC-03: CASS pre-built binary from GitHub, patched with autoPatchelfHook. Inlined from packages/cass.nix.
{ config, pkgs, ... }:
let
  cass = pkgs.stdenv.mkDerivation rec {
    pname = "cass";
    version = "0.1.64";
    src = pkgs.fetchurl {
      url = "https://github.com/Dicklesworthstone/coding_agent_session_search/releases/download/v${version}/cass-linux-amd64.tar.gz";
      hash = "sha256-bqMZQO9wKGtZjtNeZlqyDTt0JKOuNvqSs+oBC8pQkWU=";
    };
    nativeBuildInputs = [ pkgs.autoPatchelfHook ];
    buildInputs = [ pkgs.stdenv.cc.cc.lib pkgs.openssl pkgs.zlib ];
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
in
{
  home.packages = [ cass ];

  systemd.user.services.cass-indexer = {
    Unit.Description = "CASS agent session indexer";
    Service = {
      Type = "oneshot";
      ExecStart = "${cass}/bin/cass index --full";
      Environment = [ "HOME=/home/dev" ];
    };
  };

  systemd.user.timers.cass-indexer = {
    Unit.Description = "Run CASS indexer every 30 minutes";
    Timer = {
      OnCalendar = "*:00/30";
      Persistent = true;
    };
    Install.WantedBy = [ "timers.target" ];
  };
}
