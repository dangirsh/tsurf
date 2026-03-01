# modules/openclaw.nix
# OpenClaw — self-hosted AI assistant with WhatsApp/messaging integrations
# Six isolated instances: mark, lou, alexia, ari (Tailscale); jordan-claw, tal-claw (public HTTPS)
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
#   mapping translates host:18789-18794 -> container:18789 per instance.
#
# @decision OCL-04: Bridge port not exposed on host.
# @rationale: Bridge is for local claude-code access within the container network.
#   Not needed when instances are accessed via gateway (HTTP/WebSocket).
#
# @decision OCL-05: openclaw.json seeded via activation script (automaton.nix pattern).
# @rationale: Config written only if absent — preserves user edits across rebuilds.
#   gateway.mode omitted — "local" blocks web browser pairing via nginx reverse proxy.
#
# @decision OCL-06: State dirs use 0750 tmpfiles permissions, owned by UID/GID 1000.
# @rationale: Container runs as UID 1000 (node user). Setting owner to 1000:1000
#   lets the container write while preventing other host processes from reading/writing.

{ config, pkgs, ... }:

let
  # Default openclaw.json configuration — seeded on first activation only.
  # Users can edit the file on the server; it will not be overwritten on rebuild.
  #
  # @decision OCL-07: gateway.bind = "lan" required for Docker port-forwarding.
  # @rationale: OpenClaw defaults to loopback binding inside the container, which
  #   prevents Docker from forwarding host traffic to the container port. "lan"
  #   binds to all interfaces (0.0.0.0) so Docker port mapping works correctly.
  #
  # @decision OCL-08: model and user are not valid openclaw.json keys (schema error).
  # @rationale: OpenClaw config schema only accepts gateway.* keys. Model is set
  #   via the ANTHROPIC_API_KEY env; user identity is gateway-level auth (token).
  mkOpenclawConfig = _user: builtins.toJSON {
    gateway = {
      port = 18789;
      bind = "lan";
      # @decision OCL-09: dangerouslyAllowHostHeaderOriginFallback used for nginx proxy access.
      # @rationale: nginx terminates TLS and forwards to container. Host-header origin fallback
      #   is acceptable for personal single-operator use on a trusted reverse proxy.
      # @decision OCL-11: trustedProxies required for nginx+Docker gateway.
      # @rationale: Without this, proxy headers from nginx (172.17.0.1 Docker bridge) are
      #   untrusted. OpenClaw logs "Proxy headers detected from untrusted address" and falls
      #   back to blocking pairing. Include 127.0.0.1, Docker bridge, and Docker network.
      trustedProxies = [ "127.0.0.1" "172.17.0.1" "172.18.0.1" ];
      auth = {
        rateLimit = {
          maxAttempts = 10;
          windowMs = 60000;
          lockoutMs = 300000;
        };
      };
      controlUi = {
        dangerouslyAllowHostHeaderOriginFallback = true;
      };
    };
  };

  openclawConfigMark    = pkgs.writeText "openclaw-mark.json"    (mkOpenclawConfig "mark");
  openclawConfigLou     = pkgs.writeText "openclaw-lou.json"     (mkOpenclawConfig "lou");
  openclawConfigAlexia  = pkgs.writeText "openclaw-alexia.json"  (mkOpenclawConfig "alexia");
  openclawConfigAri     = pkgs.writeText "openclaw-ari.json"     (mkOpenclawConfig "ari");
  openclawConfigJordanClaw  = pkgs.writeText "openclaw-jordan-claw.json"  (mkOpenclawConfig "jordan-claw");
  openclawConfigTalClaw     = pkgs.writeText "openclaw-tal-claw.json"     (mkOpenclawConfig "tal-claw");
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

  sops.templates."openclaw-jordan-claw-env" = {
    content = ''
      OPENCLAW_GATEWAY_TOKEN=${config.sops.placeholder."openclaw-jordan-claw-gateway-token"}
      ANTHROPIC_API_KEY=${config.sops.placeholder."anthropic-api-key"}
      ANTHROPIC_DEFAULT_MODEL=claude-sonnet-4-6
    '';
    owner = "root";
    mode = "0400";
  };

  sops.templates."openclaw-tal-claw-env" = {
    content = ''
      OPENCLAW_GATEWAY_TOKEN=${config.sops.placeholder."openclaw-tal-claw-gateway-token"}
      ANTHROPIC_API_KEY=${config.sops.placeholder."anthropic-api-key"}
      ANTHROPIC_DEFAULT_MODEL=claude-sonnet-4-6
    '';
    owner = "root";
    mode = "0400";
  };

  # --- State directories with permissions for container UID 1000 ---

  systemd.tmpfiles.rules = [
    "d /var/lib/openclaw-mark    0750 1000 1000 -"
    "d /var/lib/openclaw-lou     0750 1000 1000 -"
    "d /var/lib/openclaw-alexia  0750 1000 1000 -"
    "d /var/lib/openclaw-ari     0750 1000 1000 -"
    "d /var/lib/openclaw-jordan-claw  0750 1000 1000 -"
    "d /var/lib/openclaw-tal-claw     0750 1000 1000 -"
  ];

  # --- Activation script: seed openclaw.json for each instance ---

  system.activationScripts.openclaw-state = {
    text = ''
      # Seed or fix openclaw.json for each instance.
      # Seeds if absent; replaces if config has known-invalid keys (model, user).
      for pair in "mark:${openclawConfigMark}" "lou:${openclawConfigLou}" "alexia:${openclawConfigAlexia}" "ari:${openclawConfigAri}" "jordan-claw:${openclawConfigJordanClaw}" "tal-claw:${openclawConfigTalClaw}"; do
        user="''${pair%%:*}"
        config_file="''${pair#*:}"
        state_dir="/var/lib/openclaw-''${user}"
        mkdir -p "''${state_dir}"
        target="''${state_dir}/openclaw.json"
        # Replace if: absent or has invalid keys from old seed (model, user are not valid openclaw.json keys)
        if [ ! -f "''${target}" ] || grep -q '"model":\|"user":' "''${target}" 2>/dev/null; then
          cp "''${config_file}" "''${target}"
          chown 1000:1000 "''${target}"
          chmod 0640 "''${target}"
          echo "openclaw: seeded/fixed openclaw.json for ''${user}"
        fi
      done
    '';
    deps = [ "setupSecrets" ];
  };

  # --- Container declarations ---

  # mark: Tailscale-only (bind to all interfaces; nftables internalOnlyPorts restricts public access)
  virtualisation.oci-containers.containers.openclaw-mark = {
    image = "ghcr.io/openclaw/openclaw:latest";
    volumes = [ "/var/lib/openclaw-mark:/home/node/.openclaw" ];
    ports = [ "18789:18789" ];
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

  # ari: Tailscale-only (bind to all interfaces; nftables internalOnlyPorts restricts public access)
  virtualisation.oci-containers.containers.openclaw-ari = {
    image = "ghcr.io/openclaw/openclaw:latest";
    volumes = [ "/var/lib/openclaw-ari:/home/node/.openclaw" ];
    ports = [ "18792:18789" ];
    environmentFiles = [ config.sops.templates."openclaw-ari-env".path ];
    cmd = [ "node" "openclaw.mjs" "gateway" "--allow-unconfigured" ];
  };

  # @decision OCL-10: jordan-claw and tal-claw — public HTTPS via nginx+ACME (same as mark/ari).
  # @rationale: Same visibility tier as mark. ANTHROPIC_DEFAULT_MODEL=claude-sonnet-4-6 sets default model via env.
  virtualisation.oci-containers.containers.openclaw-jordan-claw = {
    image = "ghcr.io/openclaw/openclaw:latest";
    volumes = [ "/var/lib/openclaw-jordan-claw:/home/node/.openclaw" ];
    ports = [ "18793:18789" ];
    environmentFiles = [ config.sops.templates."openclaw-jordan-claw-env".path ];
    cmd = [ "node" "openclaw.mjs" "gateway" "--allow-unconfigured" ];
  };

  virtualisation.oci-containers.containers.openclaw-tal-claw = {
    image = "ghcr.io/openclaw/openclaw:latest";
    volumes = [ "/var/lib/openclaw-tal-claw:/home/node/.openclaw" ];
    ports = [ "18794:18789" ];
    environmentFiles = [ config.sops.templates."openclaw-tal-claw-env".path ];
    cmd = [ "node" "openclaw.mjs" "gateway" "--allow-unconfigured" ];
  };
}
