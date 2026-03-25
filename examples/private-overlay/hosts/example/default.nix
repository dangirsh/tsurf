# hosts/example/default.nix
# REPLACE with your real hardware and host-specific settings.
#
# User model: root (operator) + agent (sandboxed tools).
# Root SSH key is the bootstrap step — replace the placeholder in users.nix.
{ inputs, ... }: {
  imports = [
    # REPLACE with your own hardware config.
    "${inputs.tsurf}/hosts/hardware.nix"
    "${inputs.tsurf}/hosts/disko-config.nix"
    # Optional private-only modules belong here.
    # Example: a custom agent using the generic launcher (see modules/code-review.nix)

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

  # Bootstrap: add your real SSH key for root access.
  # This replaces the placeholder key in modules/users.nix.
  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAA... your-key-REPLACE"
  ];

  # Enable the unattended dev-agent (optional, requires secrets):
  # services.devAgent = {
  #   enable = true;
  #   workingDirectory = "/data/projects/my-workspace";
  #   prompt = "Continue the highest-value task you can verify locally.";
  # };

  # When you import secrets.nix, set:
  # sops.defaultSopsFile = ../../secrets/example.yaml;

  system.stateVersion = "25.11";
}
