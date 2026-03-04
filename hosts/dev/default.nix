{ config, inputs, lib, pkgs, ... }: {
  imports = [
    ./hardware.nix
    ./disko-config.nix
    # Shared modules
    ../../modules/base.nix
    ../../modules/boot.nix
    ../../modules/users.nix
    ../../modules/networking.nix
    ../../modules/secrets.nix
    ../../modules/docker.nix
    ../../modules/syncthing.nix
    ../../modules/agent-compute.nix
    ../../modules/secret-proxy.nix
    ../../modules/impermanence.nix
    ../../modules/dashboard.nix
  ];

  networking.hostName = "neurosys-dev";
  time.timeZone = "Europe/Berlin";
  i18n.defaultLocale = "C.UTF-8";

  # OVH uses DHCP for static assignment.
  networking.useDHCP = true;

  # @decision AGENT-01, AGENT-02: Idempotent repo cloning on activation (clone-only, never pull)
  system.activationScripts.clone-repos = {
    deps = [ "users" ];
    text = ''
      repos=(
        "dangirsh/agentic-dev-base"
      )
      CLONE_DIR="/data/projects"
      GH_TOKEN="$(cat ${config.sops.secrets."github-pat".path} 2>/dev/null || true)"
      CRED_FILE=$(mktemp)
      chmod 600 "$CRED_FILE"
      mkdir -p "$CLONE_DIR"
      for repo in "''${repos[@]}"; do
        name="$(basename "$repo")"
        target="$CLONE_DIR/$name"
        if [ ! -d "$target" ]; then
          echo "Cloning $repo to $target..."
          printf 'https://x-access-token:%s@github.com\n' "$GH_TOKEN" > "$CRED_FILE"
          GIT_TERMINAL_PROMPT=0 ${pkgs.git}/bin/git \
            -c credential.helper="store --file=$CRED_FILE" \
            clone "https://github.com/$repo.git" "$target" \
            || echo "WARNING: Failed to clone $repo (will retry on next activation)"
          chown -R dev:users "$target" 2>/dev/null || true
        fi
      done
      rm -f "$CRED_FILE"
    '';
  };

  # --- Host-specific shared module settings ---
  boot.loader.grub.device = "/dev/sda";
  networking.nat.externalInterface = "ens3";
  sops.defaultSopsFile = ../../secrets/ovh.yaml;
  sops.age.sshKeyPaths = [ "/persist/etc/ssh/ssh_host_ed25519_key" ];

  # @decision OVH-01: Port 22 open on public interface for bootstrap and deploy access.
  # OVH VPS has no Tailscale pre-installed; SSH must be public until Tailscale is up.
  # fail2ban provides brute-force protection. Key-only auth enforced by networking.nix.
  services.openssh.openFirewall = lib.mkForce true;

  # @decision OVH-02: Explicit hostKeys path points directly to /persist/ to avoid
  # impermanence mount timing races on first boot. The etc-ssh.mount unit mounts
  # /persist/etc/ssh/ over /etc/ssh/, but if sshd starts before the mount completes,
  # it fails with "no such file". By pointing sshd directly at /persist/etc/ssh/,
  # we bypass sshd_config entirely — nixos-anywhere always places the host key there.
  services.openssh.hostKeys = lib.mkForce [
    { type = "ed25519"; path = "/persist/etc/ssh/ssh_host_ed25519_key"; }
  ];

  # --- srvos overrides ---
  networking.useNetworkd = lib.mkForce false;
  srvos.server.docs.enable = true;
  programs.command-not-found.enable = true;
  boot.initrd.systemd.enable = lib.mkForce false;

  system.stateVersion = "25.11";
}
