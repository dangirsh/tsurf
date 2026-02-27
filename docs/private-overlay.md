# Private Overlay Pattern

This repo exports generic NixOS infrastructure modules via `nixosModules.default`. Personal config — secrets, private services, real hostnames, SSH keys, your actual username — belongs in a separate private flake that imports this one. Zero changes to this public repo are required to add private services.

## Private Repo Structure

```
neurosys-private/
  flake.nix                # imports neurosys public + wires personal config
  .sops.yaml               # age key recipients (admin + host keys)
  secrets/
    neurosys.yaml          # sops-encrypted secrets for primary host
    ovh.yaml               # sops-encrypted secrets for secondary host
  modules/
    private-default.nix    # import hub for private modules
    home-assistant.nix     # personal home automation
    spacebot.nix           # personal services
    repos.nix              # private repos to clone on activation
    nginx.nix              # public-facing reverse proxy + TLS
  hosts/
    neurosys/
      default.nix          # extends public host config with private details
    ovh/
      default.nix
```

## flake.nix Skeleton

```nix
{
  inputs = {
    # Public infrastructure repo — the base layer
    neurosys.url = "github:your-github/neurosys";

    # Standard inputs — must follow neurosys's pinned versions
    nixpkgs.url             = "github:NixOS/nixpkgs/nixos-25.11";
    nixpkgs.follows         = "neurosys/nixpkgs";
    home-manager.follows    = "neurosys/home-manager";
    sops-nix.follows        = "neurosys/sops-nix";
    disko.follows           = "neurosys/disko";
    impermanence.follows    = "neurosys/impermanence";
    srvos.follows           = "neurosys/srvos";
    llm-agents.follows      = "neurosys/llm-agents";
    deploy-rs.follows       = "neurosys/deploy-rs";

    # Private service inputs — your personal repos
    personal-agent-runtime.url = "github:your-github/personal-agent-runtime";
    personal-agent-runtime.inputs.nixpkgs.follows = "nixpkgs";

    your-site.url = "github:your-github/your-site";
  };

  outputs = { self, nixpkgs, neurosys, home-manager, sops-nix, disko,
              impermanence, srvos, llm-agents, deploy-rs, ... } @ inputs:
    let
      system = "x86_64-linux";

      commonModules = [
        # Public infrastructure layer — all base modules included
        neurosys.nixosModules.default
        # Private service modules
        inputs.personal-agent-runtime.nixosModules.default
        ./modules/private-default.nix
        # Framework modules (same as public repo)
        srvos.nixosModules.server
        disko.nixosModules.disko
        impermanence.nixosModules.impermanence
        sops-nix.nixosModules.sops
        home-manager.nixosModules.home-manager
        { nixpkgs.overlays = [ llm-agents.overlays.default ]; }
        {
          home-manager.useGlobalPkgs    = true;
          home-manager.useUserPackages  = true;
          home-manager.extraSpecialArgs = { inherit inputs; };
          home-manager.users.youruser   = import ./home;
        }
      ];

      mkHost = hostDir: nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = { inherit inputs; };
        modules = commonModules ++ [ hostDir ];
      };
    in {
      nixosConfigurations.neurosys = mkHost ./hosts/neurosys;
      nixosConfigurations.ovh      = mkHost ./hosts/ovh;

      deploy.nodes.neurosys = {
        hostname      = "neurosys"; # Tailscale MagicDNS
        sshUser       = "root";
        magicRollback = true;
        autoRollback  = true;
        confirmTimeout = 120;
        profiles.system = {
          user = "root";
          path = deploy-rs.lib.${system}.activate.nixos self.nixosConfigurations.neurosys;
        };
      };
    };
}
```

## modules/private-default.nix

```nix
{ imports = [
    ./home-assistant.nix
    ./spacebot.nix
    ./repos.nix
    ./nginx.nix
]; }
```

## hosts/neurosys/default.nix

```nix
# No need to import neurosys.nixosModules.default — already in commonModules.
{ config, lib, pkgs, ... }: {
  imports = [ ./hardware.nix ];

  networking.hostName = "neurosys";

  # Static IP for your provider (set to "" for DHCP)
  networking.interfaces.eth0.ipv4.addresses = [
    { address = "YOUR.VPS.IP.HERE"; prefixLength = 22; }
  ];
  networking.defaultGateway = "YOUR.GATEWAY.IP";
  networking.nameservers     = [ "1.1.1.1" "8.8.8.8" ];

  # sops secrets file for this host
  sops.defaultSopsFile = ../../secrets/neurosys.yaml;

  # Your actual username — overrides the 'myuser' placeholder in the public repo
  users.users.youruser = {
    isNormalUser    = true;
    extraGroups     = [ "wheel" "docker" ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 YOUR_SSH_PUBLIC_KEY"
    ];
  };

  # Override home-manager username to match
  home-manager.users.youruser = lib.mkForce (import ../../home);

  system.stateVersion = "25.11";
}
```

## Secrets Setup

```
# 1. Generate your admin age key
age-keygen -o ~/.config/sops/age/keys.txt

# 2. Derive host age key from SSH host key (pre-generated, injected via nixos-anywhere)
ssh-to-age -i /etc/ssh/ssh_host_ed25519_key.pub

# 3. .sops.yaml — one creation rule per host
creation_rules:
  - path_regex: secrets/neurosys\.yaml$
    key_groups:
      - age:
          - age1yourAdminKey...           # your workstation key
          - age1hostNeurosysKey...         # derived from host ed25519

# 4. Create and edit secrets
sops secrets/neurosys.yaml
```

See the [sops-nix README](https://github.com/Mic92/sops-nix) for full key management details.

## Private Module Example: home-assistant.nix

```nix
# modules/home-assistant.nix — same patterns as public modules
{ config, lib, pkgs, ... }: {
  # @decision HA-PRIV-01: HA is a private service; openFirewall = false, Tailscale-only.
  services.home-assistant = {
    enable          = true;
    openFirewall    = false;
    configDir       = "/var/lib/hass";
    extraComponents = [ "hue" "esphome" "mobile_app" "mcp_server" ];
  };

  # Tailscale-only: HA is reachable via trustedInterfaces = ["tailscale0"]
  # Add port to networking.nix internalOnlyPorts in your private overlay module.
}
```

## Wiring Secret Proxy for Private Projects

The public `agent-compute.nix` has a placeholder comment for `ANTHROPIC_BASE_URL` routing. To enable it for specific projects, add a NixOS module in your private overlay:

```nix
# modules/agent-proxy-routing.nix
{ pkgs, ... }: {
  # Override agent-spawn with project-specific proxy routing
  # by patching the script or setting ANTHROPIC_BASE_URL
  # before the sandbox is entered for private project dirs.
  # See the comment block in public modules/agent-compute.nix for the
  # exact extension point.
}
```

Alternatively, fork the public repo and edit the placeholder block directly — the comment marks the exact location.
