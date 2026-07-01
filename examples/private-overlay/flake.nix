# examples/private-overlay/flake.nix
# Forkable starting point for a private tsurf overlay.
# This is a TEMPLATE; it will not evaluate as-is.
# You must customize placeholder values, add host-specific modules
# (networking.nix, secrets.nix), and configure real hardware before
# `nix flake check` will pass.
{
  inputs = {
    # REPLACE: point to your fork or upstream source repository.
    tsurf.url = "github:your-org/tsurf";

    # Keep private overlay dependency graph aligned with public tsurf.
    nixpkgs.follows = "tsurf/nixpkgs";
    home-manager.follows = "tsurf/home-manager";
    sops-nix.follows = "tsurf/sops-nix";
    disko.follows = "tsurf/disko";
    llm-agents.follows = "tsurf/llm-agents";
    deploy-rs.follows = "tsurf/deploy-rs";
    impermanence.follows = "tsurf/impermanence";
    srvos.follows = "tsurf/srvos";
    nix-mineral.follows = "tsurf/nix-mineral";
  };

  outputs =
    {
      self,
      nixpkgs,
      home-manager,
      sops-nix,
      disko,
      llm-agents,
      deploy-rs,
      impermanence,
      srvos,
      nix-mineral,
      ...
    }@inputs:
    let
      system = "x86_64-linux"; # REPLACE if needed.

      commonModules = [
        # Public infrastructure modules that are safe to import before host-specific setup.
        srvos.nixosModules.server
        disko.nixosModules.disko
        impermanence.nixosModules.impermanence
        sops-nix.nixosModules.sops
        home-manager.nixosModules.home-manager
        nix-mineral.nixosModules.nix-mineral
        {
          nixpkgs.overlays = [
            llm-agents.overlays.default
            inputs.tsurf.overlays.default
          ];
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
        }
        inputs.tsurf.nixosModules.base
        inputs.tsurf.nixosModules.boot
        inputs.tsurf.nixosModules.users
        ./modules/root-ssh.nix
        inputs.tsurf.nixosModules.impermanence
        # agent-compute.nix: tsurf-agents.slice cgroup limits and /data/projects persistence
        inputs.tsurf.nixosModules.agent-compute
        { services.agentCompute.enable = true; }
        # networking.nix: host-level firewall and dedicated-agent egress policy
        inputs.tsurf.nixosModules.networking
        # nono.nix: nono binary, tsurf base profile, NONO_PROFILE_PATH
        inputs.tsurf.nixosModules.nono
        { services.nonoSandbox.enable = true; }
        # agent-launcher.nix: generic sandboxed agent launcher infrastructure
        inputs.tsurf.nixosModules.agent-launcher
        # agent-sandbox.nix: core claude wrapper
        inputs.tsurf.nixosModules.agent-sandbox
        { services.agentSandbox.enable = true; }
        # Optional extras (import here, then enable in host config as needed):
        # cass.nix: low-priority CASS indexer timer for the dedicated agent user
        "${inputs.tsurf}/extras/cass.nix"
        # "${inputs.tsurf}/extras/restic.nix"
        # Home Manager profile opt-in pattern (per host):
        # { home-manager.users.agent = import "${inputs.tsurf}/extras/home"; }
        # Import secrets.nix after creating your encrypted secrets file, or write your own secrets module.
      ];
    in
    {
      nixosConfigurations.example = nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = { inherit inputs; };
        modules = commonModules ++ [ ./hosts/example ];
      };

      deploy.nodes.example = {
        hostname = "your-host.REPLACE.example";
        sshUser = "root";
        magicRollback = true;
        autoRollback = true;
        confirmTimeout = 300; # Keep in sync with scripts/deploy.sh --confirm-timeout
        profiles.system = {
          user = "root";
          path = deploy-rs.lib.${system}.activate.nixos self.nixosConfigurations.example;
        };
      };

      devShells.${system}.default = nixpkgs.legacyPackages.${system}.mkShell {
        packages = with nixpkgs.legacyPackages.${system}; [
          sops
          age
        ];
      };
    };
}
