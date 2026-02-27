# modules/users.nix
# @decision SYS-01: myuser with sudo (wheel) + docker group; mutableUsers=false, execWheelOnly=true
{ config, pkgs, ... }: {
  users.mutableUsers = false;

  users.users.myuser = {
    isNormalUser = true;
    extraGroups = [ "wheel" "docker" ];
    subUidRanges = [{ startUid = 100000; count = 65536; }];
    subGidRanges = [{ startGid = 100000; count = 65536; }];
    openssh.authorizedKeys.keys = [
      # Replace with your SSH public key
    ];
  };

  users.users.root = {
    openssh.authorizedKeys.keys = [
      # Replace with your SSH public key
    ];
  };

  # Passwordless sudo for wheel — no interactive password was set for myuser.
  security.sudo.wheelNeedsPassword = false;
  security.sudo.execWheelOnly = true;
}
