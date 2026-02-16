# home/cass.nix
# @decision SVC-03: CASS indexer as oneshot systemd user timer, every 30 minutes
{ config, pkgs, ... }:
let
  cass = pkgs.callPackage ../packages/cass.nix {};
in
{
  home.packages = [ cass ];

  systemd.user.services.cass-indexer = {
    Unit.Description = "CASS agent session indexer";
    Service = {
      Type = "oneshot";
      ExecStart = "${cass}/bin/cass index --full";
      Environment = [ "HOME=/home/dangirsh" ];
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
