# home/beads.nix
{ pkgs, ... }:
let
  br = pkgs.callPackage ../packages/beads.nix {};
in
{
  home.packages = [ br ];
}
