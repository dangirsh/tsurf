# modules/grafana.nix
# @decision GRAF-01: Keep Grafana reachable over trusted interfaces only (Tailscale).
# @decision GRAF-02: Store admin credentials via sops-nix file provider, never in the Nix store.
# @decision GRAF-03: Provision datasources/dashboards declaratively for repeatable monitoring setup.
{ config, pkgs, ... }: {
  sops.secrets."grafana-admin-password" = {
    owner = "grafana";
    group = "grafana";
  };

  sops.secrets."grafana-secret-key" = {
    owner = "grafana";
    group = "grafana";
  };

  services.grafana = {
    enable = true;

    settings = {
      server = {
        http_addr = "0.0.0.0";
        http_port = 3000;
        enable_gzip = true;
      };

      security = {
        admin_user = "admin";
        admin_password = "$__file{${config.sops.secrets."grafana-admin-password".path}}";
        secret_key = "$__file{${config.sops.secrets."grafana-secret-key".path}}";
      };

      analytics = {
        reporting_enabled = false;
      };
    };

    provision = {
      enable = true;

      datasources.settings = {
        apiVersion = 1;
        datasources = [
          {
            name = "Prometheus";
            type = "prometheus";
            access = "proxy";
            url = "http://localhost:${toString config.services.prometheus.port}";
            isDefault = true;
            editable = false;
          }
          {
            name = "Alertmanager";
            type = "alertmanager";
            access = "proxy";
            url = "http://localhost:9093";
            editable = false;
            jsonData = {
              implementation = "prometheus";
            };
          }
        ];
      };

      dashboards.settings = {
        apiVersion = 1;
        providers = [
          {
            name = "default";
            type = "file";
            disableDeletion = true;
            foldersFromFilesStructure = true;
            options.path = "/etc/grafana-dashboards";
          }
        ];
      };
    };
  };

  environment.etc."grafana-dashboards/node-exporter-full.json".source = builtins.fetchurl {
    url = "https://grafana.com/api/dashboards/1860/revisions/37/download";
    sha256 = "0qza4j8lywrj08bqbww52dgh2p2b9rkhq5p313g72i57lrlkacfl";
  };
}
