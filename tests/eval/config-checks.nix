# tests/eval/config-checks.nix — Nix eval-time assertions for neurosys and ovh.
# @decision TEST-48-01: Keep checks purely eval-time with runCommandNoCC to catch regressions offline.
{ self, pkgs, lib }:
let
  neurosysCfg = self.nixosConfigurations.neurosys.config;
  ovhCfg = self.nixosConfigurations.ovh.config;
  jq = "${pkgs.jq}/bin/jq";

  mkCheck = name: passMessage: failMessage: condition:
    pkgs.runCommandNoCC name { } ''
      ${if condition then ''
        echo "PASS: ${passMessage}"
        touch "$out"
      '' else ''
        echo "FAIL: ${failMessage}"
        exit 1
      ''}
    '';
in
{
  eval-neurosys = pkgs.runCommandNoCC "eval-neurosys" { } ''
    echo "neurosys config evaluates: ${self.nixosConfigurations.neurosys.config.system.build.toplevel}"
    touch "$out"
  '';

  eval-ovh = pkgs.runCommandNoCC "eval-ovh" { } ''
    echo "ovh config evaluates: ${self.nixosConfigurations.ovh.config.system.build.toplevel}"
    touch "$out"
  '';

  firewall-ports-neurosys =
    let
      actual = builtins.sort builtins.lessThan neurosysCfg.networking.firewall.allowedTCPPorts;
      expected = [ 22 80 443 22000 ];
    in
    mkCheck
      "firewall-ports-neurosys"
      "neurosys firewall ports are [22,80,443,22000]"
      "neurosys allowedTCPPorts=${builtins.toJSON actual} expected=${builtins.toJSON expected}"
      (actual == expected);

  firewall-ports-ovh =
    let
      actual = builtins.sort builtins.lessThan ovhCfg.networking.firewall.allowedTCPPorts;
      expected = [ 22 80 443 22000 ];
    in
    mkCheck
      "firewall-ports-ovh"
      "ovh firewall ports are [22,80,443,22000]"
      "ovh allowedTCPPorts=${builtins.toJSON actual} expected=${builtins.toJSON expected}"
      (actual == expected);

  trusted-interfaces-neurosys = pkgs.runCommandNoCC "trusted-interfaces-neurosys" { } ''
    actual='${builtins.toJSON neurosysCfg.networking.firewall.trustedInterfaces}'
    require_iface() {
      iface="$1"
      if ! echo "$actual" | ${jq} -e "index(\"$iface\")" > /dev/null 2>&1; then
        echo "FAIL: trustedInterfaces missing '$iface' (actual: $actual)"
        exit 1
      fi
    }

    require_iface tailscale0
    if ${if neurosysCfg.virtualisation.docker.enable then "true" else "false"}; then
      require_iface docker0
      echo "PASS: trusted interfaces include tailscale0 and docker0 (docker enabled)"
    else
      echo "PASS: trusted interfaces include tailscale0 (docker disabled)"
    fi
    touch "$out"
  '';

  expected-services-neurosys =
    let
      expectedServices = [
        "tailscaled"
        "syncthing"
        "nix-dashboard"
        "agent-canvas"
      ];
      missing = builtins.filter (name: !(builtins.hasAttr name neurosysCfg.systemd.services)) expectedServices;
    in
    mkCheck
      "expected-services-neurosys"
      "all expected neurosys services are defined"
      "missing neurosys services: ${builtins.concatStringsSep ", " missing}"
      (missing == [ ]);

  expected-services-ovh =
    let
      expectedServices = [
        "tailscaled"
        "syncthing"
        "docker"
      ];
      missing = builtins.filter (name: !(builtins.hasAttr name ovhCfg.systemd.services)) expectedServices;
    in
    mkCheck
      "expected-services-ovh"
      "all expected ovh services are defined"
      "missing ovh services: ${builtins.concatStringsSep ", " missing}"
      (missing == [ ]);

  expected-packages-neurosys =
    let
      sysPkgs = neurosysCfg.environment.systemPackages;
      expectedPkgs = {
        git = pkgs.git;
        curl = pkgs.curl;
        jq = pkgs.jq;
        ripgrep = pkgs.ripgrep;
        openssh = pkgs.openssh;
        tailscale = pkgs.tailscale;
      };
      missing = lib.filterAttrs (_: drv: !(builtins.any (p: p == drv) sysPkgs)) expectedPkgs;
      missingNames = builtins.attrNames missing;
    in
    mkCheck
      "expected-packages-neurosys"
      "required packages are present in neurosys systemPackages"
      "missing packages: ${builtins.concatStringsSep ", " missingNames}"
      (missingNames == [ ]);

  ssh-no-password = mkCheck
    "ssh-no-password"
    "SSH PasswordAuthentication is disabled"
    "SSH PasswordAuthentication is enabled"
    (neurosysCfg.services.openssh.settings.PasswordAuthentication == false);

  ssh-ed25519-only =
    let
      hostKeyTypes = map (k: k.type) neurosysCfg.services.openssh.hostKeys;
    in
    mkCheck
      "ssh-ed25519-only"
      "SSH host key types are ed25519 only"
      "SSH host key types=${builtins.toJSON hostKeyTypes}, expected [\"ed25519\"]"
      (hostKeyTypes == [ "ed25519" ]);

  docker-no-iptables = mkCheck
    "docker-no-iptables"
    "Docker daemon uses iptables=false"
    "Docker daemon iptables is not false"
    (neurosysCfg.virtualisation.docker.daemon.settings.iptables == false);

  tailscale-enabled = mkCheck
    "tailscale-enabled"
    "Tailscale service is enabled"
    "Tailscale service is disabled"
    neurosysCfg.services.tailscale.enable;

  # Keep this source-based so we do not force full evaluation of the deprecated
  # impermanence option internals on this branch.
  impermanence-paths =
    let
      source = builtins.readFile ../../modules/impermanence.nix;
      criticalPaths = [
        "/var/lib/nixos"
        "/var/lib/tailscale"
        "/home/dev"
        "/data"
      ];
      missing = builtins.filter (path: !(lib.hasInfix "\"${path}\"" source)) criticalPaths;
    in
    mkCheck
      "impermanence-paths"
      "critical impermanence paths are declared"
      "missing impermanence paths: ${builtins.concatStringsSep ", " missing}"
      (missing == [ ]);

  impermanence-files =
    let
      source = builtins.readFile ../../modules/impermanence.nix;
      criticalFiles = [
        "/etc/machine-id"
        "/etc/ssh/ssh_host_ed25519_key"
      ];
      missing = builtins.filter (path: !(lib.hasInfix "\"${path}\"" source)) criticalFiles;
    in
    mkCheck
      "impermanence-files"
      "critical impermanence files are declared"
      "missing impermanence files: ${builtins.concatStringsSep ", " missing}"
      (missing == [ ]);

  nftables-enabled = mkCheck
    "nftables-enabled"
    "nftables backend is enabled"
    "nftables backend is disabled"
    neurosysCfg.networking.nftables.enable;

  metadata-block = mkCheck
    "metadata-block"
    "agent-metadata-block nftables table is defined"
    "agent-metadata-block nftables table not found"
    (builtins.hasAttr "agent-metadata-block" neurosysCfg.networking.nftables.tables);

  oci-backend-docker = mkCheck
    "oci-backend-docker"
    "OCI containers backend is docker"
    "OCI containers backend is ${neurosysCfg.virtualisation.oci-containers.backend}, expected docker"
    (neurosysCfg.virtualisation.oci-containers.backend == "docker");

  dashboard-enabled = mkCheck
    "dashboard-enabled"
    "nix-dashboard is enabled on port 8082"
    "nix-dashboard disabled or wrong port"
    (
      neurosysCfg.services.dashboard.enable
      && neurosysCfg.services.dashboard.listenPort == 8082
    );

  canvas-enabled = mkCheck
    "canvas-enabled"
    "agent-canvas is enabled on port 8083"
    "agent-canvas disabled or wrong port"
    (
      neurosysCfg.services.agentCanvas.enable
      && neurosysCfg.services.agentCanvas.listenPort == 8083
    );

  has-secret-proxy-option = mkCheck
    "has-secret-proxy-option"
    "services.secretProxy.services option is defined (module imported)"
    "services.secretProxy.services option is missing"
    (neurosysCfg.services.secretProxy.services == {});

  dashboard-entries =
    let
      entryCount =
        builtins.length (builtins.attrNames neurosysCfg.services.dashboard.entries);
    in
    mkCheck
      "dashboard-entries"
      "dashboard has ${toString entryCount} entries (>= 5)"
      "dashboard has too few entries: ${toString entryCount}"
      (entryCount >= 5);

  dashboard-manifest = pkgs.runCommandNoCC "dashboard-manifest" { } ''
    echo '${builtins.toJSON (builtins.fromJSON neurosysCfg.environment.etc."dashboard/manifest.json".text)}' \
      | ${jq} . > /dev/null
    echo "PASS: dashboard manifest is valid JSON"
    touch "$out"
  '';
}

# --- Private overlay test extension pattern ---
#
# The private overlay (private-neurosys) extends these checks by importing
# this file and appending private-specific assertions, for example:
#
#   # In private-neurosys/tests/eval/private-checks.nix:
#   # { self, pkgs, lib, inputs }:
#   # let
#   #   publicChecks = import "${inputs.neurosys}/tests/eval/config-checks.nix" { inherit self pkgs lib; };
#   #   privateCfg = self.nixosConfigurations.neurosys.config;
#   # in publicChecks // {
#   #   agent-fleet-ports = ...; # private agent fleet/proxy assertions
#   #   nginx-vhosts = ...;      # private reverse-proxy checks
#   #   acme-domains = ...;      # private certificate domain coverage
#   # };
#
# Private live tests follow the same pattern under private-neurosys/tests/live/.
