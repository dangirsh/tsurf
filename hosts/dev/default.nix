# hosts/dev/default.nix — example agent/dev host
# Role: agent development and sandboxed execution via agent-sandbox.nix + nono.nix.
# Private overlays provide real host config, repo lists, and agent fleet wiring.
{
  lib,
  ...
}:
{
  imports = [
    ../hardware.nix
    ../disko-config.nix
    # Shared modules
    ../../modules/base.nix
    ../../modules/boot.nix
    ../../modules/users.nix
    ../../modules/networking.nix
    ../../modules/secrets.nix
    ../../modules/agent-compute.nix
    ../../modules/agent-egress-proxy.nix
    ../../modules/impermanence.nix
    ../../modules/agent-launcher.nix
    ../../modules/agent-sandbox.nix
    ../../modules/nono.nix
    # Additional extras and host-specific workflows belong in a private overlay.
  ];

  networking.hostName = "dev"; # REPLACE in private overlay
  time.timeZone = "UTC"; # REPLACE
  i18n.defaultLocale = "C.UTF-8";

  networking.useDHCP = true;

  # --- Host-specific shared module settings ---
  boot.loader.grub.device = "/dev/sda"; # REPLACE
  sops.defaultSopsFile = ../../tests/fixtures/sops-placeholder.yaml; # REPLACE with per-host encrypted secrets

  # @decision DEV-01: Port 22 open on public interface for bootstrap and deploy access.
  # Template hosts may not have Tailscale/headscale up on first boot, so SSH stays public initially.
  # Key-only auth enforced by networking.nix. fail2ban is disabled (SEC83-01).
  services.openssh.openFirewall = lib.mkForce true;

  services.agentCompute.enable = true;
  services.agentEgressProxy.enable = true;
  services.agentSandbox.enable = true;
  services.nonoSandbox.enable = true;

  networking.useNetworkd = lib.mkForce false;

  system.stateVersion = "26.11";
}
