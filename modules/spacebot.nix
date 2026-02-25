# modules/spacebot.nix
# @decision SPB-01: Run via Docker slim image (ghcr.io/spacedriveapp/spacebot:slim) rather than
#   building from source — avoids 30+ min Rust + React build on every nixos-rebuild.
#   Upstream publishes signed images on each release. Switch to flake input for native build.
# @decision SPB-02: Port 19898 bound to localhost only; Tailscale-only access enforced by
#   internalOnlyPorts assertion in networking.nix.
# @decision SPB-03: Reuses existing anthropic-api-key sops secret — no duplicate key needed.
#   LLM key injected via env template so it never appears in config.toml or the Nix store.
# @decision SPB-04: openFirewall = false (Docker port binding enforces localhost-only).
#
# --- Optional: add messaging tokens before first deploy ---
# To enable Discord:  sops secrets/neurosys.yaml  (add discord-bot-token)
#   Then add to secrets.nix: sops.secrets."discord-bot-token" = {};
#   And uncomment the DISCORD_BOT_TOKEN line in the sops.templates block below.
# Same pattern for Telegram (telegram-bot-token -> TELEGRAM_BOT_TOKEN + TELEGRAM_CHAT_ID).
#
# --- First boot behaviour ---
# config.toml is auto-generated at /var/lib/spacebot/config.toml on first start.
# Edit it there for advanced model routing, agent definitions, etc.
# It is never regenerated once it exists.
{ config, ... }: {

  # Env file rendered from sops secrets at activation time.
  # anthropic-api-key is already declared in secrets.nix; reused here.
  # spacebot resolves "env:ANTHROPIC_API_KEY" references in config.toml at startup.
  sops.templates."spacebot-env" = {
    content = ''
      ANTHROPIC_API_KEY=${config.sops.placeholder."anthropic-api-key"}
    '';
    owner = "root";
    mode = "0400";
  };

  # Persistent data directory (config.toml, SQLite DB, LanceDB embeddings).
  # Owned by docker group so the container process can write as its default UID.
  systemd.tmpfiles.rules = [
    "d /var/lib/spacebot 0750 root docker -"
  ];

  virtualisation.oci-containers.containers.spacebot = {
    image = "ghcr.io/spacedriveapp/spacebot:slim";

    # /data is SPACEBOT_DIR inside the container
    volumes = [ "/var/lib/spacebot:/data" ];

    # Bind to localhost only — access via Tailscale at http://neurosys:19898
    ports = [ "127.0.0.1:19898:19898" ];

    environmentFiles = [ config.sops.templates."spacebot-env".path ];

    # Override default model names — upstream defaults to "claude-sonnet-4" which is 404.
    # Use the current API identifiers from Anthropic.
    environment = {
      SPACEBOT_CHANNEL_MODEL = "claude-sonnet-4-6";
      SPACEBOT_WORKER_MODEL = "claude-haiku-4-5-20251001";
    };
  };
}
