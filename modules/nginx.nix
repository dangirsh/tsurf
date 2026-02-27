# modules/nginx.nix
# @decision WEB-01: nginx is the unified reverse proxy for public traffic (dangirsh.org + claw-swap.com).
# @rationale: A single internet-facing process reduces attack surface and removes Docker Caddy from the host edge.
# @decision WEB-02: TLS certificates are managed via NixOS ACME (Let's Encrypt), not Cloudflare origin certs.
# @rationale: Native ACME keeps certificate lifecycle declarative and automatic.
# @decision WEB-03: dangirsh.org static content is served directly from the Nix store derivation output.
# @rationale: Hakyll output is immutable, cache-friendly, and has no runtime app dependency.
# @decision WEB-04: www.dangirsh.org redirects to dangirsh.org as the canonical domain.
# @decision WEB-05: Static assets use long-lived immutable caching headers for performance.
# @decision WEB-10: mark's openclaw is served over HTTPS on the Tailscale interface via nginx with a self-signed cert.
# @rationale: Browser device identity API requires a secure context (HTTPS or localhost).
#   Tailscale is trusted-network-only; a self-signed cert gives HTTPS without exposing to the public internet.
# @decision WEB-11: Self-signed cert is generated once in an activation script and persisted across reboots.
# @rationale: A stable cert fingerprint means the browser warning appears only once.
#   Generating at build time would produce a new cert (new fingerprint) on every rebuild.
{ config, inputs, lib, pkgs, ... }:
let
  siteRoot = inputs.dangirsh-site.packages."x86_64-linux".default;
  # Tailscale IP — stable (derived from device key, does not change across reboots).
  # Used as CN and SAN in the self-signed cert so browser accepts it for this IP.
  tailscaleIp = "100.113.239.14";
  # @decision WEB-07: ACME uses DNS-01 challenge via Cloudflare API.
  # @rationale: DNS-01 allows cert issuance before DNS points to this server,
  # solving the chicken-and-egg problem for new host deployments (e.g. OVH).
  # Applied per-cert because security.acme.defaults.dnsProvider does not
  # propagate to the generated lego script in NixOS 25.11.
  cfDns = {
    dnsProvider = "cloudflare";
    webroot = null;  # clear enableACME's default webroot; exactly one challenge type required
    credentialFiles = {
      "CF_DNS_API_TOKEN_FILE" = config.sops.secrets."cloudflare-dns-token".path;
    };
  };
in {
  security.acme = {
    acceptTerms = true;
    defaults.email = "dan@dangirsh.org";
    certs."dangirsh.org"        = cfDns;
    certs."www.dangirsh.org"    = cfDns;
    certs."staging.dangirsh.org" = cfDns;
    certs."claw-swap.com"       = cfDns;
  };

  services.nginx = {
    enable = true;
    recommendedTlsSettings = true;
    recommendedOptimisation = true;
    recommendedGzipSettings = true;
    recommendedProxySettings = true;
    # @decision WEB-09: nginx default listen address is the public IP (not 0.0.0.0).
    # @rationale: Prevents unintentional exposure of vhosts on the Tailscale interface.
    #   The mark openclaw vhost explicitly overrides this with a Tailscale-IP listen directive.
    defaultListenAddresses = [ "161.97.74.121" ];

    virtualHosts."dangirsh.org" = {
      enableACME = true;
      forceSSL = true;
      root = siteRoot;

      locations."/" = {
        tryFiles = "$uri $uri/index.html $uri.html =404";
      };

      locations."~* \\.(css|js|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf|eot)$" = {
        root = siteRoot;
        extraConfig = ''
          expires 30d;
          add_header Cache-Control "public, immutable";
        '';
      };
    };

    virtualHosts."www.dangirsh.org" = {
      enableACME = true;
      forceSSL = true;
      globalRedirect = "dangirsh.org";
    };

    # @decision WEB-06: staging.dangirsh.org served from Contabo neurosys (161.97.74.121).
    # @rationale: Validates full nginx+Hakyll stack on staging before OVH production cutover.
    virtualHosts."staging.dangirsh.org" = {
      enableACME = true;
      forceSSL = true;
      root = siteRoot;

      locations."/" = {
        tryFiles = "$uri $uri/index.html $uri.html =404";
      };

      locations."~* \\.(css|js|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf|eot)$" = {
        root = siteRoot;
        extraConfig = ''
          expires 30d;
          add_header Cache-Control "public, immutable";
        '';
      };
    };

    virtualHosts."claw-swap.com" = {
      enableACME = true;
      forceSSL = true;
      locations."/" = {
        proxyPass = "http://127.0.0.1:3000";
        proxyWebsockets = true;
      };
    };

    # @decision WEB-10: mark's openclaw on Tailscale interface with self-signed cert.
    # Listens only on the Tailscale IP — invisible to the public internet.
    # ssl_stapling is disabled because self-signed certs have no OCSP responder.
    virtualHosts."${tailscaleIp}" = {
      onlySSL = true;
      listen = [{ addr = tailscaleIp; port = 443; ssl = true; }];
      sslCertificate = "/var/lib/openclaw-nginx-ssl/cert.pem";
      sslCertificateKey = "/var/lib/openclaw-nginx-ssl/key.pem";
      extraConfig = ''
        ssl_stapling off;
        ssl_stapling_verify off;
      '';
      locations."/" = {
        proxyPass = "http://127.0.0.1:18789";
        proxyWebsockets = true;
      };
    };

  };

  # Generate the self-signed cert once; persist across reboots (see impermanence.nix).
  # Regenerates only if the cert file is absent — fingerprint stays stable after first deploy.
  system.activationScripts.openclaw-mark-tls-cert = {
    text = ''
      cert_dir=/var/lib/openclaw-nginx-ssl
      cert_file="$cert_dir/cert.pem"
      key_file="$cert_dir/key.pem"
      if [ ! -f "$cert_file" ]; then
        mkdir -p "$cert_dir"
        ${pkgs.openssl}/bin/openssl req -x509 -newkey rsa:4096 \
          -keyout "$key_file" -out "$cert_file" \
          -days 3650 -nodes \
          -subj "/CN=${tailscaleIp}" \
          -addext "subjectAltName=IP:${tailscaleIp}"
        chown root:nginx "$key_file"
        chmod 640 "$key_file"
        chmod 644 "$cert_file"
        chmod 750 "$cert_dir"
        echo "openclaw-mark-tls-cert: generated self-signed cert for ${tailscaleIp}"
      fi
    '';
    deps = [ "users" ];
  };
}
