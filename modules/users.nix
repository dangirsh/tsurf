# modules/users.nix
# @decision SYS-01: dangirsh with sudo (wheel) + docker group
{ config, pkgs, ... }: {
  users.users.dangirsh = {
    isNormalUser = true;
    extraGroups = [ "wheel" "docker" ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIac0b7Yb2yCJrPiWf+KJQJ1c7gwH7SgHTiadSSUH0tM dan@worldcoin.org"
    ];
  };

  # Root SSH access: keep during initial deployment for recovery.
  # Remove after confirming dangirsh SSH + sudo works (Plan 02).
  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIac0b7Yb2yCJrPiWf+KJQJ1c7gwH7SgHTiadSSUH0tM dan@worldcoin.org"
  ];
}
