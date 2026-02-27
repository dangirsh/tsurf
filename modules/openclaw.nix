# modules/openclaw.nix
# OpenClaw — self-hosted AI assistant with WhatsApp/messaging integrations
# Four isolated instances: mark (public), lou (Tailscale), alexia (Tailscale), ari (public)
#
# @decision OCL-01: Explicit per-instance declarations rather than parametric function.
# @rationale: Exactly 4 instances with distinct visibility rules (nginx vs Tailscale).
#   Copy-paste clarity beats abstraction for a fixed, small set.
#
# @decision OCL-02: Use official ghcr.io image (not local tarball or pkgs.dockerTools).
# @rationale: OpenClaw publishes multi-arch images to ghcr.io/openclaw/openclaw:latest.
#   virtualisation.oci-containers pulls automatically on nixos-rebuild switch.
#   No image pre-loading needed; updates are a simple image tag bump + rebuild.
#
# @decision OCL-03: Container internal port is always 18789; host port varies via -p mapping.
# @rationale: OpenClaw's --port flag sets the listener inside the container. Docker port
#   mapping translates host:18789-18792 -> container:18789 per instance.
#
# @decision OCL-04: Bridge port not exposed on host.
# @rationale: Bridge is for local claude-code access within the container network.
#   Not needed when instances are accessed via gateway (HTTP/WebSocket).
#
# @decision OCL-05: openclaw.json seeded via activation script (automaton.nix pattern).
# @rationale: Config written only if absent — preserves user edits across rebuilds.
#   gateway.mode must be "local" for self-hosted operation.
#
# @decision OCL-06: State dirs use 0777 tmpfiles permissions.
# @rationale: Container runs as UID 1000 (node user). No host user maps to UID 1000.
#   World-writable dir is simplest working approach. Document as known limitation.

{ config, pkgs, ... }:

let
  # Default openclaw.json configuration — seeded on first activation only.
  # Users can edit the file on the server; it will not be overwritten on rebuild.
  mkOpenclawConfig = user: model: builtins.toJSON {
    gateway = {
      mode = "local";
      port = 18789;
    };
    model = model;
    user = user;
  };

  openclawConfigMark    = pkgs.writeText "openclaw-mark.json"    (mkOpenclawConfig "mark" "anthropic/claude-opus-4-6");
  openclawConfigLou     = pkgs.writeText "openclaw-lou.json"     (mkOpenclawConfig "lou" "anthropic/claude-opus-4-6");
  openclawConfigAlexia  = pkgs.writeText "openclaw-alexia.json"  (mkOpenclawConfig "alexia" "anthropic/claude-opus-4-6");
  openclawConfigAri     = pkgs.writeText "openclaw-ari.json"     (mkOpenclawConfig "ari" "anthropic/claude-opus-4-6");
in {

  # --- Sops templates: env files with secrets (one per instance) ---

  sops.templates."openclaw-mark-env" = {
    content = ''
      OPENCLAW_GATEWAY_TOKEN=${config.sops.placeholder."openclaw-mark-gateway-token"}
      ANTHROPIC_API_KEY=${config.sops.placeholder."anthropic-api-key"}
    '';
    owner = "root";
    mode = "0400";
  };

  sops.templates."openclaw-lou-env" = {
    content = ''
      OPENCLAW_GATEWAY_TOKEN=${config.sops.placeholder."openclaw-lou-gateway-token"}
      ANTHROPIC_API_KEY=${config.sops.placeholder."anthropic-api-key"}
    '';
    owner = "root";
    mode = "0400";
  };

  sops.templates."openclaw-alexia-env" = {
    content = ''
      OPENCLAW_GATEWAY_TOKEN=${config.sops.placeholder."openclaw-alexia-gateway-token"}
      ANTHROPIC_API_KEY=${config.sops.placeholder."anthropic-api-key"}
    '';
    owner = "root";
    mode = "0400";
  };

  sops.templates."openclaw-ari-env" = {
    content = ''
      OPENCLAW_GATEWAY_TOKEN=${config.sops.placeholder."openclaw-ari-gateway-token"}
      ANTHROPIC_API_KEY=${config.sops.placeholder."anthropic-api-key"}
    '';
    owner = "root";
    mode = "0400";
  };

  # --- State directories with permissions for container UID 1000 ---

  systemd.tmpfiles.rules = [
    "d /var/lib/openclaw-mark    0777 root root -"
    "d /var/lib/openclaw-lou     0777 root root -"
    "d /var/lib/openclaw-alexia  0777 root root -"
    "d /var/lib/openclaw-ari     0777 root root -"
  ];

  # --- Activation script: seed openclaw.json for each instance ---

  system.activationScripts.openclaw-state = {
    text = ''
      # Seed openclaw.json for each instance (only if absent — preserves user edits)
      for pair in "mark:${openclawConfigMark}" "lou:${openclawConfigLou}" "alexia:${openclawConfigAlexia}" "ari:${openclawConfigAri}"; do
        user="''${pair%%:*}"
        config_file="''${pair#*:}"
        state_dir="/var/lib/openclaw-''${user}"
        mkdir -p "''${state_dir}"
        if [ ! -f "''${state_dir}/openclaw.json" ]; then
          cp "''${config_file}" "''${state_dir}/openclaw.json"
          chmod 0666 "''${state_dir}/openclaw.json"
          echo "openclaw: seeded openclaw.json for ''${user}"
        fi
      done
    '';
    deps = [ "setupSecrets" ];
  };

  # --- Container declarations ---

  # mark: public HTTPS via nginx (bind to loopback)
  virtualisation.oci-containers.containers.openclaw-mark = {
    image = "ghcr.io/openclaw/openclaw:latest";
    volumes = [ "/var/lib/openclaw-mark:/home/node/.openclaw" ];
    ports = [ "127.0.0.1:18789:18789" ];
    environmentFiles = [ config.sops.templates."openclaw-mark-env".path ];
    cmd = [ "node" "openclaw.mjs" "gateway" "--allow-unconfigured" ];
  };

  # lou: Tailscale-only (bind to all interfaces; nftables trustedInterfaces restricts access)
  virtualisation.oci-containers.containers.openclaw-lou = {
    image = "ghcr.io/openclaw/openclaw:latest";
    volumes = [ "/var/lib/openclaw-lou:/home/node/.openclaw" ];
    ports = [ "18790:18789" ];
    environmentFiles = [ config.sops.templates."openclaw-lou-env".path ];
    cmd = [ "node" "openclaw.mjs" "gateway" "--allow-unconfigured" ];
  };

  # alexia: Tailscale-only (bind to all interfaces; nftables trustedInterfaces restricts access)
  virtualisation.oci-containers.containers.openclaw-alexia = {
    image = "ghcr.io/openclaw/openclaw:latest";
    volumes = [ "/var/lib/openclaw-alexia:/home/node/.openclaw" ];
    ports = [ "18791:18789" ];
    environmentFiles = [ config.sops.templates."openclaw-alexia-env".path ];
    cmd = [ "node" "openclaw.mjs" "gateway" "--allow-unconfigured" ];
  };

  # ari: public HTTPS via nginx (bind to loopback)
  virtualisation.oci-containers.containers.openclaw-ari = {
    image = "ghcr.io/openclaw/openclaw:latest";
    volumes = [ "/var/lib/openclaw-ari:/home/node/.openclaw" ];
    ports = [ "127.0.0.1:18792:18789" ];
    environmentFiles = [ config.sops.templates."openclaw-ari-env".path ];
    cmd = [ "node" "openclaw.mjs" "gateway" "--allow-unconfigured" ];
  };
}
