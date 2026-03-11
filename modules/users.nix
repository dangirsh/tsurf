# modules/users.nix
# @decision SYS-01: dev with sudo (wheel) + docker group; mutableUsers=false, execWheelOnly=true
{ config, pkgs, ... }: {
  users.mutableUsers = false;

  users.users.dev = {
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
      # Bootstrap key — private overlay replaces this entire file with real users
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIac0b7Yb2yCJrPiWf+KJQJ1c7gwH7SgHTiadSSUH0tM bootstrap-key"
    ];
  };

  # Passwordless sudo for wheel — no interactive password was set for dev.
  # Public template: allows eval without shipping real SSH keys/password hashes.
  # Replace placeholder keys above for real deployments.
  users.allowNoPasswordLogin = true;
  security.sudo.wheelNeedsPassword = false;
  security.sudo.execWheelOnly = true;
}
