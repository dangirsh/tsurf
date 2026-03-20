# This is a TEMPLATE — it will not evaluate as-is.
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
  };

  outputs = {
    self,
    nixpkgs,
    home-manager,
    sops-nix,
    disko,
    llm-agents,
    deploy-rs,
    impermanence,
    srvos,
    ...
  } @ inputs:
    let
      system = "x86_64-linux"; # REPLACE if needed.

      commonModules = [
        # Public infrastructure modules that are safe to import before host-specific setup.
        srvos.nixosModules.server
        disko.nixosModules.disko
        impermanence.nixosModules.impermanence
        sops-nix.nixosModules.sops
        home-manager.nixosModules.home-manager
        {
          nixpkgs.overlays = [ llm-agents.overlays.default ];
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
        }
        "${inputs.tsurf}/modules/base.nix"
        "${inputs.tsurf}/modules/boot.nix"
        "${inputs.tsurf}/modules/users.nix"
        "${inputs.tsurf}/modules/impermanence.nix"
        "${inputs.tsurf}/modules/break-glass-ssh.nix"
        "${inputs.tsurf}/modules/dashboard.nix"
        # nono sandbox infrastructure - provides NONO_PROFILE_PATH and profile
        # installation to /etc/nono/profiles/. Required by agentic janitor.
        "${inputs.tsurf}/modules/nono.nix"
        { services.nonoSandbox.enable = true; }

        # Import networking.nix after configuring Tailscale, SSH host keys, and impermanence.
        # Import secrets.nix after creating your encrypted secrets file, or write your own secrets module.
        # Import sshd-liveness-check.nix after networking.nix assertions are satisfied.
      ];
    in {
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
        confirmTimeout = 120;
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
