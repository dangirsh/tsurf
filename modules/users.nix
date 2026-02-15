{ config, pkgs, ... }: {
  users.users.dangirsh = {
    isNormalUser = true;
    extraGroups = [ "wheel" "docker" ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIac0b7Yb2yCJrPiWf+KJQJ1c7gwH7SgHTiadSSUH0tM dan@worldcoin.org"
    ];
  };

  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIac0b7Yb2yCJrPiWf+KJQJ1c7gwH7SgHTiadSSUH0tM dan@worldcoin.org"
  ];
}
