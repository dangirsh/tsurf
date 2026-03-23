# hosts/dev/default.nix — example agent/dev host
# Role: agent development and sandboxed execution via agent-sandbox.nix + nono.nix.
# Clone-repos helper script is available at extras/scripts/clone-repos.sh for private overlays.
# Private overlay replaces this with real host config, repo lists, and agent fleet wiring.
{ config, inputs, lib, pkgs, ... }: {
  imports = [
    ../hardware.nix
    ../disko-config.nix
    # Shared modules
    ../../modules/base.nix
    ../../modules/boot.nix
    ../../modules/users.nix
    ../../modules/networking.nix
    ../../modules/secrets.nix
    ../../extras/syncthing.nix
    ../../modules/agent-compute.nix
    ../../modules/impermanence.nix
    ../../modules/break-glass-ssh.nix
    ../../extras/dashboard.nix
    ../../modules/agent-sandbox.nix
    ../../modules/nono.nix
    # Optional extras belong in a private overlay.
  ];

  home-manager.users.dev = import ../../extras/home;

  networking.hostName = "dev"; # REPLACE in private overlay
  time.timeZone = "UTC"; # REPLACE
  i18n.defaultLocale = "C.UTF-8";

  networking.useDHCP = true;

  # --- Host-specific shared module settings ---
  boot.loader.grub.device = "/dev/sda"; # REPLACE
  sops.defaultSopsFile = ../../secrets/example.yaml; # REPLACE with per-host secrets
  sops.age.sshKeyPaths = [ "/persist/etc/ssh/ssh_host_ed25519_key" ];

  # @decision DEV-01: Port 22 open on public interface for bootstrap and deploy access.
  # Template hosts may not have Tailscale up on first boot, so SSH stays public initially.
  # Key-only auth enforced by networking.nix. fail2ban is disabled (SEC83-01).
  services.openssh.openFirewall = lib.mkForce true;

  # @decision DEV-02: Explicit hostKeys path points directly to /persist/ to avoid
  # impermanence mount timing races on first boot. The etc-ssh.mount unit mounts
  # /persist/etc/ssh/ over /etc/ssh/, but if sshd starts before the mount completes,
  # it fails with "no such file". By pointing sshd directly at /persist/etc/ssh/,
  # we bypass sshd_config entirely — nixos-anywhere always places the host key there.
  services.openssh.hostKeys = lib.mkForce [
    { type = "ed25519"; path = "/persist/etc/ssh/ssh_host_ed25519_key"; }
  ];

  services.syncthingStarter.enable = true;
  services.agentCompute.enable = true;
  services.agentSandbox.enable = true;
  services.nonoSandbox.enable = true;

  networking.useNetworkd = lib.mkForce false;

  system.stateVersion = "25.11";
}
