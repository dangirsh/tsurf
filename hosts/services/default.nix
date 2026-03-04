{ config, pkgs, inputs, lib, ... }: {
  imports = [
    ./hardware.nix
    ./disko-config.nix
    # Shared modules (previously in modules/default.nix hub)
    ../../modules/base.nix
    ../../modules/boot.nix
    ../../modules/users.nix
    ../../modules/networking.nix
    ../../modules/secrets.nix
    ../../modules/docker.nix
    ../../modules/syncthing.nix
    ../../modules/agent-compute.nix
    ../../modules/secret-proxy.nix
    ../../modules/impermanence.nix
    # Host-specific services
    ../../modules/openclaw.nix
    ../../modules/homepage.nix
    ../../modules/restic.nix
    ../../modules/matrix.nix
    ../../modules/dm-guide.nix
    ../../modules/dashboard.nix
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

  services.dashboard.enable = true;

  system.stateVersion = "25.11";
}
