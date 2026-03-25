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

  # Phase 145: nix-mineral hardening must be enabled on all hosts. [SEC-145-05]
  nix-mineral-services = mkCheck
    "nix-mineral-services"
    "services host has nix-mineral hardening enabled"
    "SECURITY: services host does not have nix-mineral enabled"
    servicesCfg.nix-mineral.enable;

  nix-mineral-dev = mkCheck
    "nix-mineral-dev"
    "dev host has nix-mineral hardening enabled"
    "SECURITY: dev host does not have nix-mineral enabled"
    devCfg.nix-mineral.enable;

  # Ports are conditional: 80/443 on nginx.enable.
  # Public template has no nginx by default.
  firewall-ports-services =
    let
      actual = builtins.sort builtins.lessThan servicesCfg.networking.firewall.allowedTCPPorts;
      expected = [ 22 ] ++ lib.optionals servicesCfg.services.nginx.enable [ 80 443 ];
    in
    mkCheck
      "firewall-ports-services"
      "services host firewall ports match nginx state"
      "services host allowedTCPPorts=${builtins.toJSON actual} expected=${builtins.toJSON expected}"
      (actual == expected);

  firewall-ports-dev =
    let
      actual = builtins.sort builtins.lessThan devCfg.networking.firewall.allowedTCPPorts;
      expected = [ 22 ] ++ lib.optionals devCfg.services.nginx.enable [ 80 443 ];
    in
    mkCheck
      "firewall-ports-dev"
      "dev host firewall ports match nginx state"
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

  agent-egress-table = mkCheck
    "agent-egress-table"
    "agent-egress nftables table is defined"
    "agent-egress nftables table not found"
    (builtins.hasAttr "agent-egress" servicesCfg.networking.nftables.tables);

  agent-egress-policy =
    let
      content = servicesCfg.networking.nftables.tables.agent-egress.content;
      agentUid = toString servicesCfg.tsurf.agent.uid;
    in
    mkCheck
      "agent-egress-policy"
      "agent-egress policy scopes by agent UID and blocks private ranges"
      "agent-egress policy missing UID scoping, private-range drops, or HTTPS allowlist"
      (lib.hasInfix "meta skuid ${agentUid}" content
       && lib.hasInfix "100.64.0.0/10" content
       && lib.hasInfix "443" content
       && lib.hasInfix "drop" content);


  agent-sandbox-dev-enabled = mkCheck
    "agent-sandbox-dev-enabled"
    "dev host agent sandbox wrappers are enabled"
    "dev host services.agentSandbox.enable is false — dev agents run unsandboxed"
    devCfg.services.agentSandbox.enable;

  # --- Source-text regression guards ---

  core-agent-sandbox-only-claude =
    let
      source = builtins.readFile ../../modules/agent-sandbox.nix;
    in
    mkCheck
      "core-agent-sandbox-only-claude"
      "agent-sandbox core wrapper declares only claude"
      "agent-sandbox.nix still hardcodes non-claude wrappers; move them to extras/"
      (lib.hasInfix "claude" source
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

  # --- Phase 119: Secure-by-default host configs + eval fixture checks ---

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

  # Phase 145: root-owned credential broker
  proxy-credential-wrapper = mkCheck
    "proxy-credential-wrapper"
    "agent wrapper starts the root-owned credential proxy and drops the child with setpriv"
    "agent-wrapper.sh missing credential-proxy.py or setpriv — raw keys may reach the agent principal"
    (let src = builtins.readFile ../../scripts/agent-wrapper.sh;
     in lib.hasInfix "credential-proxy.py" src
        && lib.hasInfix "setpriv" src);

  proxy-credential-profile = mkCheck
    "proxy-credential-profile"
    "nono profile contains no raw credential sourcing"
    "nono.nix still contains custom_credentials/env:// raw credential wiring"
    (let src = builtins.readFile ../../modules/nono.nix;
     in !lib.hasInfix "custom_credentials" src
        && !lib.hasInfix "env://" src);

  nono-profile-denies-run-secrets = mkCheck
    "nono-profile-denies-run-secrets"
    "generated nono profile explicitly denies /run/secrets"
    "nono profile deny list is missing /run/secrets"
    (let
      profile = builtins.fromJSON (builtins.readFile devCfg.environment.etc."nono/profiles/tsurf.json".source);
    in
      builtins.elem "/run/secrets" profile.filesystem.deny);

  deploy-no-repo-source =
    let
      deploySrc = builtins.readFile ../../scripts/deploy.sh;
    in
    mkCheck
      "deploy-no-repo-source"
      "deploy.sh has no repo-controlled source calls"
      "deploy.sh sources repo-controlled scripts — remove source calls for deploy-post.sh or similar"
      (!(lib.hasInfix "source \"$FLAKE_DIR" deploySrc));

  # --- Phase 115/152: agent user split ---

  agent-user-exists-dev = mkCheck
    "agent-user-exists-dev"
    "dev host agent user exists and is a normal user"
    "dev host agent user missing or not a normal user"
    (builtins.hasAttr devAgentUser devCfg.users.users
     && (builtins.getAttr devAgentUser devCfg.users.users).isNormalUser);

  agent-in-wheel = mkCheck
    "agent-in-wheel"
    "agent user is in wheel group (required for sudo to immutable launchers)"
    "agent user is not in wheel group — launcher sudo rules will not work"
    (builtins.elem "wheel" (builtins.getAttr devAgentUser devCfg.users.users).extraGroups);

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
      "agent-sandbox declares agent persist paths"
      "agent-sandbox.nix is missing expected agent state suffixes"
      (missingSuffixes == [ ]);

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

  # --- Phase 119/152: brokered launch model ---

  brokered-launch-launcher =
    let
      source = builtins.readFile ../../modules/agent-launcher.nix;
    in
    mkCheck
      "brokered-launch-launcher"
      "agent-launcher.nix defines immutable per-agent launchers"
      "agent-launcher.nix still relies on the generic tsurf-agent-launch boundary"
      (lib.hasInfix "tsurf-launch-" source
       && !(lib.hasInfix "tsurf-agent-launch" source));

  brokered-launch-systemd-run =
    let
      source = builtins.readFile ../../modules/agent-launcher.nix;
    in
    mkCheck
      "brokered-launch-systemd-run"
      "agent-launcher.nix uses systemd-run for privilege drop to agent user"
      "agent-launcher.nix missing systemd-run — wrapper runs as calling user (no privilege drop)"
      (lib.hasInfix "systemd-run" source);

  brokered-launch-sudoers =
    let
      source = builtins.readFile ../../modules/agent-launcher.nix;
    in
    mkCheck
      "brokered-launch-sudoers"
      "agent-launcher.nix configures sudo extraRules without SETENV or caller env passthrough"
      "agent-launcher.nix sudoers path still uses SETENV or preserve-env"
      (lib.hasInfix "security.sudo.extraRules" source
       && !(lib.hasInfix "\"SETENV\"" source)
       && !(lib.hasInfix "--preserve-env" source));

  brokered-launch-agent-fallback =
    let
      source = builtins.readFile ../../modules/agent-launcher.nix;
    in
    mkCheck
      "brokered-launch-agent-fallback"
      "agent-launcher.nix keeps the launcher root-brokered and only short-circuits for root"
      "agent-launcher.nix still has an agent-user direct exec path that bypasses the root credential broker"
      (lib.hasInfix "id -u" source
       && lib.hasInfix "\"0\"" source
       && !lib.hasInfix "id -un" source);

  launcher-extra-deny =
    let
      source = builtins.readFile ../../modules/agent-launcher.nix;
    in
    mkCheck
      "launcher-extra-deny"
      "agent-launcher.nix merges per-agent nonoProfile.extraDeny rules"
      "agent-launcher.nix defines extraDeny but does not write deny rules into generated profiles"
      (lib.hasInfix "extraDeny" source
       && lib.hasInfix "deny = agentDef.nonoProfile.extraDeny;" source);

  # --- Phase 120: agent API key ownership (SEC-04) ---

  agent-api-key-ownership-dev = mkCheck
    "agent-api-key-ownership-dev"
    "anthropic-api-key and openai-api-key owned by root on dev host"
    "SECURITY: anthropic-api-key or openai-api-key not owned by root — agent principal can read raw provider keys"
    (devCfg.sops.secrets."anthropic-api-key".owner == "root"
     && devCfg.sops.secrets."openai-api-key".owner == "root");

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
      deploySource = builtins.readFile ../../scripts/deploy.sh;
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

  tsurf-status-persistent-services =
    let
      source = builtins.readFile ../../scripts/tsurf-status.sh;
    in
    mkCheck
      "tsurf-status-persistent-services"
      "tsurf-status checks only persistent units and documents supported arguments accurately"
      "scripts/tsurf-status.sh still references transient agent-launch-claude or the unsupported all keyword"
      (!(lib.hasInfix "agent-launch-claude" source)
       && !(lib.hasInfix "<hostname|all>" source));

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

  example-code-review-uses-wrapper =
    let
      source = builtins.readFile ../../examples/private-overlay/modules/code-review.nix;
    in
    mkCheck
      "example-code-review-uses-wrapper"
      "example scheduled code-review agent uses the generated sandboxed wrapper"
      "examples/private-overlay/modules/code-review.nix bypasses the brokered wrapper path with a raw claude ExecStart"
      (lib.hasInfix "/run/current-system/sw/bin/code-review" source
       && !(lib.hasInfix "package}/bin/claude" source));

  # --- Phase 125: systemd hardening baseline ---

  systemd-hardening-baseline =
    let
      costTrackerSource = builtins.readFile ../../extras/cost-tracker.nix;
      devAgentSource = builtins.readFile ../../extras/dev-agent.nix;
    in
    mkCheck
      "systemd-hardening-baseline"
      "All project services have SystemCallArchitectures=native"
      "SECURITY: one or more services missing SystemCallArchitectures=native"
      (lib.hasInfix "SystemCallArchitectures = \"native\"" costTrackerSource
       && lib.hasInfix "SystemCallArchitectures = \"native\"" devAgentSource);

  # --- Phase 124: dev-agent workspace ---

  dev-agent-not-control-plane =
    let
      source = builtins.readFile ../../extras/dev-agent.nix;
    in
    mkCheck
      "dev-agent-not-control-plane"
      "dev-agent.nix defaults to a dedicated workspace"
      "SECURITY: dev-agent.nix still defaults to projectRoot instead of a dedicated workspace"
      (lib.hasInfix "dev-agent-workspace" source
       && !(lib.hasInfix "default = agentCfg.projectRoot;" source));

  dev-agent-supervised =
    let
      source = builtins.readFile ../../extras/dev-agent.nix;
    in
    mkCheck
      "dev-agent-supervised"
      "dev-agent runs as a supervised systemd service, not a detached oneshot"
      "dev-agent.nix still uses detached oneshot lifecycle instead of a supervised manager loop"
      (lib.hasInfix "Type = \"simple\"" source
       && lib.hasInfix "ExecStop =" source
       && !(lib.hasInfix "Type = \"oneshot\"" source)
       && !(lib.hasInfix "RemainAfterExit = true" source));

  dev-agent-parameterized-task =
    let
      moduleSource = builtins.readFile ../../extras/dev-agent.nix;
      scriptSource = builtins.readFile ../../extras/scripts/dev-agent.sh;
    in
    mkCheck
      "dev-agent-parameterized-task"
      "dev-agent task configuration is parameterized and manager-driven"
      "dev-agent still hardcodes a repo-specific task instead of prompt/command options and manager env vars"
      (lib.hasInfix "prompt = lib.mkOption" moduleSource
       && lib.hasInfix "command = lib.mkOption" moduleSource
       && lib.hasInfix "DEV_AGENT_TASK_SCRIPT" scriptSource
       && lib.hasInfix "zmx list --short" scriptSource
       && !(lib.hasInfix "Conduct a literature search for projects similar to tsurf" scriptSource));

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

  # --- Sandbox read-scope regression guards ---

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
      launcherSource = builtins.readFile ../../modules/agent-launcher.nix;
    in
    mkCheck
      "public-no-sandbox-removed"
      "public wrapper/launcher no longer expose a --no-sandbox escape hatch"
      "SECURITY: public wrapper or launcher still reference --no-sandbox / AGENT_ALLOW_NOSANDBOX"
      (!(lib.hasInfix "no-sandbox" wrapperSource)
       && !(lib.hasInfix "AGENT_ALLOW_NOSANDBOX" wrapperSource)
       && !(lib.hasInfix "AGENT_ALLOW_NOSANDBOX" launcherSource));

  # --- Phase 147: Spec-driven test coverage ---

  nix-channels-disabled = mkCheck
    "nix-channels-disabled"
    "Nix channels disabled on all hosts"
    "nix.channel.enable is true or nixPath is not empty"
    (!servicesCfg.nix.channel.enable && !devCfg.nix.channel.enable);

  default-packages-empty = mkCheck
    "default-packages-empty"
    "environment.defaultPackages is empty (declarative-only)"
    "environment.defaultPackages is non-empty"
    (servicesCfg.environment.defaultPackages == [] && devCfg.environment.defaultPackages == []);

  mutable-users-disabled = mkCheck
    "mutable-users-disabled"
    "users.mutableUsers is false on all hosts"
    "users.mutableUsers is true — runtime user modification possible"
    (!servicesCfg.users.mutableUsers && !devCfg.users.mutableUsers);

  nftables-enabled = mkCheck
    "nftables-enabled"
    "nftables backend enabled on all hosts"
    "networking.nftables.enable is false"
    (servicesCfg.networking.nftables.enable && devCfg.networking.nftables.enable);

  fail2ban-disabled = mkCheck
    "fail2ban-disabled"
    "fail2ban is disabled (key-only auth + MaxAuthTries is sufficient)"
    "services.fail2ban.enable is true"
    (!servicesCfg.services.fail2ban.enable && !devCfg.services.fail2ban.enable);

  impermanence-hide-mounts =
    let
      source = builtins.readFile ../../modules/impermanence.nix;
    in
    mkCheck
      "impermanence-hide-mounts"
      "impermanence hideMounts is true"
      "modules/impermanence.nix missing hideMounts = true"
      (lib.hasInfix "hideMounts = true" source);

  secrets-depend-on-persist =
    let
      source = builtins.readFile ../../modules/impermanence.nix;
    in
    mkCheck
      "secrets-depend-on-persist"
      "setupSecrets activation depends on persist-files"
      "modules/impermanence.nix missing setupSecrets.deps persist-files dependency"
      (lib.hasInfix "setupSecrets" source && lib.hasInfix "persist-files" source);

  wrapper-nix-store-guard =
    let
      source = builtins.readFile ../../scripts/agent-wrapper.sh;
    in
    mkCheck
      "wrapper-nix-store-guard"
      "agent-wrapper.sh validates AGENT_REAL_BINARY is in /nix/store"
      "agent-wrapper.sh missing /nix/store guard for AGENT_REAL_BINARY"
      (lib.hasInfix "/nix/store" source && lib.hasInfix "AGENT_REAL_BINARY must be in /nix/store" source);

  wrapper-credential-proxy-flow =
    let
      source = builtins.readFile ../../scripts/agent-wrapper.sh;
    in
    mkCheck
      "wrapper-credential-proxy-flow"
      "agent-wrapper.sh starts credential proxy and generates per-session tokens"
      "agent-wrapper.sh missing credential proxy flow (generate_session_token, proxy_port_file)"
      (lib.hasInfix "generate_session_token" source
       && lib.hasInfix "proxy_port_file" source
       && lib.hasInfix "TSURF_PROXY_ROUTE" source);

  wrapper-supply-chain-hardening =
    let
      source = builtins.readFile ../../scripts/agent-wrapper.sh;
    in
    mkCheck
      "wrapper-supply-chain-hardening"
      "agent-wrapper.sh sets supply chain hardening env vars"
      "agent-wrapper.sh missing NPM_CONFIG_IGNORE_SCRIPTS or NPM_CONFIG_AUDIT"
      (lib.hasInfix "NPM_CONFIG_IGNORE_SCRIPTS=true" source
       && lib.hasInfix "NPM_CONFIG_AUDIT=true" source
       && lib.hasInfix "NPM_CONFIG_SAVE_EXACT=true" source);

  wrapper-telemetry-suppression =
    let
      source = builtins.readFile ../../scripts/agent-wrapper.sh;
    in
    mkCheck
      "wrapper-telemetry-suppression"
      "agent-wrapper.sh suppresses telemetry"
      "agent-wrapper.sh missing DISABLE_TELEMETRY or DISABLE_ERROR_REPORTING"
      (lib.hasInfix "DISABLE_TELEMETRY=1" source
       && lib.hasInfix "DISABLE_ERROR_REPORTING=1" source);

  claude-settings-mcp-disabled =
    let
      source = builtins.readFile ../../modules/agent-sandbox.nix;
    in
    mkCheck
      "claude-settings-mcp-disabled"
      "Claude managed settings disable MCP auto-loading"
      "agent-sandbox.nix missing enableAllProjectMcpServers = false"
      (lib.hasInfix "enableAllProjectMcpServers" source
       && lib.hasInfix "false" source);

  launcher-seccomp-filter =
    let
      source = builtins.readFile ../../modules/agent-launcher.nix;
    in
    mkCheck
      "launcher-seccomp-filter"
      "agent-launcher.nix launcher includes seccomp SystemCallFilter"
      "agent-launcher.nix missing SystemCallFilter for @mount/@debug/bpf"
      (lib.hasInfix "SystemCallFilter" source
       && lib.hasInfix "@mount" source
       && lib.hasInfix "bpf" source);

  no-systemd-initrd = mkCheck
    "no-systemd-initrd"
    "boot.initrd.systemd.enable is false on all hosts"
    "boot.initrd.systemd.enable is true — non-systemd initrd required for BTRFS rollback"
    (!servicesCfg.boot.initrd.systemd.enable && !devCfg.boot.initrd.systemd.enable);

  # --- Phase 152: Generic launcher architecture ---

  generic-launcher-enabled = mkCheck
    "generic-launcher-enabled"
    "dev host has generic agent launcher enabled"
    "dev host services.agentLauncher.enable is false — no agent wrappers generated"
    devCfg.services.agentLauncher.enable;

  no-dev-user = mkCheck
    "no-dev-user"
    "dev user no longer exists in config"
    "users.users.dev still defined — remove the dev user (root+agent model)"
    (!(builtins.hasAttr "dev" devCfg.users.users)
     || !(devCfg.users.users.dev.isNormalUser or false));

}

# --- Private overlay test extension pattern ---
#
# The private overlay (private-tsurf) extends these checks by importing
# this file and appending private-specific assertions.
