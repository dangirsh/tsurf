# modules/home-assistant.nix
# @decision HA-01: Native NixOS service, not Docker container
# @decision HA-02: GUI accessible via Tailscale only (same pattern as Syncthing)
#
# Security model:
# - Home Assistant listens on 0.0.0.0:8123 to avoid startup ordering issues with tailscale0.
# - Port 8123 is intentionally not in firewall.allowedTCPPorts.
# - tailscale0 is a trusted interface in networking.nix, so HA access is effectively tailnet-only.
{ config, pkgs, ... }: {
  services.home-assistant = {
    enable = true;
    openFirewall = false;

    extraComponents = [
      "hue"
      "esphome"
    ];

    config = {
      homeassistant = {
        name = "Home";
        unit_system = "metric";
        time_zone = "Europe/Berlin";
      };

      http = {
        server_host = "0.0.0.0";
        server_port = 8123;
      };

      default_config = {};
    };
  };

  # ESPHome for managing ESP devices
  services.esphome = {
    enable = true;
    address = "0.0.0.0";
    port = 6052;
    openFirewall = false;
  };
}
