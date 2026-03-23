# tests/eval/config-checks.nix — Nix eval-time assertions for tsurf eval fixtures.
# @decision TEST-48-01: Keep checks purely eval-time with runCommand to catch regressions offline.
{ self, pkgs, lib }:
let
  servicesCfg = self.nixosConfigurations."eval-services".config;
  devCfg = self.nixosConfigurations."eval-dev".config;
  altAgentCfg = self.nixosConfigurations."eval-dev-alt-agent".config;
  devAgentUser = devCfg.tsurf.agent.user;
  altAgentUser = altAgentCfg.tsurf.agent.user;
  altAgentHome = altAgentCfg.tsurf.agent.home;
  jq = "${pkgs.jq}/bin/jq";

  mkCheck = name: passMessage: failMessage: condition:
    pkgs.runCommand name { } ''
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
  eval-services = pkgs.runCommand "eval-services" { } ''
    echo "eval-services config evaluates: ${self.nixosConfigurations."eval-services".config.system.build.toplevel}"
    touch "$out"
  '';

  eval-dev = pkgs.runCommand "eval-dev" { } ''
    echo "eval-dev config evaluates: ${self.nixosConfigurations."eval-dev".config.system.build.toplevel}"
    touch "$out"
  '';

  eval-dev-alt-agent = pkgs.runCommand "eval-dev-alt-agent" { } ''
    echo "eval-dev-alt-agent config evaluates: ${self.nixosConfigurations."eval-dev-alt-agent".config.system.build.toplevel}"
    touch "$out"
  '';

  # Ports are conditional: 22000 on publicBep opt-in, 80/443 on nginx.enable.
  # Public template has no nginx and publicBep defaults to false.
  firewall-ports-services =
    let
      actual = builtins.sort builtins.lessThan servicesCfg.networking.firewall.allowedTCPPorts;
      expected = [ 22 ]
        ++ lib.optionals servicesCfg.services.syncthingStarter.publicBep [ 22000 ]
        ++ lib.optionals servicesCfg.services.nginx.enable [ 80 443 ];
    in
    mkCheck
      "firewall-ports-services"
      "services host firewall ports match publicBep/nginx state"
      "services host allowedTCPPorts=${builtins.toJSON actual} expected=${builtins.toJSON expected}"
      (actual == expected);

  firewall-ports-dev =
    let
      actual = builtins.sort builtins.lessThan devCfg.networking.firewall.allowedTCPPorts;
      expected = [ 22 ]
        ++ lib.optionals devCfg.services.syncthingStarter.publicBep [ 22000 ]
        ++ lib.optionals devCfg.services.nginx.enable [ 80 443 ];
    in
    mkCheck
      "firewall-ports-dev"
      "dev host firewall ports match publicBep/nginx state"
      "dev host allowedTCPPorts=${builtins.toJSON actual} expected=${builtins.toJSON expected}"
      (actual == expected);

  # Phase 122: tailscale0 must NOT be in trustedInterfaces (localhost-first model).
  no-trusted-tailscale0-services = mkCheck
    "no-trusted-tailscale0-services"
    "services host does not have tailscale0 in trustedInterfaces (localhost-first model)"
    "SECURITY: services host has tailscale0 in trustedInterfaces — remove it, use per-service firewall.interfaces rules"
    (!(builtins.elem "tailscale0" servicesCfg.networking.firewall.trustedInterfaces));

  no-trusted-tailscale0-dev = mkCheck
    "no-trusted-tailscale0-dev"
    "dev host does not have tailscale0 in trustedInterfaces (localhost-first model)"
    "SECURITY: dev host has tailscale0 in trustedInterfaces — remove it, use per-service firewall.interfaces rules"
    (!(builtins.elem "tailscale0" devCfg.networking.firewall.trustedInterfaces));

  no-accept-routes-services = mkCheck
    "no-accept-routes-services"
    "services host Tailscale extraUpFlags does not include --accept-routes"
    "services host Tailscale extraUpFlags contains --accept-routes — remove from default, add in overlay if needed"
    (!(builtins.elem "--accept-routes" servicesCfg.services.tailscale.extraUpFlags));

  no-accept-routes-dev = mkCheck
    "no-accept-routes-dev"
    "dev host Tailscale extraUpFlags does not include --accept-routes"
    "dev host Tailscale extraUpFlags contains --accept-routes — remove from default, add in overlay if needed"
    (!(builtins.elem "--accept-routes" devCfg.services.tailscale.extraUpFlags));

  expected-services-services =
    let
      expectedServices = [
        "tailscaled"
        "syncthing"
        "nix-dashboard"
      ];
      missing = builtins.filter (name: !(builtins.hasAttr name servicesCfg.systemd.services)) expectedServices;
    in
    mkCheck
      "expected-services-services"
      "all expected services host services are defined"
      "missing services host services: ${builtins.concatStringsSep ", " missing}"
      (missing == [ ]);

  expected-services-dev =
    let
      expectedServices = [
        "tailscaled"
        "syncthing"
      ];
      missing = builtins.filter (name: !(builtins.hasAttr name devCfg.systemd.services)) expectedServices;
    in
    mkCheck
      "expected-services-dev"
      "all expected dev host services are defined"
      "missing dev host services: ${builtins.concatStringsSep ", " missing}"
      (missing == [ ]);

  ssh-ed25519-only =
    let
      hostKeyTypes = map (k: k.type) servicesCfg.services.openssh.hostKeys;
    in
    mkCheck
      "ssh-ed25519-only"
      "SSH host key types are ed25519 only"
      "SSH host key types=${builtins.toJSON hostKeyTypes}, expected [\"ed25519\"]"
      (hostKeyTypes == [ "ed25519" ]);

  metadata-block = mkCheck
    "metadata-block"
    "agent-metadata-block nftables table is defined"
    "agent-metadata-block nftables table not found"
    (builtins.hasAttr "agent-metadata-block" servicesCfg.networking.nftables.tables);


  dashboard-enabled = mkCheck
    "dashboard-enabled"
    "nix-dashboard is enabled on port 8082"
    "nix-dashboard disabled or wrong port"
    (
      servicesCfg.services.dashboard.enable
      && servicesCfg.services.dashboard.listenPort == 8082
    );

  dashboard-entries =
    let
      entryCount =
        builtins.length (builtins.attrNames servicesCfg.services.dashboard.entries);
    in
    mkCheck
      "dashboard-entries"
      "dashboard has ${toString entryCount} entries (>= 4)"
      "dashboard has too few entries: ${toString entryCount}"
      (entryCount >= 4);

  dashboard-manifest = pkgs.runCommand "dashboard-manifest" { } ''
    echo '${builtins.toJSON (builtins.fromJSON servicesCfg.environment.etc."dashboard/manifest.json".text)}' \
      | ${jq} . > /dev/null
    echo "PASS: dashboard manifest is valid JSON"
    touch "$out"
  '';

  agent-sandbox-dev-enabled = mkCheck
    "agent-sandbox-dev-enabled"
    "dev host agent sandbox wrappers are enabled"
    "dev host services.agentSandbox.enable is false — dev agents run unsandboxed"
    devCfg.services.agentSandbox.enable;

  # --- Source-text regression guards ---
  # These checks verify module source contains expected strings. They catch
  # accidental removal of security-critical code but do NOT prove runtime
  # behavior. Runtime behavioral tests are in tests/live/sandbox-behavioral.bats.

  core-agent-sandbox-only-claude =
    let
      source = builtins.readFile ../../modules/agent-sandbox.nix;
    in
    mkCheck
      "core-agent-sandbox-only-claude"
      "agent-sandbox core wrapper list only includes claude"
      "agent-sandbox.nix still hardcodes non-claude wrappers; move them to extras/"
      (lib.hasInfix "name = \"claude\"" source
       && !(lib.hasInfix "pkgs.codex" source)
       && !(lib.hasInfix "pkgs.pi-coding-agent" source));

  nono-sandbox-dev-enabled = mkCheck
    "nono-sandbox-dev-enabled"
    "dev host nono sandbox module is enabled"
    "dev host services.nonoSandbox.enable is false — nono not active"
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
    (builtins.hasAttr "syncthing" servicesCfg.tsurf
     && builtins.hasAttr "mesh" servicesCfg.tsurf.syncthing
     && builtins.hasAttr "syncthing" devCfg.tsurf
     && builtins.hasAttr "mesh" devCfg.tsurf.syncthing);

  # --- Phase 119: Secure-by-default host configs + eval fixture checks ---

  # Phase 119/134: Host source files must NOT set allowUnsafePlaceholders.
  # The flag is injected only in clearly named eval fixture outputs.
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
  fixture-mode-services = mkCheck
    "fixture-mode-services"
    "services eval fixture has allowUnsafePlaceholders = true (CI fixture correct)"
    "eval fixture services missing allowUnsafePlaceholders — check flake.nix mkEvalFixture"
    servicesCfg.tsurf.template.allowUnsafePlaceholders;

  fixture-mode-dev = mkCheck
    "fixture-mode-dev"
    "dev eval fixture has allowUnsafePlaceholders = true (CI fixture correct)"
    "eval fixture dev missing allowUnsafePlaceholders — check flake.nix mkEvalFixture"
    devCfg.tsurf.template.allowUnsafePlaceholders;

  fixture-output-names = mkCheck
    "fixture-output-names"
    "public flake exports only clearly named eval fixture outputs"
    "public flake still exports deploy-looking nixosConfigurations (non-eval-prefixed)"
    (let
      names = builtins.attrNames self.nixosConfigurations;
    in builtins.length names > 0 && builtins.all (name: lib.hasPrefix "eval-" name) names);

  public-deploy-empty = mkCheck
    "public-deploy-empty"
    "public flake exports no public deploy.nodes targets"
    "public flake still exports deploy.nodes.* — deploy targets must live in a private overlay"
    (
      !(self ? deploy)
      || (self.deploy.nodes or {}) == {}
    );

  dev-agent-not-in-template = mkCheck
    "dev-agent-not-in-template"
    "dev-agent service not defined in public dev config (opt-in works)"
    "dev-agent service defined in public dev config — should be opt-in only"
    (!(builtins.hasAttr "dev-agent" devCfg.systemd.services));

  restic-opt-in = mkCheck
    "restic-opt-in"
    "restic backup not active in public services config (opt-in works)"
    "restic backup active in public template — services.resticStarter.enable should be false"
    (!servicesCfg.services.resticStarter.enable);

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

  nono-profile-denies-run-secrets = mkCheck
    "nono-profile-denies-run-secrets"
    "generated nono profile explicitly denies /run/secrets"
    "nono profile deny list is missing /run/secrets"
    (let
      profile = builtins.fromJSON (builtins.readFile devCfg.environment.etc."nono/profiles/tsurf.json".source);
    in
      builtins.elem "/run/secrets" profile.filesystem.deny);

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

  agent-user-exists-dev = mkCheck
    "agent-user-exists-dev"
    "dev host agent user exists and is a normal user"
    "dev host agent user missing or not a normal user"
    (builtins.hasAttr devAgentUser devCfg.users.users
     && (builtins.getAttr devAgentUser devCfg.users.users).isNormalUser);

  agent-user-no-wheel = mkCheck
    "agent-user-no-wheel"
    "agent user is not in wheel group"
    "SECURITY: agent user is in wheel group — must not have sudo"
    (!(builtins.elem "wheel" (builtins.getAttr devAgentUser devCfg.users.users).extraGroups));

  agent-user-no-docker = mkCheck
    "agent-user-no-docker"
    "agent user is not in docker group"
    "SECURITY: agent user is in docker group — must not have docker access"
    (!(builtins.elem "docker" (builtins.getAttr devAgentUser devCfg.users.users).extraGroups));

  agent-uid-explicit = mkCheck
    "agent-uid-explicit"
    "agent user has explicit UID defined"
    "agent user uid is not set (required for stable sandbox policy references)"
    (devCfg.users.users.${devCfg.tsurf.agent.user}.uid != null);

  impermanence-agent-home =
    let
      source = builtins.readFile ../../modules/agent-sandbox.nix;
      expectedSuffixes = [
        ".claude"
        ".config/claude"
        ".config/git"
        ".local/share/direnv"
        ".gitconfig"
        ".bash_history"
      ];
      missingSuffixes = builtins.filter (path: !(lib.hasInfix "\"${path}\"" source)) expectedSuffixes;
    in
    mkCheck
      "impermanence-agent-home"
      "agent-sandbox derives agent persist paths from agentCfg.home"
      "agent-sandbox.nix still hardcodes agent home paths or is missing agent state suffixes"
      (lib.hasInfix "agentCfg.home" source
       && !(lib.hasInfix "\"/home/agent/" source)
       && missingSuffixes == [ ]);

  alt-agent-parameterization = mkCheck
    "alt-agent-parameterization"
    "non-default agent fixture propagates through users and sandbox modules"
    "non-default agent fixture still relies on hardcoded agent identity or home"
    (
      builtins.hasAttr altAgentUser altAgentCfg.users.users
      && (builtins.getAttr altAgentUser altAgentCfg.users.users).home == altAgentHome
      && altAgentCfg.services.agentSandbox.enable
      && altAgentCfg.services.nonoSandbox.enable
    );

  # --- Phase 116: structural hardening regression guards ---

  syncthing-discovery-disabled = mkCheck
    "syncthing-discovery-disabled"
    "Syncthing global announce and relays disabled by default"
    "Syncthing global announce or relays still enabled"
    (servicesCfg.services.syncthing.settings.options.globalAnnounceEnabled == false
     && servicesCfg.services.syncthing.settings.options.relaysEnabled == false);

  syncthing-no-public-bep =
    let
      ports = servicesCfg.networking.firewall.allowedTCPPorts;
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

  agent-slice-exists-dev = mkCheck
    "agent-slice-exists-dev"
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
      "agent-sandbox.nix defines immutable per-agent launchers"
      "agent-sandbox.nix still relies on the generic tsurf-agent-launch boundary"
      (lib.hasInfix "tsurf-launch-" source
       && !(lib.hasInfix "tsurf-agent-launch" source));

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
      "agent-sandbox.nix configures sudo extraRules without SETENV or caller env passthrough"
      "agent-sandbox.nix sudoers path still uses SETENV or preserve-env"
      (lib.hasInfix "security.sudo.extraRules" source
       && !(lib.hasInfix "\"SETENV\"" source)
       && !(lib.hasInfix "--preserve-env" source));

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

  agent-api-key-ownership-dev = mkCheck
    "agent-api-key-ownership-dev"
    "anthropic-api-key and openai-api-key owned by agent user on dev host"
    "SECURITY: anthropic-api-key or openai-api-key not owned by agent user — wrapper cannot read secrets"
    (devCfg.sops.secrets."anthropic-api-key".owner == devCfg.tsurf.agent.user
     && devCfg.sops.secrets."openai-api-key".owner == devCfg.tsurf.agent.user);

  # --- Phase 124: Nix daemon user restrictions ---

  nix-allowed-users-services = mkCheck
    "nix-allowed-users-services"
    "services host nix.settings.allowed-users restricts daemon access"
    "services host nix.settings.allowed-users is not set or too permissive"
    (builtins.elem "root" servicesCfg.nix.settings.allowed-users
     && builtins.elem "@wheel" servicesCfg.nix.settings.allowed-users
     && !(builtins.elem "*" servicesCfg.nix.settings.allowed-users));

  nix-trusted-users-services = mkCheck
    "nix-trusted-users-services"
    "services host nix.settings.trusted-users is root-only"
    "services host nix.settings.trusted-users includes non-root entries"
    (servicesCfg.nix.settings.trusted-users == [ "root" ]);

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

  home-profile-no-deprecated-options =
    let
      source = builtins.readFile ../../extras/home/default.nix;
    in
    mkCheck
      "home-profile-no-deprecated-options"
      "extras/home/default.nix avoids deprecated Home Manager git/ssh options"
      "extras/home/default.nix still uses deprecated Home Manager git/ssh options"
      (!(lib.hasInfix "programs.git.userName" source)
       && !(lib.hasInfix "programs.git.userEmail" source)
       && !(lib.hasInfix "programs.ssh.controlMaster" source)
       && !(lib.hasInfix "programs.ssh.controlPersist" source)
       && !(lib.hasInfix "programs.ssh.hashKnownHosts" source)
       && !(lib.hasInfix "programs.ssh.serverAliveInterval" source));

  agent-scripts-avoid-global-tmp =
    let
      cloneSource = builtins.readFile ../../extras/scripts/clone-repos.sh;
      deploySource = builtins.readFile ../../extras/scripts/deploy.sh;
      devAgentSource = builtins.readFile ../../extras/scripts/dev-agent.sh;
    in
    mkCheck
      "agent-scripts-avoid-global-tmp"
      "agent helper scripts avoid /tmp for transient state"
      "agent helper scripts still write transient files under /tmp"
      (!(lib.hasInfix "mktemp /tmp" cloneSource)
       && !(lib.hasInfix " /tmp/" deploySource)
       && !(lib.hasInfix "=/tmp/" deploySource)
       && !(lib.hasInfix "mktemp /tmp" devAgentSource)
       && !(lib.hasInfix "/tmp/dev-agent-task" devAgentSource));

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
      resticSource = builtins.readFile ../../extras/restic.nix;
      costTrackerSource = builtins.readFile ../../extras/cost-tracker.nix;
      devAgentSource = builtins.readFile ../../extras/dev-agent.nix;
    in
    mkCheck
      "systemd-hardening-baseline"
      "All project services have SystemCallArchitectures=native"
      "SECURITY: one or more services missing SystemCallArchitectures=native"
      (hasSCA servicesCfg.systemd.services.nix-dashboard
       && hasSCA devCfg.systemd.services.syncthing
       && lib.hasInfix "SystemCallArchitectures = \"native\"" (builtins.readFile ../../extras/dashboard.nix)
       && lib.hasInfix "SystemCallArchitectures = \"native\"" resticSource
       && lib.hasInfix "SystemCallArchitectures = \"native\"" costTrackerSource
       && lib.hasInfix "SystemCallArchitectures = \"native\"" devAgentSource);

  # --- Phase 124: Control-plane separation ---

  dev-agent-not-control-plane =
    let
      source = builtins.readFile ../../extras/dev-agent.nix;
    in
    mkCheck
      "dev-agent-not-control-plane"
      "dev-agent.nix default WorkingDirectory is not the control-plane repo"
      "SECURITY: dev-agent.nix WorkingDirectory defaults to /tsurf (control-plane repo) — use agentCfg.projectRoot"
      (!(lib.hasInfix "projectRoot}/tsurf" source));

  dev-agent-script-no-control-plane-output =
    let
      source = builtins.readFile ../../extras/scripts/dev-agent.sh;
    in
    mkCheck
      "dev-agent-script-no-control-plane-output"
      "dev-agent task writes research output to the configured working directory"
      "SECURITY: dev-agent.sh hardcodes /data/projects/tsurf/RESEARCH.md instead of the current working directory"
      (!(lib.hasInfix "/data/projects/tsurf/RESEARCH.md" source)
       && lib.hasInfix "./RESEARCH.md" source);

  cost-tracker-secret-capability =
    let
      source = builtins.readFile ../../extras/cost-tracker.nix;
    in
    mkCheck
      "cost-tracker-secret-capability"
      "cost-tracker explicitly grants CAP_DAC_READ_SEARCH ambiently for secret reads"
      "cost-tracker.nix bounds CAP_DAC_READ_SEARCH without AmbientCapabilities — DynamicUser service cannot read configured secret files"
      (lib.hasInfix "AmbientCapabilities = [ \"CAP_DAC_READ_SEARCH\" ]" source
       && lib.hasInfix "CapabilityBoundingSet = [ \"CAP_DAC_READ_SEARCH\" ]" source);

  # --- Phase 124: Sandbox read-scope regression guards ---
  # Source-text checks for critical fail-closed patterns in agent-wrapper.sh.
  # Runtime behavioral coverage is in tests/live/sandbox-behavioral.bats.

  sandbox-git-root-fail-closed =
    let
      source = builtins.readFile ../../scripts/agent-wrapper.sh;
    in
    mkCheck
      "sandbox-git-root-fail-closed"
      "agent-wrapper.sh has fail-closed git-root validation (no silent fallback)"
      "agent-wrapper.sh missing fail-closed git-root check — agents may run outside git worktrees"
      (lib.hasInfix "rev-parse --show-toplevel" source
       && lib.hasInfix "exit 1" source);

  sandbox-refuses-project-root-read =
    let
      source = builtins.readFile ../../scripts/agent-wrapper.sh;
    in
    mkCheck
      "sandbox-refuses-project-root-read"
      "agent-wrapper.sh refuses to grant read access to entire project root"
      "agent-wrapper.sh missing project-root refusal — agents could read all repos"
      (lib.hasInfix "refusing to grant read access to the entire project root" source);

  public-no-sandbox-removed =
    let
      wrapperSource = builtins.readFile ../../scripts/agent-wrapper.sh;
      launcherSource = builtins.readFile ../../modules/agent-sandbox.nix;
    in
    mkCheck
      "public-no-sandbox-removed"
      "public wrapper/launcher no longer expose a --no-sandbox escape hatch"
      "SECURITY: public wrapper or launcher still reference --no-sandbox / AGENT_ALLOW_NOSANDBOX"
      (!(lib.hasInfix "no-sandbox" wrapperSource)
       && !(lib.hasInfix "AGENT_ALLOW_NOSANDBOX" wrapperSource)
       && !(lib.hasInfix "AGENT_ALLOW_NOSANDBOX" launcherSource));

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
#   #   privateCfg = self.nixosConfigurations.my-real-host.config;
#   # in publicChecks // {
#   #   agent-fleet-ports = ...; # private agent fleet/proxy assertions
#   #   nginx-vhosts = ...;      # private reverse-proxy checks
#   #   acme-domains = ...;      # private certificate domain coverage
#   # };
#
# Private live tests follow the same pattern under private-tsurf/tests/live/.
