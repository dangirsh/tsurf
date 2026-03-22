# extras/docker.nix
# @decision DOCK-01: Docker engine with --iptables=false, NixOS owns the firewall
{ config, lib, pkgs, ... }:
let
  cfg = config.services.dockerStarter;
in
{
  options.services.dockerStarter.enable = lib.mkEnableOption "Docker engine with NixOS-managed NAT";

  config = lib.mkIf cfg.enable {

  # --- Docker engine ---
  virtualisation.docker = {
    enable = true;
    daemon.settings = {
      iptables = false;           # NixOS owns the firewall, not Docker
      log-driver = "journald";    # Container logs in systemd journal
    };
  };

  # @decision DOCK-03: Pin oci-containers backend to docker so that Docker-managed
  # containers keep using docker-* unit names even though agent-compute.nix
  # enables rootless Podman. Without this, NixOS picks podman when both runtimes
  # are enabled, producing podman-* units that conflict during activation.
  virtualisation.oci-containers.backend = "docker";

  # --- NAT for container outbound internet access ---
  # Required because Docker --iptables=false disables Docker's own NAT/masquerade.
  # Without this, containers cannot reach the internet.
  # @decision DOCK-02: Use internalIPs instead of internalInterfaces to cover all
  # Docker networks (default bridge + custom br-* bridges) without naming each one.
  networking.nat = {
    enable = true;
    internalIPs = [ "172.16.0.0/12" ];
  };

  # @decision DOCK-04: docker0 NOT in trustedInterfaces by default.
  # Container-to-host traffic goes through normal firewall rules.
  # Private overlay can add docker0 to trustedInterfaces if needed.
  # User-defined bridge networks work because filterForward defaults to false.

  services.dashboard.entries.docker = {
    name = "Docker Engine";
    description = "Container runtime (iptables=false)";
    systemdUnit = "docker.service";
    icon = "docker";
    order = 10;
    module = "docker.nix";
  };

  }; # end lib.mkIf
}
