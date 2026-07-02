# flake.nix
# Entrypoint for the tsurf NixOS configuration template.
# Defines inputs, eval fixtures, test infrastructure, and the tsurf overlay.
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    flake-parts.url = "github:hercules-ci/flake-parts";
    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    llm-agents = {
      url = "github:numtide/llm-agents.nix";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-parts.follows = "flake-parts";
      inputs.treefmt-nix.follows = "treefmt-nix";
    };
    deploy-rs = {
      url = "github:serokell/deploy-rs";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    impermanence = {
      url = "github:nix-community/impermanence";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "home-manager";
    };
    srvos = {
      url = "github:nix-community/srvos";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixos-anywhere = {
      url = "github:nix-community/nixos-anywhere";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.disko.follows = "disko";
      inputs.treefmt-nix.follows = "treefmt-nix";
    };
    nix-mineral = {
      url = "github:cynicsketch/nix-mineral";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-parts.follows = "flake-parts";
    };
  };

  # Private overlay: add your private inputs (parts, personal services, etc.) in a separate private flake that imports this one.
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
      nixos-anywhere,
      nix-mineral,
      ...
    }@inputs:
    let
      system = "x86_64-linux";
      lib = nixpkgs.lib;
      pkgs = nixpkgs.legacyPackages.${system};
      tsurfOverlay = final: _prev: {
        nono = final.callPackage ./packages/nono.nix { };
        iron-proxy = final.callPackage ./packages/iron-proxy.nix { };
      };

      commonModules = [
        srvos.nixosModules.server
        disko.nixosModules.disko
        impermanence.nixosModules.impermanence
        sops-nix.nixosModules.sops
        home-manager.nixosModules.home-manager
        nix-mineral.nixosModules.nix-mineral
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

      tsurfNixosModules = rec {
        base = ./modules/base.nix;
        boot = ./modules/boot.nix;
        users = ./modules/users.nix;
        networking = ./modules/networking.nix;
        secrets = ./modules/secrets.nix;
        impermanence = ./modules/impermanence.nix;
        agent-compute = ./modules/agent-compute.nix;
        agent-egress-proxy = ./modules/agent-egress-proxy.nix;
        agent-launcher = ./modules/agent-launcher.nix;
        agent-sandbox = ./modules/agent-sandbox.nix;
        nono = ./modules/nono.nix;
        headscale = ./modules/headscale.nix;
        harmonia-cache = ./modules/harmonia-cache.nix;

        common =
          { ... }:
          {
            imports = commonModules;
          };

        core =
          { ... }:
          {
            imports = [
              common
              base
              boot
              users
              networking
              impermanence
            ];
          };

        agent-host =
          { lib, ... }:
          {
            imports = [
              core
              agent-compute
              agent-egress-proxy
              nono
              agent-launcher
              agent-sandbox
            ];

            services.agentCompute.enable = lib.mkDefault true;
            services.nonoSandbox.enable = lib.mkDefault true;
            services.agentSandbox.enable = lib.mkDefault true;
          };

        agent-host-with-secrets =
          { ... }:
          {
            imports = [
              agent-host
              secrets
            ];
          };

        service-host =
          { ... }:
          {
            imports = [
              core
              headscale
              ./extras/restic.nix
            ];
          };

        service-host-with-secrets =
          { ... }:
          {
            imports = [
              service-host
              secrets
            ];
          };
      };

      # Eval fixtures: inject allowUnsafePlaceholders so the public template evaluates
      # without real credentials. Host source files are secure by default (flag not set).
      # These are exported only as clearly named eval-only outputs, never as deploy
      # targets.
      mkEvalFixture =
        hostDir: extraModules:
        nixpkgs.lib.nixosSystem {
          inherit system;
          specialArgs = { inherit inputs; };
          modules =
            commonModules
            ++ [
              hostDir
              { tsurf.template.allowUnsafePlaceholders = true; }
            ]
            ++ extraModules;
        };

      evalChecks = import ./tests/eval/config-checks.nix { inherit self pkgs lib; };
    in
    {
      overlays.default = tsurfOverlay;
      nixosModules = tsurfNixosModules;

      nixosConfigurations."eval-services" = mkEvalFixture ./hosts/services [ ];
      nixosConfigurations."eval-dev" = mkEvalFixture ./hosts/dev [ ];
      nixosConfigurations."eval-dev-alt-agent" = mkEvalFixture ./hosts/dev [
        {
          tsurf.agent.user = "sandbox";
          tsurf.agent.home = "/srv/sandbox";
        }
      ];
      nixosConfigurations."eval-dev-extra-deny" = mkEvalFixture ./hosts/dev [
        {
          services.agentLauncher.agents.review-check = {
            command = "hello";
            package = pkgs.hello;
            wrapperName = "review-check";
            nonoProfile.extraDeny = [ "/custom-deny" ];
          };
        }
      ];
      nixosConfigurations."eval-dev-openrouter" = mkEvalFixture ./hosts/dev [
        ./extras/codex-openrouter.nix
        {
          services.codexOpenRouterAgent.enable = true;
        }
      ];

      packages.${system} = {
        deploy-rs = deploy-rs.packages.${system}.default;
        iron-proxy = pkgs.callPackage ./packages/iron-proxy.nix { };
        nono = pkgs.callPackage ./packages/nono.nix { };

        # NixOS VM test for sandbox user privilege separation (requires KVM).
        # Run: nix build .#vm-test-sandbox
        vm-test-sandbox = import ./tests/vm/sandbox-behavioral.nix {
          inherit pkgs lib;
          impermanenceModule = impermanence.nixosModules.impermanence;
        };
        vm-test-credential-proxy = import ./tests/vm/credential-proxy.nix {
          inherit pkgs lib;
          impermanenceModule = impermanence.nixosModules.impermanence;
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
          text =
            let
              evalFixtures = lib.filterAttrs (
                name: _: lib.hasPrefix "eval-" name && !(lib.hasSuffix "-alt-agent" name)
              ) self.nixosConfigurations;
              hostCaseAttrs = lib.foldl' (
                acc: sys:
                let
                  hostName = sys.config.networking.hostName;
                  hasSandbox = lib.attrByPath [ "config" "services" "agentSandbox" "enable" ] false sys;
                in
                acc
                // {
                  ${hostName} = {
                    agentUser = sys.config.tsurf.agent.user;
                    inherit hasSandbox;
                  };
                }
              ) { } (builtins.attrValues evalFixtures);
              hostCases = lib.concatStringsSep "\n" (
                lib.mapAttrsToList (
                  hostName: hostCfg:
                  "              ${hostName}) export TSURF_TEST_AGENT_USER=\"${hostCfg.agentUser}\"; export TSURF_TEST_HAS_SANDBOX=\"${
                                  if hostCfg.hasSandbox then "1" else "0"
                                }\" ;;"
                ) hostCaseAttrs
              );
            in
            ''
                          #!/usr/bin/env bash
                          set -euo pipefail

                          HOST=""
                          BATS_FILES=()

                          while [[ $# -gt 0 ]]; do
                            case "$1" in
                              --host|-h)
                                HOST="$2"
                                shift 2
                                ;;
                              *)
                                BATS_FILES+=("$1")
                                shift
                                ;;
                            esac
                          done

                          if [[ -z "$HOST" ]]; then
                            echo "Usage: test-live -- --host <hostname> [test-files...]"
                            exit 1
                          fi

                          export TSURF_TEST_HOST="$HOST"
                          case "$HOST" in
              ${hostCases}
                            *) echo "WARNING: unknown host '$HOST' — TSURF_TEST_AGENT_USER not set" ;;
                          esac
                          export BATS_LIB_PATH="${pkgs.bats.libraries.bats-support}/share/bats:${pkgs.bats.libraries.bats-assert}/share/bats"

                          tests_dir="${./tests/live}"
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

      packages.aarch64-darwin = {
        deploy-rs = deploy-rs.packages.aarch64-darwin.default;
      };

      apps.${system} = {
        test-live = {
          type = "app";
          program = "${self.packages.${system}.test-live}/bin/test-live";
          meta.description = "Run live BATS tests against a target host";
        };

        persistence-audit =
          let
            getDirs = cfg: map (d: d.directory) cfg.environment.persistence."/persist".directories;
            getFiles = cfg: map (f: f.file) cfg.environment.persistence."/persist".files;
            sorted = builtins.sort (a: b: a < b);
            formatList = lst: lib.concatMapStringsSep "\n" (p: "  " + p) (sorted lst);
            sections = lib.concatStringsSep "\n\n" (
              lib.mapAttrsToList (
                name: sys:
                let
                  cfg = sys.config;
                in
                ''
                  === ${name} (${cfg.networking.hostName}) ===
                  Directories:
                  ${formatList (getDirs cfg)}

                  Files:
                  ${formatList (getFiles cfg)}''
              ) (lib.filterAttrs (name: _: lib.hasPrefix "eval-" name) self.nixosConfigurations)
            );
            script = pkgs.writeShellApplication {
              name = "persistence-audit";
              text = ''
                              cat <<'EOF'
                ${sections}
                EOF
              '';
            };
          in
          {
            type = "app";
            program = "${script}/bin/persistence-audit";
            meta.description = "Print merged persistence paths for all eval fixtures";
          };
        tsurf-init =
          let
            script = pkgs.writeShellApplication {
              name = "tsurf-init";
              runtimeInputs = with pkgs; [
                openssh
                coreutils
              ];
              text = builtins.readFile ./scripts/tsurf-init.sh;
            };
          in
          {
            type = "app";
            program = "${script}/bin/tsurf-init";
            meta.description = "Bootstrap tsurf: generate SSH key, validate setup";
          };

        tsurf-status =
          let
            script = pkgs.writeShellApplication {
              name = "tsurf-status";
              runtimeInputs = with pkgs; [
                openssh
                coreutils
                nix
                jq
              ];
              text = builtins.readFile ./scripts/tsurf-status.sh;
            };
          in
          {
            type = "app";
            program = "${script}/bin/tsurf-status";
            meta.description = "Check systemd service status on tsurf hosts";
          };

        # @decision BOOT-06: Pinned nixos-anywhere via flake.lock (supply-chain safety).
        nixos-anywhere = {
          type = "app";
          program = "${nixos-anywhere.packages.${system}.default}/bin/nixos-anywhere";
          meta.description = "Pinned nixos-anywhere bootstrap helper";
        };
      };

      devShells.${system}.default = pkgs.mkShell {
        packages = [
          pkgs.sops
          pkgs.age
          pkgs.nixfmt
          pkgs.deadnix
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
            if self ? deploy && self.deploy ? nodes then
              deploy-rs.lib.${system}.deployChecks self.deploy
            else
              { };
        in
        deployChecks
        // evalChecks
        // {
          nixfmt-check =
            pkgs.runCommand "nixfmt-check"
              {
                nativeBuildInputs = [
                  pkgs.findutils
                  pkgs.nixfmt
                ];
                src = ./.;
              }
              ''
                find "$src" -type f -name '*.nix' -print0 | xargs -0 nixfmt --check
                touch "$out"
              '';
          deadnix-check =
            pkgs.runCommand "deadnix-check"
              {
                nativeBuildInputs = [ pkgs.deadnix ];
                src = ./.;
              }
              ''
                deadnix --fail "$src"
                touch "$out"
              '';
          shellcheck-tests =
            pkgs.runCommand "shellcheck-tests"
              {
                nativeBuildInputs = [ pkgs.shellcheck ];
                src = ./.;
              }
              ''
                shellcheck "$src"/tests/lib/*.bash "$src"/tests/unit/*.bash "$src"/scripts/run-tests.sh "$src"/scripts/agent-wrapper.sh "$src"/scripts/deploy.sh "$src"/scripts/deploy-detached.sh "$src"/scripts/sandbox-probe.sh "$src"/scripts/tsurf-init.sh "$src"/scripts/tsurf-status.sh
                # btrfs-rollback.sh runs in initrd (busybox) — skip shellcheck
                # SC2317: BATS @test blocks appear unreachable to shellcheck
                shellcheck --exclude=SC2317 "$src"/tests/live/*.bats
                touch "$out"
              '';
          unit-tests =
            pkgs.runCommand "unit-tests"
              {
                nativeBuildInputs = [
                  pkgs.bash
                  pkgs.openssh
                ];
                src = ./.;
              }
              ''
                export TSURF_TEST_TMPDIR="$TMPDIR/tsurf-unit-tests"
                mkdir -p "$TSURF_TEST_TMPDIR"
                for test in "$src"/tests/unit/*.bash; do
                  bash "$test"
                done
                touch "$out"
              '';
        };
    };
}
