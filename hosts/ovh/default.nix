{ config, inputs, lib, pkgs, ... }: {
  imports = [
    ./hardware.nix
    ./disko-config.nix
    ../../modules
    # nginx module moved to private overlay
  ];

  networking.hostName = "neurosys-prod";
  time.timeZone = "Europe/Berlin";
  i18n.defaultLocale = "C.UTF-8";

  # OVH uses DHCP for static assignment.
  networking.useDHCP = true;

  # --- Host-specific shared module settings ---
  boot.loader.grub.device = "/dev/sda";
  networking.nat.externalInterface = "ens3";
  sops.defaultSopsFile = ../../secrets/ovh.yaml;
  sops.age.sshKeyPaths = [ "/persist/etc/ssh/ssh_host_ed25519_key" ];

  # @decision OVH-01: Port 22 open on public interface for bootstrap and deploy access.
  # OVH VPS has no Tailscale pre-installed; SSH must be public until Tailscale is up.
  # fail2ban provides brute-force protection. Key-only auth enforced by networking.nix.
  services.openssh.openFirewall = lib.mkForce true;

  # @decision OVH-02: Explicit hostKeys path points directly to /persist/ to avoid
  # impermanence mount timing races on first boot. The etc-ssh.mount unit mounts
  # /persist/etc/ssh/ over /etc/ssh/, but if sshd starts before the mount completes,
  # it fails with "no such file". By pointing sshd directly at /persist/etc/ssh/,
  # we bypass sshd_config entirely — nixos-anywhere always places the host key there.
  services.openssh.hostKeys = lib.mkForce [
    { type = "ed25519"; path = "/persist/etc/ssh/ssh_host_ed25519_key"; }
  ];

  # --- srvos overrides ---
  networking.useNetworkd = lib.mkForce false;
  srvos.server.docs.enable = true;
  programs.command-not-found.enable = true;
  boot.initrd.systemd.enable = lib.mkForce false;

  system.stateVersion = "25.11";
}
