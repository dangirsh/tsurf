# modules/spacebot.nix
# @decision SPB-01: Run via Docker slim image (ghcr.io/spacedriveapp/spacebot:slim) rather than
#   building from source — avoids 30+ min Rust + React build on every nixos-rebuild.
#   Upstream publishes signed images on each release. Switch to flake input for native build.
# @decision SPB-02: Port 19898 bound to localhost only; Tailscale-only access enforced by
#   internalOnlyPorts assertion in networking.nix.
# @decision SPB-03: Reuses existing anthropic-api-key sops secret — no duplicate key needed.
#   LLM key injected via env template so it never appears in config.toml or the Nix store.
# @decision SPB-04: openFirewall = false (Docker port binding enforces localhost-only).
# @decision SPB-05: Model routing set in config.toml [agents.routing], not via env vars.
#   SPACEBOT_MODEL env var does not override per-agent routing when config.toml is present.
#   The config.toml on the volume is the source of truth for model selection.
#
# --- Optional: add messaging tokens before first deploy ---
# To enable Discord:  sops secrets/neurosys.yaml  (add discord-bot-token)
#   Then add to secrets.nix: sops.secrets."discord-bot-token" = {};
#   And add DISCORD_BOT_TOKEN to the sops.templates block below.
#   Restart the container; entrypoint appends messaging sections if the token is present
#   but ONLY on first boot (config.toml already exists — edit it directly for messaging).
# Same pattern for Telegram (telegram-bot-token -> TELEGRAM_BOT_TOKEN + TELEGRAM_CHAT_ID).
#
# --- config.toml (lives at /var/lib/spacebot/config.toml on the server) ---
# Auto-generated on first start; never regenerated. Current content:
#   [agents.routing]  channel/branch/cortex = anthropic/claude-sonnet-4-6
#                     worker/compactor     = anthropic/claude-haiku-4-5-20251001
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
  };
}
