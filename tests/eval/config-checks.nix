# tests/eval/config-checks.nix — Nix eval-time assertions for tsurf (neurosys and neurosys-dev hosts).
# @decision TEST-48-01: Keep checks purely eval-time with runCommandNoCC to catch regressions offline.
{ self, pkgs, lib }:
let
  neurosysCfg = self.nixosConfigurations.neurosys.config;
  devCfg = self.nixosConfigurations.neurosys-dev.config;
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

  eval-neurosys-dev = pkgs.runCommandNoCC "eval-neurosys-dev" { } ''
    echo "neurosys-dev config evaluates: ${self.nixosConfigurations.neurosys-dev.config.system.build.toplevel}"
    touch "$out"
  '';

  # Ports are conditional: 22000 on syncthing.enable, 80/443 on nginx.enable.
  # Public template has no nginx; syncthing is imported by both hosts.
  firewall-ports-neurosys =
    let
      actual = builtins.sort builtins.lessThan neurosysCfg.networking.firewall.allowedTCPPorts;
      expected = [ 22 ]
        ++ lib.optionals neurosysCfg.services.syncthing.enable [ 22000 ]
        ++ lib.optionals neurosysCfg.services.nginx.enable [ 80 443 ];
    in
    mkCheck
      "firewall-ports-neurosys"
      "neurosys firewall ports match syncthing/nginx state"
      "neurosys allowedTCPPorts=${builtins.toJSON actual} expected=${builtins.toJSON expected}"
      (actual == expected);

  firewall-ports-ovh =
    let
      actual = builtins.sort builtins.lessThan devCfg.networking.firewall.allowedTCPPorts;
      expected = [ 22 ]
        ++ lib.optionals devCfg.services.syncthing.enable [ 22000 ]
        ++ lib.optionals devCfg.services.nginx.enable [ 80 443 ];
    in
    mkCheck
      "firewall-ports-ovh"
      "ovh firewall ports match syncthing/nginx state"
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
    echo "PASS: trusted interfaces include tailscale0"
    touch "$out"
  '';

  expected-services-neurosys =
    let
      expectedServices = [
        "tailscaled"
        "syncthing"
        "nix-dashboard"
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
      missing = builtins.filter (name: !(builtins.hasAttr name devCfg.systemd.services)) expectedServices;
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
        "/home/dev/.ssh"
        "/root/.ssh"
        "/data/projects"
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

  has-nono-sandbox-option = mkCheck
    "has-nono-sandbox-option"
    "services.nonoSandbox option is defined (module imported)"
    "services.nonoSandbox option is missing"
    (builtins.hasAttr "nonoSandbox" devCfg.services);

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
    "ovh remote access broken: sshd=${builtins.toJSON devCfg.services.openssh.enable} tailscale=${builtins.toJSON devCfg.services.tailscale.enable} rootKeys=${builtins.toJSON (devCfg.users.users.root.openssh.authorizedKeys.keys != [])} port22=${builtins.toJSON (builtins.elem 22 devCfg.networking.firewall.allowedTCPPorts)}"
    (devCfg.services.openssh.enable
     && devCfg.services.tailscale.enable
     && devCfg.users.users.root.openssh.authorizedKeys.keys != []
     && (builtins.elem 22 devCfg.networking.firewall.allowedTCPPorts
         || devCfg.services.openssh.openFirewall));

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
      devCfg.users.users.root.openssh.authorizedKeys.keys);

  break-glass-key-unique-neurosys =
    let
      keys = neurosysCfg.users.users.root.openssh.authorizedKeys.keys;
      keyMaterials = map (k: builtins.elemAt (lib.splitString " " k) 1) keys;
      unique = lib.unique keyMaterials;
    in
    mkCheck
      "break-glass-key-unique-neurosys"
      "neurosys root SSH keys all have distinct key material"
      "neurosys root has duplicate SSH key material — break-glass must differ from bootstrap"
      (builtins.length keyMaterials == builtins.length unique);

  break-glass-key-unique-ovh =
    let
      keys = devCfg.users.users.root.openssh.authorizedKeys.keys;
      keyMaterials = map (k: builtins.elemAt (lib.splitString " " k) 1) keys;
      unique = lib.unique keyMaterials;
    in
    mkCheck
      "break-glass-key-unique-ovh"
      "ovh root SSH keys all have distinct key material"
      "ovh root has duplicate SSH key material — break-glass must differ from bootstrap"
      (builtins.length keyMaterials == builtins.length unique);

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

  sshd-liveness-check-neurosys = mkCheck
    "sshd-liveness-check-neurosys"
    "neurosys sshd-liveness-check timer is defined"
    "neurosys sshd-liveness-check timer is missing — import modules/sshd-liveness-check.nix"
    (builtins.hasAttr "sshd-liveness-check" neurosysCfg.systemd.timers);

  sshd-liveness-check-ovh = mkCheck
    "sshd-liveness-check-ovh"
    "ovh sshd-liveness-check timer is defined"
    "ovh sshd-liveness-check timer is missing — import modules/sshd-liveness-check.nix"
    (builtins.hasAttr "sshd-liveness-check" devCfg.systemd.timers);

  agent-sandbox-ovh-enabled = mkCheck
    "agent-sandbox-ovh-enabled"
    "ovh agent sandbox wrappers are enabled"
    "ovh services.agentSandbox.enable is false — dev agents run unsandboxed"
    devCfg.services.agentSandbox.enable;

  agent-egress-ovh = mkCheck
    "agent-egress-ovh"
    "ovh agent egress nftables table is defined"
    "ovh agent-egress nftables table missing"
    (builtins.hasAttr "agent-egress" devCfg.networking.nftables.tables);

  agent-sandbox-module-has-nono =
    let
      source = builtins.readFile ../../modules/agent-sandbox.nix;
    in
    mkCheck
      "agent-sandbox-module-has-nono"
      "agent-sandbox module references nono"
      "agent-sandbox module does not reference nono — sandbox is broken"
      (lib.hasInfix "nono" source);

  pi-coding-agent-in-packages = mkCheck
    "pi-coding-agent-in-packages"
    "pi-coding-agent is in ovh systemPackages"
    "pi-coding-agent missing from ovh systemPackages — check agent-compute.nix"
    (builtins.any (p: (p.pname or "") == "pi-coding-agent")
      devCfg.environment.systemPackages);

  pi-sandbox-wrapper-exists =
    let
      source = builtins.readFile ../../modules/agent-sandbox.nix;
    in
    mkCheck
      "pi-sandbox-wrapper-exists"
      "agent-sandbox module defines pi-sandboxed wrapper"
      "agent-sandbox module does not define pi-sandboxed — pi is unsandboxed"
      (lib.hasInfix "pi-sandboxed" source);

  nono-profile-has-pi =
    let
      source = builtins.readFile ../../modules/nono.nix;
    in
    mkCheck
      "nono-profile-has-pi"
      "nono neurosys profile includes ~/.pi in filesystem allow list"
      "nono neurosys profile missing ~/.pi — pi config inaccessible in sandbox"
      (lib.hasInfix ".pi" source);

  nono-sandbox-ovh-enabled = mkCheck
    "nono-sandbox-ovh-enabled"
    "ovh nono sandbox module is enabled"
    "ovh services.nonoSandbox.enable is false — nono not active"
    devCfg.services.nonoSandbox.enable;

  agent-audit-dir = mkCheck
    "agent-audit-dir"
    "agent-audit tmpfiles directory is declared"
    "agent-audit tmpfiles directory missing — /data/projects/.agent-audit won't be created"
    (builtins.any (r: lib.hasInfix ".agent-audit" r) devCfg.systemd.tmpfiles.rules);

  syncthing-mesh-option = mkCheck
    "syncthing-mesh-option"
    "tsurf.syncthing.mesh option exists on both hosts"
    "tsurf.syncthing.mesh option missing — import modules/syncthing.nix"
    (builtins.hasAttr "syncthing" neurosysCfg.tsurf
     && builtins.hasAttr "mesh" neurosysCfg.tsurf.syncthing
     && builtins.hasAttr "syncthing" devCfg.tsurf
     && builtins.hasAttr "mesh" devCfg.tsurf.syncthing);

  # --- Phase 106: Template safety + opt-in checks ---

  template-mode-neurosys = mkCheck
    "template-mode-neurosys"
    "neurosys host has allowUnsafePlaceholders = true (template mode)"
    "neurosys host missing allowUnsafePlaceholders — public template won't evaluate"
    neurosysCfg.tsurf.template.allowUnsafePlaceholders;

  template-mode-ovh = mkCheck
    "template-mode-ovh"
    "ovh host has allowUnsafePlaceholders = true (template mode)"
    "ovh host missing allowUnsafePlaceholders — public template won't evaluate"
    devCfg.tsurf.template.allowUnsafePlaceholders;

  dev-agent-not-in-template = mkCheck
    "dev-agent-not-in-template"
    "dev-agent service not defined in public ovh config (opt-in works)"
    "dev-agent service defined in public ovh config — should be opt-in only"
    (!(builtins.hasAttr "dev-agent" devCfg.systemd.services));

  restic-opt-in = mkCheck
    "restic-opt-in"
    "restic backup not active in public neurosys config (opt-in works)"
    "restic backup active in public template — services.resticStarter.enable should be false"
    (!neurosysCfg.services.resticStarter.enable);

  # Stale-phrase check: banned phrases must not appear in key docs.
  # Prevents reintroduction of outdated security claims.
  stale-phrases-claude-md =
    let
      source = builtins.readFile ../../CLAUDE.md;
    in
    mkCheck
      "stale-phrases-claude-md"
      "CLAUDE.md contains no banned stale phrases"
      "CLAUDE.md contains stale phrase (phantom token / credential proxy / sibling repos readable)"
      (!(lib.hasInfix "phantom token" source)
       && !(lib.hasInfix "sibling repos readable" source)
       && !(lib.hasInfix "credential proxy" source));

  stale-phrases-readme =
    let
      source = builtins.readFile ../../README.md;
    in
    mkCheck
      "stale-phrases-readme"
      "README.md contains no banned stale phrases"
      "README.md contains stale phrase (phantom token / sibling repos readable)"
      (!(lib.hasInfix "phantom token" source)
       && !(lib.hasInfix "sibling repos readable" source));

  dashboard-security-headers =
    let
      serverSrc = builtins.readFile ../../scripts/dashboard-server.py;
      hasHeader = header: lib.hasInfix header serverSrc;
    in
    mkCheck
      "dashboard-security-headers"
      "dashboard server includes security response headers"
      "dashboard-server.py missing security headers (X-Content-Type-Options, X-Frame-Options, Referrer-Policy)"
      (hasHeader "X-Content-Type-Options" && hasHeader "X-Frame-Options" && hasHeader "Referrer-Policy");

  dashboard-no-innerhtml-xss =
    let
      htmlSrc = builtins.readFile ../../scripts/dashboard-frontend.html;
    in
    mkCheck
      "dashboard-no-innerhtml-xss"
      "dashboard frontend has no innerHTML XSS sinks"
      "dashboard-frontend.html still uses innerHTML — use textContent/createElement instead"
      (!(lib.hasInfix ".innerHTML =" htmlSrc));

  deploy-no-repo-source =
    let
      deploySrc = builtins.readFile ../../scripts/deploy.sh;
    in
    mkCheck
      "deploy-no-repo-source"
      "deploy.sh has no repo-controlled source calls"
      "deploy.sh sources repo-controlled scripts — remove source calls for deploy-post.sh or similar"
      (!(lib.hasInfix "source \"$FLAKE_DIR" deploySrc));

}

# --- Private overlay test extension pattern ---
#
# The private overlay (private-tsurf) extends these checks by importing
# this file and appending private-specific assertions, for example:
#
#   # In private-tsurf/tests/eval/private-checks.nix:
#   # { self, pkgs, lib, inputs }:
#   # let
#   #   publicChecks = import "${inputs.tsurf}/tests/eval/config-checks.nix" { inherit self pkgs lib; };
#   #   privateCfg = self.nixosConfigurations.neurosys.config;
#   # in publicChecks // {
#   #   agent-fleet-ports = ...; # private agent fleet/proxy assertions
#   #   nginx-vhosts = ...;      # private reverse-proxy checks
#   #   acme-domains = ...;      # private certificate domain coverage
#   # };
#
# Private live tests follow the same pattern under private-tsurf/tests/live/.
