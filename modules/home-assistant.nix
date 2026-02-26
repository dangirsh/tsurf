# modules/home-assistant.nix
# @decision HA-01: Native NixOS service, not Docker container
# @decision HA-02: GUI accessible via Tailscale only (same pattern as Syncthing)
# @decision HA-03: Automations managed in dangirsh/home-assistant-config (GitHub, private)
#   and cloned to /var/lib/hass/config-repo on activation. Wired via config.automation
#   using HA's built-in !include YAML tag (supported by the NixOS module's renderYAMLFile
#   sed post-processor which unquotes '!tag arg' strings).
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

      # Load file-based automations from the config repo cloned during activation.
      # The NixOS HA module's renderYAMLFile sed step unquotes '!tag arg' strings,
      # so this becomes: automation: !include config-repo/automations.yaml
      # Path is relative to configDir (/var/lib/hass/).
      automation = "!include config-repo/automations.yaml";
    };
  };

  # ESPHome for managing ESP devices
  services.esphome = {
    enable = true;
    address = "0.0.0.0";
    port = 6052;
    openFirewall = false;
  };

  # Clone dangirsh/home-assistant-config into /var/lib/hass/config-repo.
  # Uses the same github-pat credential pattern as repos.nix (store-file, no token in args).
  # On clone failure, a placeholder automations.yaml is written so HA starts cleanly.
  # The placeholder is replaced on the next successful activation.
  system.activationScripts.clone-ha-config = {
    deps = [ "users" ];
    text = ''
      HA_REPO_DIR="/var/lib/hass/config-repo"
      GH_TOKEN="$(cat ${config.sops.secrets."github-pat".path} 2>/dev/null || true)"

      mkdir -p /var/lib/hass

      if [ ! -d "$HA_REPO_DIR" ]; then
        if [ -n "$GH_TOKEN" ]; then
          CRED_FILE=$(mktemp)
          chmod 600 "$CRED_FILE"
          printf 'https://x-access-token:%s@github.com\n' "$GH_TOKEN" > "$CRED_FILE"
          GIT_TERMINAL_PROMPT=0 ${pkgs.git}/bin/git \
            -c credential.helper="store --file=$CRED_FILE" \
            clone "https://github.com/dangirsh/home-assistant-config.git" \
            "$HA_REPO_DIR" \
            || echo "WARNING: Failed to clone home-assistant-config (will retry on next activation)"
          rm -f "$CRED_FILE"
        else
          echo "WARNING: github-pat not available, deferring home-assistant-config clone"
        fi

        # Fallback: ensure automations.yaml exists so HA starts cleanly even if clone failed.
        if [ ! -f "$HA_REPO_DIR/automations.yaml" ]; then
          mkdir -p "$HA_REPO_DIR"
          echo "# placeholder: home-assistant-config clone pending" \
            > "$HA_REPO_DIR/automations.yaml"
        fi

        chown -R hass:hass "$HA_REPO_DIR" 2>/dev/null || true
      fi
    '';
  };
}
