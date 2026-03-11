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
    srvos = {
      url = "github:nix-community/srvos";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-secret-proxy = {
      # NOTE: This uses a local path input. Clone https://github.com/dangirsh/nix-secret-proxy
      # (or your own fork) to /data/projects/nix-secret-proxy before using.
      # Private overlay can override via: inputs.nix-secret-proxy.follows = "your-fork"
      url = "path:/data/projects/nix-secret-proxy";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  # Private overlay: add your private inputs (parts, personal services, etc.) in a separate private flake that imports this one.
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
    treefmt-nix,
    nix-secret-proxy,
    ...
  } @ inputs:
    let
      system = "x86_64-linux";
      lib = nixpkgs.lib;
      pkgs = nixpkgs.legacyPackages.${system};
      treefmtEval = treefmt-nix.lib.evalModule pkgs ./treefmt.nix;

      commonModules = [
        srvos.nixosModules.server
        disko.nixosModules.disko
        impermanence.nixosModules.impermanence
        sops-nix.nixosModules.sops
        nix-secret-proxy.nixosModules.default
        home-manager.nixosModules.home-manager
        {
          nixpkgs.overlays = [ llm-agents.overlays.default ];
        }
        {
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
          home-manager.extraSpecialArgs = { inherit inputs; };
          home-manager.users.dev = import ./home;
        }
      ];

      mkHost = hostDir: nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = { inherit inputs; };
        modules = commonModules ++ [ hostDir ];
      };

      evalChecks = import ./tests/eval/config-checks.nix { inherit self pkgs lib; };
    in {
      nixosConfigurations.neurosys = mkHost ./hosts/services;
      nixosConfigurations.ovh = mkHost ./hosts/dev;

      deploy.nodes.neurosys = {
        hostname = "neurosys"; # Tailscale MagicDNS hostname; private overlay may override with IP
        sshUser = "root";
        magicRollback = true;
        autoRollback = true;
        confirmTimeout = 120;
        profiles.system = {
          user = "root";
          path = deploy-rs.lib.${system}.activate.nixos self.nixosConfigurations.neurosys;
        };
      };

      deploy.nodes.ovh = {
        hostname = "neurosys-dev";
        sshUser = "root";
        magicRollback = true;
        autoRollback = true;
        confirmTimeout = 120;
        profiles.system = {
          user = "root";
          path = deploy-rs.lib.${system}.activate.nixos self.nixosConfigurations.ovh;
        };
      };

      packages.${system} = {
        deploy-rs = deploy-rs.packages.${system}.default;

        # VM integration test — requires KVM (local dev or KVM-capable CI only).
        # Run with: nix build .#vm-test-ssh
        # @decision TEST-70-01: exposed as a package (not a check) so nix flake check
        # continues to work on Contabo/OVH VPS which lack nested KVM.
        vm-test-ssh = import ./tests/vm/ssh-reachability.nix { inherit self pkgs lib; };

        test-live = pkgs.writeShellApplication {
          name = "test-live";
          runtimeInputs = with pkgs; [
            bats
            bats.libraries.bats-support
            bats.libraries.bats-assert
            openssh
            curl
            jq
            nmap
            coreutils
            findutils
            gnugrep
            gawk
          ];
          text = ''
            #!/usr/bin/env bash
            set -euo pipefail

            HOST="neurosys"
            BATS_FILES=()

            while [[ $# -gt 0 ]]; do
              case "$1" in
                --host|-h)
                  HOST="$2"
                  shift 2
                  ;;
                neurosys|ovh|neurosys-dev)
                  HOST="$1"
                  shift
                  ;;
                *)
                  BATS_FILES+=("$1")
                  shift
                  ;;
              esac
            done

            export NEUROSYS_TEST_HOST="$HOST"
            export BATS_LIB_PATH="${pkgs.bats.libraries.bats-support}/share/bats:${pkgs.bats.libraries.bats-assert}/share/bats"

            tests_dir="${builtins.toString ./tests/live}"
            if [[ ! -d "$tests_dir" ]]; then
              echo "ERROR: tests directory not found: $tests_dir"
              exit 1
            fi

            if [[ ''${#BATS_FILES[@]} -eq 0 ]]; then
              echo "=== Running all live tests against $HOST ==="
              bats --tap "$tests_dir"/*.bats
            else
              echo "=== Running selected live tests against $HOST ==="
              bats --tap "''${BATS_FILES[@]}"
            fi
          '';
        };
      };

      apps.${system}.test-live = {
        type = "app";
        program = "${self.packages.${system}.test-live}/bin/test-live";
      };

      formatter.${system} = treefmtEval.config.build.wrapper;

      devShells.${system}.default = pkgs.mkShell {
        packages = [
          pkgs.sops
          pkgs.age
          pkgs.nixfmt
          pkgs.shellcheck
          pkgs.bats
          pkgs.bats.libraries.bats-support
          pkgs.bats.libraries.bats-assert
          deploy-rs.packages.${system}.default
        ];
      };

      checks.${system} =
        let
          deployChecks = deploy-rs.lib.${system}.deployChecks self.deploy;
        in
        deployChecks // evalChecks // {
          shellcheck-tests = pkgs.runCommandNoCC "shellcheck-tests" {
            nativeBuildInputs = [ pkgs.shellcheck ];
            src = ./.;
          } ''
            shellcheck "$src"/tests/lib/*.bash "$src"/scripts/run-tests.sh
            shellcheck "$src"/tests/live/*.bats || true
            touch "$out"
          '';
        };
    };
}
