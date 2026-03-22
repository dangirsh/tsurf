# tests/eval/config-checks.nix — Nix eval-time assertions for tsurf (tsurf and tsurf-dev hosts).
# @decision TEST-48-01: Keep checks purely eval-time with runCommandNoCC to catch regressions offline.
{ self, pkgs, lib }:
let
  tsurfCfg = self.nixosConfigurations.tsurf.config;
  devCfg = self.nixosConfigurations.tsurf-dev.config;
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
  eval-tsurf = pkgs.runCommandNoCC "eval-tsurf" { } ''
    echo "tsurf config evaluates: ${self.nixosConfigurations.tsurf.config.system.build.toplevel}"
    touch "$out"
  '';

  eval-tsurf-dev = pkgs.runCommandNoCC "eval-tsurf-dev" { } ''
    echo "tsurf-dev config evaluates: ${self.nixosConfigurations.tsurf-dev.config.system.build.toplevel}"
    touch "$out"
  '';

  # Ports are conditional: 22000 on publicBep opt-in, 80/443 on nginx.enable.
  # Public template has no nginx and publicBep defaults to false.
  firewall-ports-tsurf =
    let
      actual = builtins.sort builtins.lessThan tsurfCfg.networking.firewall.allowedTCPPorts;
      expected = [ 22 ]
        ++ lib.optionals tsurfCfg.services.syncthingStarter.publicBep [ 22000 ]
        ++ lib.optionals tsurfCfg.services.nginx.enable [ 80 443 ];
    in
    mkCheck
      "firewall-ports-tsurf"
      "tsurf firewall ports match publicBep/nginx state"
      "tsurf allowedTCPPorts=${builtins.toJSON actual} expected=${builtins.toJSON expected}"
      (actual == expected);

  firewall-ports-ovh =
    let
      actual = builtins.sort builtins.lessThan devCfg.networking.firewall.allowedTCPPorts;
      expected = [ 22 ]
        ++ lib.optionals devCfg.services.syncthingStarter.publicBep [ 22000 ]
        ++ lib.optionals devCfg.services.nginx.enable [ 80 443 ];
    in
    mkCheck
      "firewall-ports-ovh"
      "ovh firewall ports match publicBep/nginx state"
      "ovh allowedTCPPorts=${builtins.toJSON actual} expected=${builtins.toJSON expected}"
      (actual == expected);

  # Phase 122: tailscale0 must NOT be in trustedInterfaces (localhost-first model).
  no-trusted-tailscale0-tsurf = mkCheck
    "no-trusted-tailscale0-tsurf"
    "tsurf does not have tailscale0 in trustedInterfaces (localhost-first model)"
    "SECURITY: tsurf has tailscale0 in trustedInterfaces — remove it, use per-service firewall.interfaces rules"
    (!(builtins.elem "tailscale0" tsurfCfg.networking.firewall.trustedInterfaces));

  no-trusted-tailscale0-ovh = mkCheck
    "no-trusted-tailscale0-ovh"
    "ovh does not have tailscale0 in trustedInterfaces (localhost-first model)"
    "SECURITY: ovh has tailscale0 in trustedInterfaces — remove it, use per-service firewall.interfaces rules"
    (!(builtins.elem "tailscale0" devCfg.networking.firewall.trustedInterfaces));

  no-accept-routes-tsurf = mkCheck
    "no-accept-routes-tsurf"
    "tsurf Tailscale extraUpFlags does not include --accept-routes"
    "tsurf Tailscale extraUpFlags contains --accept-routes — remove from default, add in overlay if needed"
    (!(builtins.elem "--accept-routes" tsurfCfg.services.tailscale.extraUpFlags));

  no-accept-routes-ovh = mkCheck
    "no-accept-routes-ovh"
    "ovh Tailscale extraUpFlags does not include --accept-routes"
    "ovh Tailscale extraUpFlags contains --accept-routes — remove from default, add in overlay if needed"
    (!(builtins.elem "--accept-routes" devCfg.services.tailscale.extraUpFlags));

  expected-services-tsurf =
    let
      expectedServices = [
        "tailscaled"
        "syncthing"
        "nix-dashboard"
      ];
      missing = builtins.filter (name: !(builtins.hasAttr name tsurfCfg.systemd.services)) expectedServices;
    in
    mkCheck
      "expected-services-tsurf"
      "all expected tsurf services are defined"
      "missing tsurf services: ${builtins.concatStringsSep ", " missing}"
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

  expected-packages-tsurf =
    let
      sysPkgs = tsurfCfg.environment.systemPackages;
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
      "expected-packages-tsurf"
      "required packages are present in tsurf systemPackages"
      "missing packages: ${builtins.concatStringsSep ", " missingNames}"
      (missingNames == [ ]);

  ssh-no-password = mkCheck
    "ssh-no-password"
    "SSH PasswordAuthentication is disabled"
    "SSH PasswordAuthentication is enabled"
    (tsurfCfg.services.openssh.settings.PasswordAuthentication == false);

  ssh-ed25519-only =
    let
      hostKeyTypes = map (k: k.type) tsurfCfg.services.openssh.hostKeys;
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
    (tsurfCfg.virtualisation.docker.daemon.settings.iptables == false);

  tailscale-enabled = mkCheck
    "tailscale-enabled"
    "Tailscale service is enabled"
    "Tailscale service is disabled"
    tsurfCfg.services.tailscale.enable;

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
    tsurfCfg.networking.nftables.enable;

  metadata-block = mkCheck
    "metadata-block"
    "agent-metadata-block nftables table is defined"
    "agent-metadata-block nftables table not found"
    (builtins.hasAttr "agent-metadata-block" tsurfCfg.networking.nftables.tables);

  oci-backend-docker = mkCheck
    "oci-backend-docker"
    "OCI containers backend is docker"
    "OCI containers backend is ${tsurfCfg.virtualisation.oci-containers.backend}, expected docker"
    (tsurfCfg.virtualisation.oci-containers.backend == "docker");

  dashboard-enabled = mkCheck
    "dashboard-enabled"
    "nix-dashboard is enabled on port 8082"
    "nix-dashboard disabled or wrong port"
    (
      tsurfCfg.services.dashboard.enable
      && tsurfCfg.services.dashboard.listenPort == 8082
    );

  has-nono-sandbox-option = mkCheck
    "has-nono-sandbox-option"
    "services.nonoSandbox option is defined (module imported)"
    "services.nonoSandbox option is missing"
    (builtins.hasAttr "nonoSandbox" devCfg.services);

  dashboard-entries =
    let
      entryCount =
        builtins.length (builtins.attrNames tsurfCfg.services.dashboard.entries);
    in
    mkCheck
      "dashboard-entries"
      "dashboard has ${toString entryCount} entries (>= 5)"
      "dashboard has too few entries: ${toString entryCount}"
      (entryCount >= 5);

  dashboard-manifest = pkgs.runCommandNoCC "dashboard-manifest" { } ''
    echo '${builtins.toJSON (builtins.fromJSON tsurfCfg.environment.etc."dashboard/manifest.json".text)}' \
      | ${jq} . > /dev/null
    echo "PASS: dashboard manifest is valid JSON"
    touch "$out"
  '';

  # --- Remote access safety checks (both hosts) ---
  # These mirror the NixOS assertions in networking.nix but give named PASS/FAIL visibility
  # during `nix flake check`. If assertions fire, the eval check fails too, but the check
  # name makes it obvious which invariant broke.

  remote-access-tsurf = mkCheck
    "remote-access-tsurf"
    "tsurf remote access invariants: sshd + tailscale + root SSH keys + port 22"
    "tsurf remote access broken: sshd=${builtins.toJSON tsurfCfg.services.openssh.enable} tailscale=${builtins.toJSON tsurfCfg.services.tailscale.enable} rootKeys=${builtins.toJSON (tsurfCfg.users.users.root.openssh.authorizedKeys.keys != [])} port22=${builtins.toJSON (builtins.elem 22 tsurfCfg.networking.firewall.allowedTCPPorts)}"
    (tsurfCfg.services.openssh.enable
     && tsurfCfg.services.tailscale.enable
     && tsurfCfg.users.users.root.openssh.authorizedKeys.keys != []
     && (builtins.elem 22 tsurfCfg.networking.firewall.allowedTCPPorts
         || tsurfCfg.services.openssh.openFirewall));

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

  break-glass-key-tsurf = mkCheck
    "break-glass-key-tsurf"
    "tsurf root has break-glass emergency SSH key"
    "tsurf root is missing break-glass emergency SSH key (import modules/break-glass-ssh.nix)"
    (builtins.any (k: lib.hasInfix "break-glass-emergency" k)
      tsurfCfg.users.users.root.openssh.authorizedKeys.keys);

  break-glass-key-ovh = mkCheck
    "break-glass-key-ovh"
    "ovh root has break-glass emergency SSH key"
    "ovh root is missing break-glass emergency SSH key (import modules/break-glass-ssh.nix)"
    (builtins.any (k: lib.hasInfix "break-glass-emergency" k)
      devCfg.users.users.root.openssh.authorizedKeys.keys);

  break-glass-key-unique-tsurf =
    let
      keys = tsurfCfg.users.users.root.openssh.authorizedKeys.keys;
      keyMaterials = map (k: builtins.elemAt (lib.splitString " " k) 1) keys;
      unique = lib.unique keyMaterials;
    in
    mkCheck
      "break-glass-key-unique-tsurf"
      "tsurf root SSH keys all have distinct key material"
      "tsurf root has duplicate SSH key material — break-glass must differ from bootstrap"
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
    "tsurf sshd checks .ssh/authorized_keys (NET-14 impermanence fallback)"
    "tsurf authorizedKeysFiles is missing .ssh/authorized_keys — NET-14 fallback broken"
    (builtins.any (f: f == ".ssh/authorized_keys")
      tsurfCfg.services.openssh.authorizedKeysFiles);

  ssh-host-key-persisted = mkCheck
    "ssh-host-key-persisted"
    "tsurf SSH host key is declared in impermanence persistence"
    "tsurf SSH host key not found in impermanence files — sshd may fail on reboot"
    (let
      source = builtins.readFile ../../modules/impermanence.nix;
    in
      lib.hasInfix "\"/etc/ssh/ssh_host_ed25519_key\"" source);

  sshd-liveness-check-tsurf = mkCheck
    "sshd-liveness-check-tsurf"
    "tsurf sshd-liveness-check timer is defined"
    "tsurf sshd-liveness-check timer is missing — import modules/sshd-liveness-check.nix"
    (builtins.hasAttr "sshd-liveness-check" tsurfCfg.systemd.timers);

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

  # --- Source-text regression guards ---
  # These checks verify module source contains expected strings. They catch
  # accidental removal of security-critical code but do NOT prove runtime
  # behavior. Runtime behavioral tests are in tests/live/sandbox-behavioral.bats.

  agent-sandbox-module-has-nono =
    let
      source = builtins.readFile ../../modules/agent-sandbox.nix;
    in
    mkCheck
      "agent-sandbox-module-has-nono"
      "agent-sandbox module references nono"
      "agent-sandbox module does not reference nono — sandbox is broken"
      (lib.hasInfix "nono" source);

  # Phase 116: raw agent binaries removed from PATH (SEC-116-01).
  # Verify the pi *wrapper* exists (writeShellApplication named "pi"), not the raw package.
  pi-sandbox-wrapper-in-packages =
    let
      source = builtins.readFile ../../modules/agent-sandbox.nix;
    in
    mkCheck
      "pi-sandbox-wrapper-in-packages"
      "pi sandboxed wrapper defined in agent-sandbox.nix"
      "pi sandboxed wrapper missing from agent-sandbox.nix"
      (lib.hasInfix "pi-sandboxed" source);

  nono-profile-has-pi =
    let
      source = builtins.readFile ../../modules/nono.nix;
    in
    mkCheck
      "nono-profile-has-pi"
      "nono tsurf profile includes ~/.pi in filesystem allow list"
      "nono tsurf profile missing ~/.pi — pi config inaccessible in sandbox"
      (lib.hasInfix ".pi" source);

  nono-sandbox-ovh-enabled = mkCheck
    "nono-sandbox-ovh-enabled"
    "ovh nono sandbox module is enabled"
    "ovh services.nonoSandbox.enable is false — nono not active"
    devCfg.services.nonoSandbox.enable;

  agent-journald-logging = mkCheck
    "agent-journald-logging"
    "agent wrapper uses journald-only launch logging (no file audit log)"
    "agent-wrapper.sh still contains audit_log or AGENT_AUDIT_LOG — file audit not fully removed"
    (let src = builtins.readFile ../../scripts/agent-wrapper.sh;
     in lib.hasInfix "journal_log" src
        && !lib.hasInfix "audit_log" src
        && !lib.hasInfix "AGENT_AUDIT_LOG" src);

  syncthing-mesh-option = mkCheck
    "syncthing-mesh-option"
    "tsurf.syncthing.mesh option exists on both hosts"
    "tsurf.syncthing.mesh option missing — import extras/syncthing.nix"
    (builtins.hasAttr "syncthing" tsurfCfg.tsurf
     && builtins.hasAttr "mesh" tsurfCfg.tsurf.syncthing
     && builtins.hasAttr "syncthing" devCfg.tsurf
     && builtins.hasAttr "mesh" devCfg.tsurf.syncthing);

  # --- Phase 119: Secure-by-default host configs + eval fixture checks ---

  # Phase 119: Host source files must NOT set allowUnsafePlaceholders.
  # The flag is injected at the flake level (mkEvalFixture) for CI eval only.
  secure-host-services = mkCheck
    "secure-host-services"
    "hosts/services/default.nix does not set allowUnsafePlaceholders"
    "SECURITY: hosts/services/default.nix sets allowUnsafePlaceholders — host source must be secure by default"
    (!(lib.hasInfix "allowUnsafePlaceholders" (builtins.readFile ../../hosts/services/default.nix)));

  secure-host-dev = mkCheck
    "secure-host-dev"
    "hosts/dev/default.nix does not set allowUnsafePlaceholders"
    "SECURITY: hosts/dev/default.nix sets allowUnsafePlaceholders — host source must be secure by default"
    (!(lib.hasInfix "allowUnsafePlaceholders" (builtins.readFile ../../hosts/dev/default.nix)));

  # Regression guard: eval fixtures must have the flag enabled (proves mkEvalFixture works)
  fixture-mode-tsurf = mkCheck
    "fixture-mode-tsurf"
    "tsurf eval fixture has allowUnsafePlaceholders = true (CI fixture correct)"
    "eval fixture tsurf missing allowUnsafePlaceholders — check flake.nix mkEvalFixture"
    tsurfCfg.tsurf.template.allowUnsafePlaceholders;

  fixture-mode-ovh = mkCheck
    "fixture-mode-ovh"
    "ovh eval fixture has allowUnsafePlaceholders = true (CI fixture correct)"
    "eval fixture ovh missing allowUnsafePlaceholders — check flake.nix mkEvalFixture"
    devCfg.tsurf.template.allowUnsafePlaceholders;

  dev-agent-not-in-template = mkCheck
    "dev-agent-not-in-template"
    "dev-agent service not defined in public ovh config (opt-in works)"
    "dev-agent service defined in public ovh config — should be opt-in only"
    (!(builtins.hasAttr "dev-agent" devCfg.systemd.services));

  restic-opt-in = mkCheck
    "restic-opt-in"
    "restic backup not active in public tsurf config (opt-in works)"
    "restic backup active in public template — services.resticStarter.enable should be false"
    (!tsurfCfg.services.resticStarter.enable);

  # Stale-phrase check: banned phrases must not appear in key docs.
  # Prevents reintroduction of outdated security claims.
  # Note: "phantom token" and "credential proxy" removed from banned list —
  # proxy credential mode with phantom tokens is now implemented (Phase 118).
  stale-phrases-claude-md =
    let
      source = builtins.readFile ../../CLAUDE.md;
    in
    mkCheck
      "stale-phrases-claude-md"
      "CLAUDE.md contains no banned stale phrases"
      "CLAUDE.md contains stale phrase (sibling repos readable)"
      (!(lib.hasInfix "sibling repos readable" source));

  stale-phrases-readme =
    let
      source = builtins.readFile ../../README.md;
    in
    mkCheck
      "stale-phrases-readme"
      "README.md contains no banned stale phrases"
      "README.md contains stale phrase (sibling repos readable)"
      (!(lib.hasInfix "sibling repos readable" source));

  # Phase 118: Proxy credential mode (phantom token pattern)
  proxy-credential-wrapper = mkCheck
    "proxy-credential-wrapper"
    "agent wrapper uses --credential (proxy mode), not --env-credential-map"
    "agent-wrapper.sh uses --env-credential-map — must switch to --credential for proxy mode"
    (let src = builtins.readFile ../../scripts/agent-wrapper.sh;
     in lib.hasInfix "--credential" src
        && !lib.hasInfix "--env-credential-map" src);

  proxy-credential-profile = mkCheck
    "proxy-credential-profile"
    "nono profile contains custom_credentials with env:// URIs"
    "nono.nix profile missing custom_credentials or env:// — proxy mode not configured"
    (let src = builtins.readFile ../../modules/nono.nix;
     in lib.hasInfix "custom_credentials" src
        && lib.hasInfix "env://" src);

  dashboard-security-headers =
    let
      serverSrc = builtins.readFile ../../extras/scripts/dashboard-server.py;
      hasHeader = header: lib.hasInfix header serverSrc;
    in
    mkCheck
      "dashboard-security-headers"
      "dashboard server includes security response headers"
      "dashboard-server.py missing security headers (X-Content-Type-Options, X-Frame-Options, Referrer-Policy)"
      (hasHeader "X-Content-Type-Options" && hasHeader "X-Frame-Options" && hasHeader "Referrer-Policy");

  dashboard-no-innerhtml-xss =
    let
      htmlSrc = builtins.readFile ../../extras/scripts/dashboard-frontend.html;
    in
    mkCheck
      "dashboard-no-innerhtml-xss"
      "dashboard frontend has no innerHTML XSS sinks"
      "dashboard-frontend.html still uses innerHTML — use textContent/createElement instead"
      (!(lib.hasInfix ".innerHTML =" htmlSrc));

  deploy-no-repo-source =
    let
      deploySrc = builtins.readFile ../../extras/scripts/deploy.sh;
    in
    mkCheck
      "deploy-no-repo-source"
      "deploy.sh has no repo-controlled source calls"
      "deploy.sh sources repo-controlled scripts — remove source calls for deploy-post.sh or similar"
      (!(lib.hasInfix "source \"$FLAKE_DIR" deploySrc));

  # --- Phase 115: operator/agent user split ---

  agent-user-exists-ovh = mkCheck
    "agent-user-exists-ovh"
    "ovh agent user exists and is a normal user"
    "ovh agent user missing or not a normal user"
    (builtins.hasAttr "agent" devCfg.users.users
     && devCfg.users.users.agent.isNormalUser);

  agent-user-no-wheel = mkCheck
    "agent-user-no-wheel"
    "agent user is not in wheel group"
    "SECURITY: agent user is in wheel group — must not have sudo"
    (!(builtins.elem "wheel" devCfg.users.users.agent.extraGroups));

  agent-user-no-docker = mkCheck
    "agent-user-no-docker"
    "agent user is not in docker group"
    "SECURITY: agent user is in docker group — must not have docker access"
    (!(builtins.elem "docker" devCfg.users.users.agent.extraGroups));

  agent-egress-targets-agent-user = mkCheck
    "agent-egress-targets-agent-user"
    "ovh agent egress control targets agent user"
    "ovh agent egress control targets wrong user"
    (devCfg.services.agentSandbox.egressControl.user == "agent");

  agent-uid-explicit = mkCheck
    "agent-uid-explicit"
    "agent user has explicit UID defined"
    "agent user uid is not set (required for nftables egress rules)"
    (devCfg.users.users.${devCfg.tsurf.agent.user}.uid != null);

  egress-ruleset-check-enabled = mkCheck
    "egress-ruleset-check-enabled"
    "nftables ruleset validation is not disabled"
    "nftables.checkRuleset is false — egress UID model not fixed"
    (devCfg.networking.nftables.checkRuleset != false);

  impermanence-agent-home =
    let
      source = builtins.readFile ../../modules/impermanence.nix;
    in
    mkCheck
      "impermanence-agent-home"
      "agent home paths declared in impermanence"
      "agent home paths missing from impermanence.nix"
      (lib.hasInfix "/home/agent/.claude" source);

  # --- Phase 116: structural hardening regression guards ---

  syncthing-discovery-disabled = mkCheck
    "syncthing-discovery-disabled"
    "Syncthing global announce and relays disabled by default"
    "Syncthing global announce or relays still enabled"
    (tsurfCfg.services.syncthing.settings.options.globalAnnounceEnabled == false
     && tsurfCfg.services.syncthing.settings.options.relaysEnabled == false);

  syncthing-no-public-bep =
    let
      ports = tsurfCfg.networking.firewall.allowedTCPPorts;
    in
    mkCheck
      "syncthing-no-public-bep"
      "Port 22000 not in allowedTCPPorts (publicBep is off)"
      "Port 22000 in allowedTCPPorts but publicBep is false"
      (!(builtins.elem 22000 ports));

  agent-binaries-not-in-path =
    let
      source = builtins.readFile ../../modules/agent-compute.nix;
    in
    mkCheck
      "agent-binaries-not-in-path"
      "Raw agent binaries not in agent-compute.nix systemPackages"
      "SECURITY: raw agent binaries found in agent-compute.nix systemPackages — use sandboxed wrappers only"
      (!(lib.hasInfix "pkgs.claude-code" source)
       && !(lib.hasInfix "pkgs.codex" source)
       && !(lib.hasInfix "pkgs.pi-coding-agent" source));

  agent-slice-exists-ovh = mkCheck
    "agent-slice-exists-ovh"
    "tsurf-agents systemd slice defined on dev host"
    "tsurf-agents slice missing from dev host"
    (builtins.hasAttr "tsurf-agents" devCfg.systemd.slices);

  restic-status-dynamic-user =
    let
      source = builtins.readFile ../../extras/restic.nix;
    in
    mkCheck
      "restic-status-dynamic-user"
      "restic-status-server uses DynamicUser"
      "restic-status-server should use DynamicUser for least privilege"
      (lib.hasInfix "DynamicUser = true" source);

  # --- Phase 119: brokered launch model (SEC-119-01) ---

  brokered-launch-launcher =
    let
      source = builtins.readFile ../../modules/agent-sandbox.nix;
    in
    mkCheck
      "brokered-launch-launcher"
      "agent-sandbox.nix defines tsurf-agent-launch brokered launcher"
      "agent-sandbox.nix missing tsurf-agent-launch — brokered launch model not implemented"
      (lib.hasInfix "tsurf-agent-launch" source);

  brokered-launch-systemd-run =
    let
      source = builtins.readFile ../../modules/agent-sandbox.nix;
    in
    mkCheck
      "brokered-launch-systemd-run"
      "agent-sandbox.nix uses systemd-run for privilege drop to agent user"
      "agent-sandbox.nix missing systemd-run — wrapper runs as calling user (no privilege drop)"
      (lib.hasInfix "systemd-run" source);

  brokered-launch-sudoers =
    let
      source = builtins.readFile ../../modules/agent-sandbox.nix;
    in
    mkCheck
      "brokered-launch-sudoers"
      "agent-sandbox.nix configures sudo extraRules for brokered launcher"
      "agent-sandbox.nix missing sudo.extraRules — operator cannot invoke brokered launcher"
      (lib.hasInfix "security.sudo.extraRules" source);

  brokered-launch-agent-fallback =
    let
      source = builtins.readFile ../../modules/agent-sandbox.nix;
    in
    mkCheck
      "brokered-launch-agent-fallback"
      "agent-sandbox.nix has direct-exec fallback when already running as agent"
      "agent-sandbox.nix missing agent-user fallback — dev-agent.nix would double-sudo"
      (lib.hasInfix "id -un" source);

  # --- Phase 120: agent API key ownership (SEC-04) ---

  agent-api-key-ownership-ovh = mkCheck
    "agent-api-key-ownership-ovh"
    "anthropic-api-key and openai-api-key owned by agent user on dev host"
    "SECURITY: anthropic-api-key or openai-api-key not owned by agent user — wrapper cannot read secrets"
    (devCfg.sops.secrets."anthropic-api-key".owner == devCfg.tsurf.agent.user
     && devCfg.sops.secrets."openai-api-key".owner == devCfg.tsurf.agent.user);

  # --- Phase 124: Nix daemon user restrictions ---

  nix-allowed-users-tsurf = mkCheck
    "nix-allowed-users-tsurf"
    "tsurf nix.settings.allowed-users restricts daemon access"
    "tsurf nix.settings.allowed-users is not set or too permissive"
    (builtins.elem "root" tsurfCfg.nix.settings.allowed-users
     && builtins.elem "@wheel" tsurfCfg.nix.settings.allowed-users
     && !(builtins.elem "*" tsurfCfg.nix.settings.allowed-users));

  nix-trusted-users-tsurf = mkCheck
    "nix-trusted-users-tsurf"
    "tsurf nix.settings.trusted-users is root-only"
    "tsurf nix.settings.trusted-users includes non-root entries"
    (tsurfCfg.nix.settings.trusted-users == [ "root" ]);

  nix-allowed-users-ovh-includes-agent = mkCheck
    "nix-allowed-users-ovh-includes-agent"
    "ovh nix.settings.allowed-users includes agent user (allowNixDaemon is on)"
    "ovh nix.settings.allowed-users missing agent user despite allowNixDaemon=true"
    (builtins.elem devCfg.tsurf.agent.user devCfg.nix.settings.allowed-users);

  # --- Phase 124: Clone-repos credential safety ---

  clone-repos-no-cli-credentials =
    let
      source = builtins.readFile ../../extras/scripts/clone-repos.sh;
    in
    mkCheck
      "clone-repos-no-cli-credentials"
      "clone-repos.sh uses GIT_ASKPASS (no credentials on CLI)"
      "clone-repos.sh passes credentials via git -c extraheader - use GIT_ASKPASS pattern instead"
      (lib.hasInfix "GIT_ASKPASS" source
       && !(lib.hasInfix "extraheader" source));

  # --- Phase 124: Cost-tracker least privilege ---

  cost-tracker-dynamic-user =
    let
      source = builtins.readFile ../../extras/cost-tracker.nix;
    in
    mkCheck
      "cost-tracker-dynamic-user"
      "cost-tracker uses DynamicUser for least privilege"
      "cost-tracker.nix missing DynamicUser = true — service runs as root"
      (lib.hasInfix "DynamicUser = true" source);

  # --- Phase 125: systemd hardening baseline ---

  systemd-hardening-baseline =
    let
      hasSCA = svc:
        let sca = svc.serviceConfig.SystemCallArchitectures or null;
        in if sca == null then false
           else if builtins.isList sca then builtins.elem "native" sca
           else sca == "native";
    in
    mkCheck
      "systemd-hardening-baseline"
      "All project services have SystemCallArchitectures=native"
      "SECURITY: one or more services missing SystemCallArchitectures=native"
      (hasSCA tsurfCfg.systemd.services.nix-dashboard
       && hasSCA tsurfCfg.systemd.services.sshd-liveness-check
       && hasSCA devCfg.systemd.services.syncthing);

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
#   #   privateCfg = self.nixosConfigurations.tsurf.config;
#   # in publicChecks // {
#   #   agent-fleet-ports = ...; # private agent fleet/proxy assertions
#   #   nginx-vhosts = ...;      # private reverse-proxy checks
#   #   acme-domains = ...;      # private certificate domain coverage
#   # };
#
# Private live tests follow the same pattern under private-tsurf/tests/live/.
