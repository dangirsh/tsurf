# modules/homepage.nix
# @decision HP-01: Use NixOS-native homepage-dashboard service; listen on 0.0.0.0 for Tailscale reachability.
{ config, pkgs, ... }: {
  services.homepage-dashboard = {
    enable = true;
    listenPort = 8082;
    allowedHosts = "100.127.245.9:8082,100.127.245.9,acfs,localhost";

    settings = {
      title = "acfs";
      theme = "dark";
      color = "slate";
      headerStyle = "clean";
    };

    services = [
      {
        "Services" = [
          { "Grafana" = { href = "http://100.127.245.9:3000"; description = "Metrics dashboards"; }; }
          { "Prometheus" = { href = "http://100.127.245.9:9090"; description = "Metrics & queries"; }; }
          { "Alertmanager" = { href = "http://100.127.245.9:9093"; description = "Alert routing"; }; }
          { "ntfy" = { href = "http://100.127.245.9:2586"; description = "Push notifications"; }; }
          { "Syncthing" = { href = "http://100.127.245.9:8384"; description = "File sync"; }; }
          { "Home Assistant" = { href = "http://100.127.245.9:8123"; description = "Home automation"; }; }
        ];
      }
    ];
  };
}
