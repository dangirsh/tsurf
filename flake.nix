{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    home-manager = {
      url = "github:nix-community/home-manager/release-25.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    parts = {
      url = "github:dangirsh/personal-agent-runtime";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.sops-nix.follows = "sops-nix";
    };
    claw-swap = {
      url = "github:dangirsh/claw-swap";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.sops-nix.follows = "sops-nix";
    };
    llm-agents = {
      url = "github:numtide/llm-agents.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    deploy-rs = {
      url = "github:serokell/deploy-rs";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    impermanence = {
      url = "github:nix-community/impermanence";
    };
  };

  outputs = { self, nixpkgs, home-manager, sops-nix, disko, parts, claw-swap, llm-agents, deploy-rs, impermanence, ... } @ inputs: {
    nixosConfigurations.neurosys = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = { inherit inputs; };
      modules = [
        disko.nixosModules.disko
        impermanence.nixosModules.impermanence
        sops-nix.nixosModules.sops
        home-manager.nixosModules.home-manager
        inputs.parts.nixosModules.default
        inputs.claw-swap.nixosModules.default
        {
          nixpkgs.overlays = [ llm-agents.overlays.default ];
        }
        ./hosts/neurosys
        {
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
          home-manager.extraSpecialArgs = { inherit inputs; };
          home-manager.users.dangirsh = import ./home;
        }
      ];
    };

    deploy.nodes.neurosys = {
      hostname = "neurosys";
      sshUser = "root";
      magicRollback = true;
      autoRollback = true;
      confirmTimeout = 120;
      profiles.system = {
        user = "root";
        path = deploy-rs.lib.x86_64-linux.activate.nixos self.nixosConfigurations.neurosys;
      };
    };

    packages.x86_64-linux.deploy-rs = deploy-rs.packages.x86_64-linux.default;

    checks = builtins.mapAttrs
      (system: deployLib: deployLib.deployChecks self.deploy)
      deploy-rs.lib;
  };
}
