# hosts/example/default.nix
# REPLACE with your real hardware and host-specific settings.
{ inputs, ... }: {
  imports = [
    # REPLACE with your own hardware config.
    "${inputs.tsurf}/hosts/hardware.nix"
    "${inputs.tsurf}/hosts/disko-config.nix"

    # After configuring Tailscale and SSH host keys, import:
    # "${inputs.tsurf}/modules/networking.nix"
    # "${inputs.tsurf}/modules/secrets.nix"  # after creating encrypted secrets file
  ];

  networking.hostName = "example-REPLACE";
  time.timeZone = "UTC"; # REPLACE
  i18n.defaultLocale = "C.UTF-8";

  # Required host-specific settings for boot + NAT.
  boot.loader.grub.device = "/dev/sda"; # REPLACE
  networking.nat.externalInterface = "eth0"; # REPLACE

  # When you import secrets.nix, set:
  # sops.defaultSopsFile = ../../secrets/example.yaml;

  services.dashboard.enable = true;

  system.stateVersion = "25.11";
}
