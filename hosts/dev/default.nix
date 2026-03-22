# hosts/dev/default.nix — dev host (e.g. OVH VPS)
# Role: agent development and sandboxed execution via agent-sandbox.nix + nono.nix.
# Clone-repos activation script initializes project directories on first boot.
# Private overlay adds repo lists, agent fleet config, and host-specific service wiring.
{ config, inputs, lib, pkgs, ... }:
let
  agentCfg = config.tsurf.agent;
in {
  imports = [
    ../hardware.nix
    ../disko-config.nix
    # Shared modules
    ../../modules/base.nix
    ../../modules/boot.nix
    ../../modules/users.nix
    ../../modules/networking.nix
    ../../modules/secrets.nix
    ../../extras/docker.nix
    ../../extras/syncthing.nix
    ../../modules/agent-compute.nix
    ../../modules/impermanence.nix
    ../../modules/break-glass-ssh.nix
    ../../modules/sshd-liveness-check.nix
    ../../extras/dashboard.nix
    ../../extras/cost-tracker.nix
    ../../modules/agent-sandbox.nix
    ../../modules/nono.nix
    # Optional agent extras: import ../../extras/codex.nix, ../../extras/pi.nix,
    # ../../extras/opencode.nix, or ../../extras/dev-agent.nix in your private overlay.
  ];

  home-manager.users.dev = import ../../extras/home;

  # Agent user home-manager config (minimal — git + direnv only, no SSH)
  home-manager.users.${agentCfg.user} = { ... }: {
    home.username = agentCfg.user;
    home.homeDirectory = agentCfg.home;
    home.stateVersion = "25.11";
    programs.home-manager.enable = true;
    programs.git = {
      enable = true;
      settings.user.name = "Agent";
      settings.user.email = "agent@localhost";
    };
    programs.direnv = {
      enable = true;
      enableBashIntegration = true;
      nix-direnv.enable = true;
    };
  };

  networking.hostName = "tsurf-dev";
  time.timeZone = "Europe/Berlin";
  i18n.defaultLocale = "C.UTF-8";

  # OVH uses DHCP for static assignment.
  networking.useDHCP = true;

  # @decision AGENT-01, AGENT-02: Idempotent repo cloning on activation (clone-only, never pull)
  system.activationScripts.clone-repos = {
    deps = [ "users" ];
    text = ''
      GIT_BIN="${pkgs.git}/bin/git"
      GITHUB_PAT_FILE="${config.sops.secrets."github-pat".path}"
    '' + builtins.readFile ../../extras/scripts/clone-repos.sh;
  };

  # --- Host-specific shared module settings ---
  boot.loader.grub.device = "/dev/sda";
  networking.nat.externalInterface = "ens3";
  sops.defaultSopsFile = ../../secrets/ovh.yaml;
  sops.age.sshKeyPaths = [ "/persist/etc/ssh/ssh_host_ed25519_key" ];

  # @decision OVH-01: Port 22 open on public interface for bootstrap and deploy access.
  # OVH VPS has no Tailscale pre-installed; SSH must be public until Tailscale is up.
  # Key-only auth enforced by networking.nix. fail2ban is disabled (SEC83-01).
  services.openssh.openFirewall = lib.mkForce true;

  # @decision OVH-02: Explicit hostKeys path points directly to /persist/ to avoid
  # impermanence mount timing races on first boot. The etc-ssh.mount unit mounts
  # /persist/etc/ssh/ over /etc/ssh/, but if sshd starts before the mount completes,
  # it fails with "no such file". By pointing sshd directly at /persist/etc/ssh/,
  # we bypass sshd_config entirely — nixos-anywhere always places the host key there.
  services.openssh.hostKeys = lib.mkForce [
    { type = "ed25519"; path = "/persist/etc/ssh/ssh_host_ed25519_key"; }
  ];

  services.dockerStarter.enable = true;
  services.syncthingStarter.enable = true;
  services.agentCompute.enable = true;
  services.agentSandbox.enable = true;
  services.nonoSandbox.enable = true;
  services.agentSandbox.allowNixDaemon = true;
  services.agentSandbox.egressControl.enable = true;
  services.agentSandbox.extraAgents = [{
    name = "agent-sandbox-e2e";
    package = pkgs.sandbox-probe-e2e;
    binary = "sandbox-probe-e2e";
    credentials = [ "anthropic:ANTHROPIC_API_KEY:anthropic-api-key" ];
  }];

  networking.useNetworkd = lib.mkForce false;

  system.stateVersion = "25.11";
}
