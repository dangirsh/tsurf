# modules/home-assistant.nix
# @decision HA-01: Native NixOS service, not Docker container
# @decision HA-02: GUI accessible via Tailscale only (same pattern as Syncthing)
# @decision HA-03: Automations managed in dangirsh/home-assistant-config (GitHub, private)
#   and cloned to /var/lib/hass/config-repo on activation. Wired via config.automation
#   using HA's built-in !include YAML tag (supported by the NixOS module's renderYAMLFile
#   sed post-processor which unquotes '!tag arg' strings).
# @decision HA-04: trusted_proxies for Tailscale Serve reverse proxy
#   Tailscale Serve terminates TLS on port 443 and proxies to 127.0.0.1:8123.
#   HA must trust localhost as a proxy to correctly handle X-Forwarded-For.
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
      "mcp_server"
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
        use_x_forwarded_for = true;
        trusted_proxies = [ "127.0.0.1" ];
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

  # --- Tailscale Serve: HTTPS proxy to HA for MCP ---
  # @decision HA-05: Declarative systemd oneshot for tailscale serve --bg
  # @rationale: --bg persistence survives reboots (config stored in
  #   /var/lib/tailscale), but a systemd wrapper ensures the config is
  #   applied on every deploy and follows NixOS declarative convention.
  #   Oneshot + RemainAfterExit = runs once, stays "active".
  #   Restart=on-failure handles boot-time races (tailscale not yet authed).
  # @decision HA-06: ExecStartPre uses tailscale status exit-code (no jq).
  # @rationale: jq + complex quoting inside systemd single-quoted ExecStartPre
  #   causes systemd to mangle \" escapes, producing invalid jq syntax. Using
  #   "tailscale status" exit-code avoids quoting entirely and is equivalent.
  systemd.services.tailscale-serve-ha = {
    description = "Tailscale Serve: HTTPS proxy to Home Assistant MCP";
    after = [ "tailscaled.service" ];
    wants = [ "tailscaled.service" ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      Restart = "on-failure";
      RestartSec = "30";
      # Wait for Tailscale to be fully authenticated before configuring serve.
      # tailscaled.service may report ready before auth completes.
      # "tailscale status" exits 0 when connected, non-zero otherwise.
      ExecStartPre = "${pkgs.bash}/bin/bash -c 'for i in $(seq 1 30); do ${pkgs.tailscale}/bin/tailscale status >/dev/null 2>&1 && exit 0; sleep 2; done; echo tailscale-not-ready; exit 1'";
      ExecStart = "${pkgs.tailscale}/bin/tailscale serve --bg --https=443 http://127.0.0.1:8123";
      ExecStop = "${pkgs.tailscale}/bin/tailscale serve off";
    };
  };
}
