{ config, pkgs, inputs, lib, ... }: {
  imports = [
    ./hardware.nix
    ./disko-config.nix
    ../../modules
    ../../modules/openclaw.nix
    # Contabo-only services
    ../../modules/homepage.nix
    ../../modules/restic.nix
    ../../modules/sun-schedule.nix
    # nginx module moved to private overlay
  ];

  networking.hostName = "neurosys";
  time.timeZone = "Europe/Berlin";
  i18n.defaultLocale = "C.UTF-8";

  # Static IP config is host-specific — set in your private overlay or directly here.
  networking.useDHCP = false;

  # --- Host-specific shared module settings ---
  boot.loader.grub.device = "/dev/sda";
  networking.nat.externalInterface = "eth0";
  sops.defaultSopsFile = ../../secrets/neurosys.yaml;

  # --- srvos overrides ---
  # Contabo VPS uses scripted networking for static IP, not systemd-networkd
  networking.useNetworkd = lib.mkForce false;
  # Dev server: agents and humans need man pages and --help
  srvos.server.docs.enable = true;
  # Helpful for interactive sessions
  programs.command-not-found.enable = true;
  # srvos does not set this today, but mkForce guards against a future srvos
  # release enabling systemd initrd before Phase 21 is ready
  boot.initrd.systemd.enable = lib.mkForce false;

  system.stateVersion = "25.11";
}
