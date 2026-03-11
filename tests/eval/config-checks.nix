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

  # --- Remote access safety checks (both hosts) ---
  # These mirror the NixOS assertions in networking.nix but give named PASS/FAIL visibility
  # during `nix flake check`. If assertions fire, the eval check fails too, but the check
  # name makes it obvious which invariant broke.

  remote-access-neurosys = mkCheck
    "remote-access-neurosys"
    "neurosys remote access invariants: sshd + tailscale + root SSH keys + port 22"
    "neurosys remote access broken: sshd=${builtins.toJSON neurosysCfg.services.openssh.enable} tailscale=${builtins.toJSON neurosysCfg.services.tailscale.enable} rootKeys=${builtins.toJSON (neurosysCfg.users.users.root.openssh.authorizedKeys.keys != [])} port22=${builtins.toJSON (builtins.elem 22 neurosysCfg.networking.firewall.allowedTCPPorts)}"
    (neurosysCfg.services.openssh.enable
     && neurosysCfg.services.tailscale.enable
     && neurosysCfg.users.users.root.openssh.authorizedKeys.keys != []
     && (builtins.elem 22 neurosysCfg.networking.firewall.allowedTCPPorts
         || neurosysCfg.services.openssh.openFirewall));

  remote-access-ovh = mkCheck
    "remote-access-ovh"
    "ovh remote access invariants: sshd + tailscale + root SSH keys + port 22"
    "ovh remote access broken: sshd=${builtins.toJSON ovhCfg.services.openssh.enable} tailscale=${builtins.toJSON ovhCfg.services.tailscale.enable} rootKeys=${builtins.toJSON (ovhCfg.users.users.root.openssh.authorizedKeys.keys != [])} port22=${builtins.toJSON (builtins.elem 22 ovhCfg.networking.firewall.allowedTCPPorts)}"
    (ovhCfg.services.openssh.enable
     && ovhCfg.services.tailscale.enable
     && ovhCfg.users.users.root.openssh.authorizedKeys.keys != []
     && (builtins.elem 22 ovhCfg.networking.firewall.allowedTCPPorts
         || ovhCfg.services.openssh.openFirewall));

  # --- Phase 70: Lockout prevention checks ---

  break-glass-key-neurosys = mkCheck
    "break-glass-key-neurosys"
    "neurosys root has break-glass emergency SSH key"
    "neurosys root is missing break-glass emergency SSH key (import modules/break-glass-ssh.nix)"
    (builtins.any (k: lib.hasInfix "break-glass-emergency" k)
      neurosysCfg.users.users.root.openssh.authorizedKeys.keys);

  break-glass-key-ovh = mkCheck
    "break-glass-key-ovh"
    "ovh root has break-glass emergency SSH key"
    "ovh root is missing break-glass emergency SSH key (import modules/break-glass-ssh.nix)"
    (builtins.any (k: lib.hasInfix "break-glass-emergency" k)
      ovhCfg.users.users.root.openssh.authorizedKeys.keys);

  ssh-authorized-keys-fallback = mkCheck
    "ssh-authorized-keys-fallback"
    "neurosys sshd checks .ssh/authorized_keys (NET-14 impermanence fallback)"
    "neurosys authorizedKeysFiles is missing .ssh/authorized_keys — NET-14 fallback broken"
    (builtins.any (f: f == ".ssh/authorized_keys")
      neurosysCfg.services.openssh.authorizedKeysFiles);

  ssh-host-key-persisted = mkCheck
    "ssh-host-key-persisted"
    "neurosys SSH host key is declared in impermanence persistence"
    "neurosys SSH host key not found in impermanence files — sshd may fail on reboot"
    (let
      source = builtins.readFile ../../modules/impermanence.nix;
    in
      lib.hasInfix "\"/etc/ssh/ssh_host_ed25519_key\"" source);

  ssh-canary-neurosys = mkCheck
    "ssh-canary-neurosys"
    "neurosys ssh-canary timer is defined"
    "neurosys ssh-canary timer is missing — import modules/ssh-canary.nix"
    (builtins.hasAttr "ssh-canary" neurosysCfg.systemd.timers);

  ssh-canary-ovh = mkCheck
    "ssh-canary-ovh"
    "ovh ssh-canary timer is defined"
    "ovh ssh-canary timer is missing — import modules/ssh-canary.nix"
    (builtins.hasAttr "ssh-canary" ovhCfg.systemd.timers);

  agent-sandbox-ovh-enabled = mkCheck
    "agent-sandbox-ovh-enabled"
    "ovh agent sandbox wrappers are enabled"
    "ovh services.agentSandbox.enable is false — dev agents run unsandboxed"
    ovhCfg.services.agentSandbox.enable;

  agent-sandbox-module-has-bwrap =
    let
      source = builtins.readFile ../../modules/agent-sandbox.nix;
    in
    mkCheck
      "agent-sandbox-module-has-bwrap"
      "agent-sandbox module references bubblewrap"
      "agent-sandbox module does not reference bubblewrap — sandbox is broken"
      (lib.hasInfix "bubblewrap" source);

  agent-audit-dir = mkCheck
    "agent-audit-dir"
    "agent-audit tmpfiles directory is declared"
    "agent-audit tmpfiles directory missing — /data/projects/.agent-audit won't be created"
    (builtins.any (r: lib.hasInfix ".agent-audit" r) ovhCfg.systemd.tmpfiles.rules);
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
