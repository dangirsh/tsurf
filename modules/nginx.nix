# modules/nginx.nix
# @decision WEB-01: nginx is the unified reverse proxy for public traffic (dangirsh.org + claw-swap.com).
# @rationale: A single internet-facing process reduces attack surface and removes Docker Caddy from the host edge.
# @decision WEB-02: TLS certificates are managed via NixOS ACME (Let's Encrypt), not Cloudflare origin certs.
# @rationale: Native ACME keeps certificate lifecycle declarative and automatic.
# @decision WEB-03: dangirsh.org static content is served directly from the Nix store derivation output.
# @rationale: Hakyll output is immutable, cache-friendly, and has no runtime app dependency.
# @decision WEB-04: www.dangirsh.org redirects to dangirsh.org as the canonical domain.
# @decision WEB-05: Static assets use long-lived immutable caching headers for performance.
{ config, inputs, lib, pkgs, ... }:
let
  siteRoot = inputs.dangirsh-site.packages."x86_64-linux".default;
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
    # @decision WEB-09: nginx binds to public IP only (not 0.0.0.0) so that
    # Tailscale Serve can bind port 443 on the Tailscale interface without conflict.
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

  };
}
