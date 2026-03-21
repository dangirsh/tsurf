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
    ...
  } @ inputs:
    let
      system = "x86_64-linux";
      lib = nixpkgs.lib;
      pkgs = nixpkgs.legacyPackages.${system};

      commonModules = [
        srvos.nixosModules.server
        disko.nixosModules.disko
        impermanence.nixosModules.impermanence
        sops-nix.nixosModules.sops
        home-manager.nixosModules.home-manager
        {
          nixpkgs.overlays = [
            llm-agents.overlays.default
            (final: prev: {
              nono = final.callPackage ./packages/nono.nix {};
              pi-coding-agent = final.callPackage ./packages/pi-coding-agent.nix {};
            })
          ];
        }
        {
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
          home-manager.extraSpecialArgs = { inherit inputs; };
          # Each host imports home config explicitly — see hosts/*/default.nix
        }
      ];

      mkHost = hostDir: nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = { inherit inputs; };
        modules = commonModules ++ [ hostDir ];
      };

      # Eval fixtures: inject allowUnsafePlaceholders so public template evaluates
      # without real credentials. Host source files are secure by default (flag not set).
      # Private overlay uses mkHost directly and never sets this flag.
      mkEvalFixture = hostDir: nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = { inherit inputs; };
        modules = commonModules ++ [
          hostDir
          { tsurf.template.allowUnsafePlaceholders = true; }
        ];
      };

      evalChecks = import ./tests/eval/config-checks.nix { inherit self pkgs lib; };
    in {
      nixosConfigurations.neurosys = mkEvalFixture ./hosts/services;
      nixosConfigurations.neurosys-dev = mkEvalFixture ./hosts/dev;

      deploy.nodes.neurosys = {
        hostname = "neurosys"; # Tailscale MagicDNS hostname; private overlay may override with IP
        sshUser = "root";
        magicRollback = true;
        autoRollback = true;
        confirmTimeout = 300; # Keep in sync with scripts/deploy.sh --confirm-timeout
        profiles.system = {
          user = "root";
          path = deploy-rs.lib.${system}.activate.nixos self.nixosConfigurations.neurosys;
        };
      };

      deploy.nodes.neurosys-dev = {
        hostname = "neurosys-dev";
        sshUser = "root";
        magicRollback = true;
        autoRollback = true;
        confirmTimeout = 300; # Keep in sync with scripts/deploy.sh --confirm-timeout
        profiles.system = {
          user = "root";
          path = deploy-rs.lib.${system}.activate.nixos self.nixosConfigurations.neurosys-dev;
        };
      };

      packages.${system} = {
        deploy-rs = deploy-rs.packages.${system}.default;

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
                neurosys|neurosys-dev)
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
            shellcheck "$src"/tests/lib/*.bash "$src"/scripts/run-tests.sh "$src"/scripts/sshd-liveness-check.sh
            # btrfs-rollback.sh runs in initrd (busybox) — skip shellcheck
            # SC2317: BATS @test blocks appear unreachable to shellcheck
            shellcheck --exclude=SC2317 "$src"/tests/live/*.bats
            touch "$out"
          '';
        };
    };
}
