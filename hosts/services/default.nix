# hosts/services/default.nix — example services host
# Role: runs long-lived services (containers, backups, file sync).
# Imports restic.nix for backups and omits agent-sandbox.nix by default.
# Private overlay replaces this with real host config, user settings, and networking.
{
  config,
  pkgs,
  inputs,
  lib,
  ...
}:
{
  imports = [
    ../hardware.nix
    ../disko-config.nix
    # Core modules
    ../../modules/base.nix
    ../../modules/boot.nix
    ../../modules/users.nix
    ../../modules/networking.nix
    ../../modules/secrets.nix
    ../../modules/impermanence.nix
    # Example extra (opt-in; enable with services.resticStarter.enable = true)
    ../../extras/restic.nix
    # Private overlay: add personal service modules (nginx, etc.) here
  ];

  networking.hostName = "services"; # REPLACE in private overlay
  time.timeZone = "UTC"; # REPLACE
  i18n.defaultLocale = "C.UTF-8";

  # Static IP config is host-specific — set in your private overlay or directly here.
  networking.useDHCP = false;

  # --- Host-specific shared module settings ---
  boot.loader.grub.device = "/dev/sda"; # REPLACE
  sops.defaultSopsFile = ../../secrets/example.yaml; # REPLACE with per-host secrets

  # Use scripted networking for static IP, not systemd-networkd
  networking.useNetworkd = lib.mkForce false;

  system.stateVersion = "25.11";
}
