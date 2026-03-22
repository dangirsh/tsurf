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
    nixos-anywhere = {
      url = "github:nix-community/nixos-anywhere";
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
    nixos-anywhere,
    ...
  } @ inputs:
    let
      system = "x86_64-linux";
      lib = nixpkgs.lib;
      pkgs = nixpkgs.legacyPackages.${system};
      tsurfOverlay = final: prev: {
        nono = final.callPackage ./packages/nono.nix {};
        pi-coding-agent = final.callPackage ./packages/pi-coding-agent.nix {};
        zmx = final.callPackage ./packages/zmx.nix {};
      };

      commonModules = [
        srvos.nixosModules.server
        disko.nixosModules.disko
        impermanence.nixosModules.impermanence
        sops-nix.nixosModules.sops
        home-manager.nixosModules.home-manager
        {
          nixpkgs.overlays = [
            llm-agents.overlays.default
            self.overlays.default
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

      # Eval fixtures: inject allowUnsafePlaceholders so the public template evaluates
      # without real credentials. Host source files are secure by default (flag not set).
      # These are exported only as clearly named eval-only outputs, never as deploy
      # targets. Private overlay uses mkHost directly and never sets this flag.
      mkEvalFixture = hostDir: extraModules: nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = { inherit inputs; };
        modules = commonModules ++ [
          hostDir
          { tsurf.template.allowUnsafePlaceholders = true; }
        ] ++ extraModules;
      };

      evalChecks = import ./tests/eval/config-checks.nix { inherit self pkgs lib; };
    in {
      overlays.default = tsurfOverlay;

      nixosConfigurations."eval-tsurf" = mkEvalFixture ./hosts/services [ ];
      nixosConfigurations."eval-tsurf-dev" = mkEvalFixture ./hosts/dev [ ];
      nixosConfigurations."eval-tsurf-dev-alt-agent" = mkEvalFixture ./hosts/dev [
        {
          tsurf.agent.user = "sandbox";
          tsurf.agent.home = "/srv/sandbox";
        }
      ];

      packages.${system} = {
        deploy-rs = deploy-rs.packages.${system}.default;

        # NixOS VM test for sandbox user privilege separation (requires KVM).
        # Run: nix build .#vm-test-sandbox
        vm-test-sandbox = import ./tests/vm/sandbox-behavioral.nix {
          inherit pkgs lib;
        };

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

            HOST="tsurf"
            BATS_FILES=()

            while [[ $# -gt 0 ]]; do
              case "$1" in
                --host|-h)
                  HOST="$2"
                  shift 2
                  ;;
                tsurf|tsurf-dev)
                  HOST="$1"
                  shift
                  ;;
                *)
                  BATS_FILES+=("$1")
                  shift
                  ;;
              esac
            done

            export TSURF_TEST_HOST="$HOST"
            case "$HOST" in
              tsurf)
                export TSURF_TEST_AGENT_USER="${self.nixosConfigurations."eval-tsurf".config.tsurf.agent.user}"
                ;;
              tsurf-dev|ovh)
                export TSURF_TEST_AGENT_USER="${self.nixosConfigurations."eval-tsurf-dev".config.tsurf.agent.user}"
                ;;
            esac
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

      apps.${system} = {
        test-live = {
          type = "app";
          program = "${self.packages.${system}.test-live}/bin/test-live";
        };

        # @decision BOOT-06: Pinned nixos-anywhere via flake.lock (supply-chain safety).
        nixos-anywhere = {
          type = "app";
          program = "${nixos-anywhere.packages.${system}.default}/bin/nixos-anywhere";
        };
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
          deployChecks =
            if self ? deploy && self.deploy ? nodes
            then deploy-rs.lib.${system}.deployChecks self.deploy
            else {};
        in
        deployChecks // evalChecks // {
          shellcheck-tests = pkgs.runCommandNoCC "shellcheck-tests" {
            nativeBuildInputs = [ pkgs.shellcheck ];
            src = ./.;
          } ''
            shellcheck "$src"/tests/lib/*.bash "$src"/scripts/run-tests.sh "$src"/scripts/sshd-liveness-check.sh "$src"/scripts/agent-wrapper.sh "$src"/extras/scripts/clone-repos.sh "$src"/extras/scripts/dev-agent.sh "$src"/scripts/sandbox-probe.sh
            # btrfs-rollback.sh runs in initrd (busybox) — skip shellcheck
            # SC2317: BATS @test blocks appear unreachable to shellcheck
            shellcheck --exclude=SC2317 "$src"/tests/live/*.bats
            touch "$out"
          '';
        };
    };
}
