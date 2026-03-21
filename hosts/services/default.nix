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
    ../../modules/docker.nix
    ../../modules/syncthing.nix
    ../../modules/impermanence.nix
    ../../modules/break-glass-ssh.nix
    ../../modules/sshd-liveness-check.nix
    ../../modules/restic.nix
    ../../modules/dashboard.nix
    ../../modules/cost-tracker.nix
    # Private overlay: add personal service modules (nginx, etc.) here
  ];

  home-manager.users.dev = import ../../home;

  networking.hostName = "tsurf";
  time.timeZone = "Europe/Berlin";
  i18n.defaultLocale = "C.UTF-8";

  # Static IP config is host-specific — set in your private overlay or directly here.
  networking.useDHCP = false;

  # --- Host-specific shared module settings ---
  boot.loader.grub.device = "/dev/sda";
  networking.nat.externalInterface = "eth0";
  sops.defaultSopsFile = ../../secrets/tsurf.yaml;

  # Contabo VPS uses scripted networking for static IP, not systemd-networkd
  networking.useNetworkd = lib.mkForce false;

  # WARNING: Template mode — replace keys and disable this flag before deploying.
  # See SECURITY.md.
  tsurf.template.allowUnsafePlaceholders = true;
  services.dockerStarter.enable = true;
  services.syncthingStarter.enable = true;

  services.dashboard.enable = true;
  system.stateVersion = "25.11";
}
