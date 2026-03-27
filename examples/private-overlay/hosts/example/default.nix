# hosts/example/default.nix
# REPLACE with your real hardware and host-specific settings.
#
# User model: root (operator) + agent (sandboxed tools).
# Run `nix run .#tsurf-init -- --overlay-dir .` in the private overlay to create modules/root-ssh.nix.
{ inputs, ... }:
{
  imports = [
    # REPLACE with your own hardware config.
    "${inputs.tsurf}/hosts/hardware.nix"
    "${inputs.tsurf}/hosts/disko-config.nix"
    # Optional private-only modules belong here.
    # Example: a custom agent using the generic launcher (see modules/code-review.nix)

    # After configuring Tailscale/headscale and SSH host keys, import:
    # "${inputs.tsurf}/modules/networking.nix"
    # "${inputs.tsurf}/modules/secrets.nix"  # after creating encrypted secrets file
  ];

  networking.hostName = "example-REPLACE";
  time.timeZone = "UTC"; # REPLACE
  i18n.defaultLocale = "C.UTF-8";

  # Required host-specific settings for boot + NAT.
  boot.loader.grub.device = "/dev/sda"; # REPLACE
  networking.nat.externalInterface = "eth0"; # REPLACE

  # Optional extras:
  # tsurf.headscale.enable = true;       # Self-hosted Tailscale control plane (services host)
  # tsurf.headscale.domain = "hs.example.com";
  # tsurf.headscale.baseDomain = "ts.net";  # MagicDNS suffix for machine names
  # tsurf.headscale.publicIPv4 = "YOUR_PUBLIC_IP";
  # tsurf.headscale.acmeEmail = "admin@example.com";
  # services.codexAgent.enable = true;
  # services.cassIndexer.enable = true;
  # Home Manager profile for the agent user (opt-in):
  # home-manager.users.agent = import "${inputs.tsurf}/extras/home";
  # tsurf.headscale.enable = true;       # Self-hosted Tailscale control plane (services host)
  # tsurf.headscale.domain = "hs.example.com";
  # tsurf.headscale.baseDomain = "ts.net";  # MagicDNS suffix for machine names
  # tsurf.headscale.publicIPv4 = "YOUR_PUBLIC_IP";
  # tsurf.headscale.acmeEmail = "admin@example.com";

  # When you import secrets.nix, set:
  # sops.defaultSopsFile = ../../secrets/example.yaml;

  system.stateVersion = "25.11";
}
