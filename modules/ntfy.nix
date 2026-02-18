# modules/ntfy.nix
# @decision NTFY-01: Run ntfy on a dedicated local port with Tailscale-only reachability.
# @decision NTFY-02: Use write-only default access so local services can publish without tokens.
{ config, pkgs, ... }: {
  services.ntfy-sh = {
    enable = true;
    settings = {
      listen-http = ":2586";
      base-url = "http://localhost:2586";
      behind-proxy = false;
      # write-only: safe because ntfy is Tailscale-only (not in allowedTCPPorts). All internal services POST without auth tokens.
      auth-default-access = "write-only";
      cache-file = "/var/lib/ntfy-sh/cache.db";
      cache-duration = "24h";

      # SMTP delivery (future):
      # smtp-sender-addr = "smtp.example.com:587";
      # smtp-sender-user = "ntfy@example.com";
      # smtp-sender-from = "ntfy@example.com";
      # Configure `services.ntfy-sh.environmentFile` with SMTP password, e.g.
      # NTFY_SMTP_SENDER_PASS=...
    };

    # Example for future SMTP secret wiring:
    # environmentFile = config.sops.secrets."ntfy-smtp-password".path;
  };
}
