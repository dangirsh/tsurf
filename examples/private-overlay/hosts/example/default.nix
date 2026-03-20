# hosts/example/default.nix
# REPLACE with your real hardware and host-specific settings.
{ inputs, ... }: {
  imports = [
    # REPLACE with your own hardware config.
    "${inputs.tsurf}/hosts/hardware.nix"
    "${inputs.tsurf}/hosts/disko-config.nix"
    ../../modules/janitor.nix

    # After configuring Tailscale and SSH host keys, import:
    # "${inputs.tsurf}/modules/networking.nix"
    # "${inputs.tsurf}/modules/secrets.nix"  # after creating encrypted secrets file
    # "${inputs.tsurf}/modules/sshd-liveness-check.nix"
  ];

  networking.hostName = "example-REPLACE";
  time.timeZone = "UTC"; # REPLACE
  i18n.defaultLocale = "C.UTF-8";

  # Required host-specific settings for boot + NAT.
  boot.loader.grub.device = "/dev/sda"; # REPLACE
  networking.nat.externalInterface = "eth0"; # REPLACE

  # When you import secrets.nix, set:
  # sops.defaultSopsFile = ../../secrets/example.yaml;

  services.dashboard.enable = true;
  # Agentic janitor requires:
  # 1. sops secret "anthropic-api-key" (import secrets.nix or declare manually)
  # 2. nono.nix in commonModules (already added)
  # Optional: services.janitor.model = "claude-sonnet-4-20250514";
  # Optional: override services.janitor.systemPrompt for custom cleanup logic.
  services.janitor.enable = true;

  system.stateVersion = "25.11";
}
