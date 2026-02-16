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
      url = "path:/data/projects/parts";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.sops-nix.follows = "sops-nix";
    };
    claw-swap = {
      url = "path:/data/projects/claw-swap"; # path: for local dev; github: for production
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.sops-nix.follows = "sops-nix";
    };
    llm-agents = {
      url = "github:numtide/llm-agents.nix";
    };
    zmx = {
      url = "github:neurosnap/zmx";
    };
  };

  outputs = { self, nixpkgs, home-manager, sops-nix, disko, parts, claw-swap, llm-agents, zmx, ... } @ inputs: {
    nixosConfigurations.acfs = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = { inherit inputs; };
      modules = [
        disko.nixosModules.disko
        sops-nix.nixosModules.sops
        home-manager.nixosModules.home-manager
        inputs.parts.nixosModules.default
        inputs.claw-swap.nixosModules.default
        {
          nixpkgs.overlays = [ llm-agents.overlays.default ];
        }
        ./hosts/acfs
        {
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
          home-manager.extraSpecialArgs = { inherit inputs; };
          home-manager.users.dangirsh = import ./home;
        }
      ];
    };
  };
}
