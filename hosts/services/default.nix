# hosts/services/default.nix — services host (e.g. Contabo VPS)
# Role: runs long-lived services (containers, backups, file sync, dashboard).
# Imports restic.nix for backups and omits agent-sandbox.nix by default.
# Private overlay adds personal service modules, real user config, and host networking.
{ config, pkgs, inputs, lib, ... }: {
  imports = [
    ../hardware.nix
    ../disko-config.nix
    # Core modules
    ../../modules/base.nix
    ../../modules/boot.nix
    ../../modules/users.nix
    ../../modules/networking.nix
    ../../modules/secrets.nix
    ../../extras/syncthing.nix
    ../../modules/impermanence.nix
    ../../modules/break-glass-ssh.nix
    ../../extras/restic.nix
    ../../extras/dashboard.nix
    ../../extras/cost-tracker.nix
    # Private overlay: add personal service modules (nginx, etc.) here
  ];

  home-manager.users.dev = import ../../extras/home;

  networking.hostName = "tsurf";
  time.timeZone = "Europe/Berlin";
  i18n.defaultLocale = "C.UTF-8";

  # Static IP config is host-specific — set in your private overlay or directly here.
  networking.useDHCP = false;

  # --- Host-specific shared module settings ---
  boot.loader.grub.device = "/dev/sda";
  sops.defaultSopsFile = ../../secrets/tsurf.yaml;

  # Contabo VPS uses scripted networking for static IP, not systemd-networkd
  networking.useNetworkd = lib.mkForce false;

  services.syncthingStarter.enable = true;

  services.dashboard.enable = true;
  system.stateVersion = "25.11";
}
