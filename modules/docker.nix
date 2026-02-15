# modules/docker.nix
# @decision DOCK-01: Docker engine with --iptables=false, NixOS owns the firewall
{ config, pkgs, ... }: {

  # --- Docker engine ---
  virtualisation.docker = {
    enable = true;
    daemon.settings = {
      iptables = false;           # NixOS owns the firewall, not Docker
      log-driver = "journald";    # Container logs in systemd journal
    };
  };

  # --- NAT for container outbound internet access ---
  # Required because Docker --iptables=false disables Docker's own NAT/masquerade.
  # Without this, containers cannot reach the internet.
  networking.nat = {
    enable = true;
    internalInterfaces = [ "docker0" ];
    externalInterface = "eth0";   # NOTE: verify on Contabo -- may be ens3
  };

  # --- Trust Docker bridge for container-to-container traffic ---
  # NixOS merges trustedInterfaces lists across modules, so this adds
  # to the tailscale0 trust declared in networking.nix.
  # User-defined bridge networks (br-<hash>) work because
  # networking.firewall.filterForward defaults to false (FORWARD accepts all).
  networking.firewall.trustedInterfaces = [ "docker0" ];
}
