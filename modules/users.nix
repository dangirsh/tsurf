# modules/users.nix
# @decision SYS-01: dangirsh with sudo (wheel) + docker group; mutableUsers=false, execWheelOnly=true
{ config, pkgs, ... }: {
  users.mutableUsers = false;

  users.users.dangirsh = {
    isNormalUser = true;
    extraGroups = [ "wheel" "docker" ];
    subUidRanges = [{ startUid = 100000; count = 65536; }];
    subGidRanges = [{ startGid = 100000; count = 65536; }];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIac0b7Yb2yCJrPiWf+KJQJ1c7gwH7SgHTiadSSUH0tM dan@worldcoin.org"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAqNVObi1HflLIV/FkO/rAz/ABdTvADidl5tuIulS3WE parts-agent@vm"
    ];
  };

  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIac0b7Yb2yCJrPiWf+KJQJ1c7gwH7SgHTiadSSUH0tM dan@worldcoin.org"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAqNVObi1HflLIV/FkO/rAz/ABdTvADidl5tuIulS3WE parts-agent@vm"
  ];

  # Passwordless sudo for wheel — no interactive password was set for dangirsh.
  security.sudo.wheelNeedsPassword = false;
  security.sudo.execWheelOnly = true;
}
