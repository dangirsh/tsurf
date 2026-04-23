# tests/eval/config-checks.nix — Nix eval-time assertions for tsurf eval fixtures.
# @decision TEST-48-01: Keep checks purely eval-time with runCommand to catch regressions offline.
{
  self,
  pkgs,
  lib,
}:
let
  servicesCfg = self.nixosConfigurations."eval-services".config;
  devCfg = self.nixosConfigurations."eval-dev".config;
  altAgentCfg = self.nixosConfigurations."eval-dev-alt-agent".config;
  extraDenyCfg = self.nixosConfigurations."eval-dev-extra-deny".config;
  devAgentUser = devCfg.tsurf.agent.user;
  altAgentUser = altAgentCfg.tsurf.agent.user;
  altAgentHome = altAgentCfg.tsurf.agent.home;
  mkCheck =
    name: passMessage: failMessage: condition:
    pkgs.runCommand name { } ''
      ${
        if condition then
          ''
            echo "PASS: ${passMessage}"
            touch "$out"
          ''
        else
          ''
            echo "FAIL: ${failMessage}"
            exit 1
          ''
      }
    '';
in
{
  eval-services = pkgs.runCommand "eval-services" { } ''
    echo "eval-services config evaluates: ${
      self.nixosConfigurations."eval-services".config.system.build.toplevel
    }"
    touch "$out"
  '';

  eval-dev = pkgs.runCommand "eval-dev" { } ''
    echo "eval-dev config evaluates: ${
      self.nixosConfigurations."eval-dev".config.system.build.toplevel
    }"
    touch "$out"
  '';

  eval-dev-alt-agent = pkgs.runCommand "eval-dev-alt-agent" { } ''
    echo "eval-dev-alt-agent config evaluates: ${
      self.nixosConfigurations."eval-dev-alt-agent".config.system.build.toplevel
    }"
    touch "$out"
  '';

  # Phase 145: nix-mineral hardening must be enabled on all hosts. [SEC-145-05]
  nix-mineral-services =
    mkCheck "nix-mineral-services" "services host has nix-mineral hardening enabled"
      "SECURITY: services host does not have nix-mineral enabled"
      servicesCfg.nix-mineral.enable;

  nix-mineral-dev =
    mkCheck "nix-mineral-dev" "dev host has nix-mineral hardening enabled"
      "SECURITY: dev host does not have nix-mineral enabled"
      devCfg.nix-mineral.enable;

  # Phase 160: Explicit security settings — self-backing, not inherited from srvos/nix-mineral.
  # Note: openssh.settings values are booleans in the evaluated config (confirmed via nix eval).
  # Sysctl values are strings in the evaluated config (NixOS coerces int/bool to strings).
  explicit-firewall-enabled =
    mkCheck "explicit-firewall-enabled" "firewall explicitly enabled in networking module"
      "networking.firewall.enable is false — must be explicitly set in modules/networking.nix"
      devCfg.networking.firewall.enable;

  explicit-ssh-password-auth =
    mkCheck "explicit-ssh-password-auth" "SSH PasswordAuthentication explicitly disabled"
      "SSH PasswordAuthentication is not false — must be explicitly set in modules/networking.nix"
      (devCfg.services.openssh.settings.PasswordAuthentication == false);

  explicit-ssh-kbd-auth =
    mkCheck "explicit-ssh-kbd-auth" "SSH KbdInteractiveAuthentication explicitly disabled"
      "SSH KbdInteractiveAuthentication is not false — must be explicitly set in modules/networking.nix"
      (devCfg.services.openssh.settings.KbdInteractiveAuthentication == false);

  explicit-ssh-x11 =
    mkCheck "explicit-ssh-x11" "SSH X11Forwarding explicitly disabled"
      "SSH X11Forwarding is not false — must be explicitly set in modules/networking.nix"
      (devCfg.services.openssh.settings.X11Forwarding == false);

  explicit-kexec-disabled =
    mkCheck "explicit-kexec-disabled" "kexec_load_disabled sysctl is set"
      "boot.kernel.sysctl.kernel.kexec_load_disabled is not \"1\" — must be set in modules/base.nix"
      (toString devCfg.boot.kernel.sysctl."kernel.kexec_load_disabled" == "1");

  explicit-bpf-restricted =
    mkCheck "explicit-bpf-restricted" "unprivileged_bpf_disabled sysctl is set"
      "boot.kernel.sysctl.kernel.unprivileged_bpf_disabled is not \"1\" — must be set in modules/base.nix"
      (toString devCfg.boot.kernel.sysctl."kernel.unprivileged_bpf_disabled" == "1");

  explicit-io-uring-disabled =
    mkCheck "explicit-io-uring-disabled" "io_uring_disabled sysctl is set to 2 (kernel-wide disable)"
      "boot.kernel.sysctl.kernel.io_uring_disabled is not \"2\" — must be set in modules/base.nix"
      (toString devCfg.boot.kernel.sysctl."kernel.io_uring_disabled" == "2");

  # Ports are conditional: 80/443 on nginx.enable.
  # Public template has no nginx by default.
  firewall-ports-services =
    let
      actual = builtins.sort builtins.lessThan servicesCfg.networking.firewall.allowedTCPPorts;
      expected = [
        22
      ]
      ++ lib.optionals servicesCfg.services.nginx.enable [
        80
        443
      ];
    in
    mkCheck "firewall-ports-services" "services host firewall ports match nginx state"
      "services host allowedTCPPorts=${builtins.toJSON actual} expected=${builtins.toJSON expected}"
      (actual == expected);

  firewall-ports-dev =
    let
      actual = builtins.sort builtins.lessThan devCfg.networking.firewall.allowedTCPPorts;
      expected = [
        22
      ]
      ++ lib.optionals devCfg.services.nginx.enable [
        80
        443
      ];
    in
    mkCheck "firewall-ports-dev" "dev host firewall ports match nginx state"
      "dev host allowedTCPPorts=${builtins.toJSON actual} expected=${builtins.toJSON expected}"
      (actual == expected);

  trusted-interfaces-loopback-only-services =
    mkCheck "trusted-interfaces-loopback-only-services" "services host trusts loopback only"
      "services host trusts a non-loopback interface — keep the public firewall model interface-agnostic"
      (servicesCfg.networking.firewall.trustedInterfaces == [ "lo" ]);

  trusted-interfaces-loopback-only-dev =
    mkCheck "trusted-interfaces-loopback-only-dev" "dev host trusts loopback only"
      "dev host trusts a non-loopback interface — keep the public firewall model interface-agnostic"
      (devCfg.networking.firewall.trustedInterfaces == [ "lo" ]);

  ssh-ed25519-only =
    let
      hostKeyTypes = map (k: k.type) servicesCfg.services.openssh.hostKeys;
    in
    mkCheck "ssh-ed25519-only" "SSH host key types are ed25519 only"
      "SSH host key types=${builtins.toJSON hostKeyTypes}, expected [\"ed25519\"]"
      (hostKeyTypes == [ "ed25519" ]);

  metadata-block =
    mkCheck "metadata-block" "agent-metadata-block nftables table is defined"
      "agent-metadata-block nftables table not found"
      (builtins.hasAttr "agent-metadata-block" servicesCfg.networking.nftables.tables);

  agent-egress-table =
    mkCheck "agent-egress-table" "agent-egress nftables table is defined"
      "agent-egress nftables table not found"
      (builtins.hasAttr "agent-egress" servicesCfg.networking.nftables.tables);

  agent-egress-policy =
    let
      content = servicesCfg.networking.nftables.tables.agent-egress.content;
      agentUid = toString servicesCfg.tsurf.agent.uid;
    in
    mkCheck "agent-egress-policy" "agent-egress policy scopes by agent UID and blocks private ranges"
      "agent-egress policy missing UID scoping, private-range drops, or HTTPS allowlist"
      (
        lib.hasInfix "meta skuid ${agentUid}" content
        && lib.hasInfix "100.64.0.0/10" content
        && lib.hasInfix "443" content
        && lib.hasInfix "drop" content
      );

  agent-sandbox-dev-enabled =
    mkCheck "agent-sandbox-dev-enabled" "dev host agent sandbox wrappers are enabled"
      "dev host services.agentSandbox.enable is false — dev agents run unsandboxed"
      devCfg.services.agentSandbox.enable;

  # --- Source-text regression guards ---

  core-agent-sandbox-only-claude =
    let
      source = builtins.readFile ../../modules/agent-sandbox.nix;
    in
    mkCheck "core-agent-sandbox-only-claude" "agent-sandbox core wrapper declares only claude"
      "agent-sandbox.nix still hardcodes non-claude wrappers; move them to extras/"
      (
        lib.hasInfix "claude" source
        && !(lib.hasInfix "pkgs.codex" source)
        && !(lib.hasInfix "pkgs.pi-coding-agent" source)
      );

  nono-sandbox-dev-enabled =
    mkCheck "nono-sandbox-dev-enabled" "dev host nono sandbox module is enabled"
      "dev host services.nonoSandbox.enable is false — nono not active"
      devCfg.services.nonoSandbox.enable;

  agent-journald-logging =
    mkCheck "agent-journald-logging"
      "agent wrapper uses journald-only launch logging (no file audit log)"
      "agent-wrapper.sh still contains audit_log or AGENT_AUDIT_LOG — file audit not fully removed"
      (
        let
          src = builtins.readFile ../../scripts/agent-wrapper.sh;
        in
        lib.hasInfix "journal_log" src
        && !lib.hasInfix "audit_log" src
        && !lib.hasInfix "AGENT_AUDIT_LOG" src
      );

  # --- Phase 119: Secure-by-default host configs + eval fixture checks ---

  secure-host-services =
    mkCheck "secure-host-services" "hosts/services/default.nix does not set allowUnsafePlaceholders"
      "SECURITY: hosts/services/default.nix sets allowUnsafePlaceholders — host source must be secure by default"
      (!(lib.hasInfix "allowUnsafePlaceholders" (builtins.readFile ../../hosts/services/default.nix)));

  secure-host-dev =
    mkCheck "secure-host-dev" "hosts/dev/default.nix does not set allowUnsafePlaceholders"
      "SECURITY: hosts/dev/default.nix sets allowUnsafePlaceholders — host source must be secure by default"
      (!(lib.hasInfix "allowUnsafePlaceholders" (builtins.readFile ../../hosts/dev/default.nix)));

  fixture-mode-services =
    mkCheck "fixture-mode-services"
      "services eval fixture has allowUnsafePlaceholders = true (CI fixture correct)"
      "eval fixture services missing allowUnsafePlaceholders — check flake.nix mkEvalFixture"
      servicesCfg.tsurf.template.allowUnsafePlaceholders;

  fixture-mode-dev =
    mkCheck "fixture-mode-dev"
      "dev eval fixture has allowUnsafePlaceholders = true (CI fixture correct)"
      "eval fixture dev missing allowUnsafePlaceholders — check flake.nix mkEvalFixture"
      devCfg.tsurf.template.allowUnsafePlaceholders;

  fixture-root-login-bypass =
    mkCheck "fixture-root-login-bypass"
      "eval fixtures explicitly bypass the root-login lockout assertion"
      "eval fixtures do not set users.allowNoPasswordLogin — public flake check cannot evaluate without a private root key"
      (servicesCfg.users.allowNoPasswordLogin && devCfg.users.allowNoPasswordLogin);

  fixture-output-names =
    mkCheck "fixture-output-names" "public flake exports only clearly named eval fixture outputs"
      "public flake still exports deploy-looking nixosConfigurations (non-eval-prefixed)"
      (
        let
          names = builtins.attrNames self.nixosConfigurations;
        in
        builtins.length names > 0 && builtins.all (name: lib.hasPrefix "eval-" name) names
      );

  public-deploy-empty =
    mkCheck "public-deploy-empty" "public flake exports no public deploy.nodes targets"
      "public flake still exports deploy.nodes.* — deploy targets must live in a private overlay"
      (!(self ? deploy) || (self.deploy.nodes or { }) == { });

  cass-default-disabled =
    let
      source = builtins.readFile ../../extras/cass.nix;
    in
    mkCheck "cass-default-disabled" "CASS indexer defaults to disabled when imported"
      "extras/cass.nix still has default = true — CASS must be opt-in"
      (!(lib.hasInfix "default = true" source));

  restic-opt-in =
    mkCheck "restic-opt-in" "restic backup not active in public services config (opt-in works)"
      "restic backup active in public template — services.resticStarter.enable should be false"
      (!servicesCfg.services.resticStarter.enable);

  headscale-opt-in =
    mkCheck "headscale-opt-in" "headscale not active in public services config (opt-in works)"
      "headscale active in public template — tsurf.headscale.enable should be false"
      (!(lib.attrByPath [ "tsurf" "headscale" "enable" ] false servicesCfg));

  headscale-port-internal =
    let
      source = builtins.readFile ../../modules/networking.nix;
    in
    mkCheck "headscale-port-internal" "headscale port 8080 registered in internalOnlyPorts"
      "modules/networking.nix missing headscale in internalOnlyPorts"
      (lib.hasInfix "\"8080\" = \"headscale\"" source);

  headscale-localhost-bind =
    let
      source = builtins.readFile ../../modules/headscale.nix;
    in
    mkCheck "headscale-localhost-bind" "headscale binds to localhost only"
      "modules/headscale.nix missing 127.0.0.1 bind address"
      (lib.hasInfix "address = \"127.0.0.1\"" source);

  headscale-dns-nameservers =
    let
      source = builtins.readFile ../../modules/headscale.nix;
    in
    mkCheck "headscale-dns-nameservers" "headscale sets dns.nameservers.global (25.11 compat)"
      "modules/headscale.nix missing dns.nameservers.global — headscale 0.26+ requires explicit nameservers"
      (lib.hasInfix "dns.nameservers.global" source);

  headscale-persistence =
    let
      source = builtins.readFile ../../modules/headscale.nix;
    in
    mkCheck "headscale-persistence" "headscale state persisted under impermanence"
      "modules/headscale.nix missing /var/lib/headscale persistence declaration"
      (lib.hasInfix "/var/lib/headscale" source && lib.hasInfix "persistence" source);

  headscale-websockets =
    let
      source = builtins.readFile ../../modules/headscale.nix;
    in
    mkCheck "headscale-websockets" "headscale nginx proxy enables WebSocket support"
      "modules/headscale.nix missing proxyWebsockets — Tailscale control protocol requires WebSocket"
      (lib.hasInfix "proxyWebsockets = true" source);

  # Stale-phrase check: banned phrases must not appear in key docs.
  stale-phrases-claude-md =
    let
      source = builtins.readFile ../../CLAUDE.md;
    in
    mkCheck "stale-phrases-claude-md" "CLAUDE.md contains no banned stale phrases"
      "CLAUDE.md contains stale phrase (sibling repos readable)"
      (!(lib.hasInfix "sibling repos readable" source));

  stale-phrases-readme =
    let
      source = builtins.readFile ../../README.md;
    in
    mkCheck "stale-phrases-readme" "README.md contains no banned stale phrases"
      "README.md contains stale phrase (sibling repos readable)"
      (!(lib.hasInfix "sibling repos readable" source));

  # Phase 159: nono built-in credential proxy
  proxy-credential-wrapper =
    mkCheck "proxy-credential-wrapper"
      "agent wrapper loads secrets for nono credential proxy and drops the child with setpriv"
      "agent-wrapper.sh missing AGENT_CREDENTIAL_SECRETS or setpriv — credential proxy flow broken"
      (
        let
          src = builtins.readFile ../../scripts/agent-wrapper.sh;
        in
        lib.hasInfix "AGENT_CREDENTIAL_SECRETS" src && lib.hasInfix "setpriv" src
      );

  proxy-credential-profile =
    let
      profile = builtins.fromJSON (
        builtins.readFile devCfg.environment.etc."nono/profiles/tsurf.json".source
      );
    in
    mkCheck "proxy-credential-profile" "base nono profile has no credential wiring (credentials live in per-agent profiles)"
      "base tsurf.json nono profile should not contain network.custom_credentials — those belong in per-agent profiles"
      (
        !(builtins.hasAttr "custom_credentials" (profile.network or {}))
        && !(builtins.hasAttr "credentials" (profile.network or {}))
      );

  claude-profile-credential-proxy =
    let
      profile = builtins.fromJSON (
        builtins.readFile devCfg.environment.etc."nono/profiles/tsurf-claude.json".source
      );
      creds = profile.network.credentials or [];
      customCreds = profile.network.custom_credentials or {};
    in
    mkCheck "claude-profile-credential-proxy"
      "generated Claude nono profile wires credential proxy with env:// URI"
      "tsurf-claude nono profile missing network.credentials or custom_credentials with env:// credential_key"
      (
        builtins.elem "anthropic" creds
        && builtins.hasAttr "anthropic" customCreds
        && lib.hasPrefix "env://" customCreds.anthropic.credential_key
      );

  nono-profile-denies-run-secrets =
    mkCheck "nono-profile-denies-run-secrets" "generated nono profile explicitly denies /run/secrets"
      "nono profile deny list is missing /run/secrets"
      (
        let
          profile = builtins.fromJSON (
            builtins.readFile devCfg.environment.etc."nono/profiles/tsurf.json".source
          );
        in
        builtins.elem "/run/secrets" profile.filesystem.deny
      );

  nono-base-profile-generic =
    let
      profile = builtins.fromJSON (
        builtins.readFile devCfg.environment.etc."nono/profiles/tsurf.json".source
      );
      allow = profile.filesystem.allow or [ ];
      allowFile = profile.filesystem.allow_file or [ ];
      groups = profile.security.groups or [ ];
      home = devCfg.tsurf.agent.home;
    in
    mkCheck "nono-base-profile-generic" "base tsurf nono profile is generic and not Claude-shaped"
      "modules/nono.nix still bakes Claude-specific paths, groups, or extends into the base profile"
      (
        !(builtins.hasAttr "extends" profile)
        && !(builtins.elem "${home}/.claude" allow)
        && !(builtins.elem "${home}/.config/claude" allow)
        && !(builtins.elem "${home}/.claude.json" allowFile)
        && !(builtins.elem "${home}/.claude.json.lock" allowFile)
        && !(builtins.elem "claude_code_linux" groups)
        && !(builtins.elem "claude_cache_linux" groups)
      );

  claude-profile-adds-claude-state =
    let
      profile = builtins.fromJSON (
        builtins.readFile devCfg.environment.etc."nono/profiles/tsurf-claude.json".source
      );
      allow = profile.filesystem.allow or [ ];
      allowFile = profile.filesystem.allow_file or [ ];
      home = devCfg.tsurf.agent.home;
    in
    mkCheck "claude-profile-adds-claude-state"
      "Claude wrapper adds only the Claude-specific state paths on top of the base profile"
      "generated tsurf-claude nono profile is missing Claude state paths after the base-profile simplification"
      (
        builtins.elem "${home}/.claude" allow
        && builtins.elem "${home}/.config/claude" allow
        && builtins.elem "${home}/.claude.json" allowFile
        && builtins.elem "${home}/.claude.json.lock" allowFile
      );

  agent-launcher-extra-deny-wired =
    let
      source = builtins.readFile ../../modules/agent-launcher.nix;
    in
    mkCheck "agent-launcher-extra-deny-wired"
      "agent-launcher wires per-agent extraDeny entries into generated nono profiles"
      "modules/agent-launcher.nix defines extraDeny but does not merge it into filesystem.deny"
      (lib.hasInfix "deny = agentDef.nonoProfile.extraDeny;" source);

  deploy-no-repo-source =
    let
      deploySrc = builtins.readFile ../../scripts/deploy.sh;
    in
    mkCheck "deploy-no-repo-source" "deploy.sh has no repo-controlled source calls"
      "deploy.sh sources repo-controlled scripts — remove source calls for deploy-post.sh or similar"
      (!(lib.hasInfix "source \"$FLAKE_DIR" deploySrc));

  # --- Phase 115/152: agent user split ---

  agent-user-exists-dev =
    mkCheck "agent-user-exists-dev" "dev host agent user exists and is a normal user"
      "dev host agent user missing or not a normal user"
      (
        builtins.hasAttr devAgentUser devCfg.users.users
        && (builtins.getAttr devAgentUser devCfg.users.users).isNormalUser
      );

  agent-not-in-wheel =
    mkCheck "agent-not-in-wheel" "agent user is not in wheel"
      "agent user is still in wheel — launcher sudo should come from explicit sudoers rules only"
      (!(builtins.elem "wheel" (builtins.getAttr devAgentUser devCfg.users.users).extraGroups));

  agent-user-no-docker =
    mkCheck "agent-user-no-docker" "agent user is not in docker group"
      "SECURITY: agent user is in docker group — must not have docker access"
      (!(builtins.elem "docker" (builtins.getAttr devAgentUser devCfg.users.users).extraGroups));

  agent-uid-explicit =
    mkCheck "agent-uid-explicit" "agent user has explicit UID defined"
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
    mkCheck "impermanence-agent-home" "agent-sandbox declares agent persist paths"
      "agent-sandbox.nix is missing expected agent state suffixes"
      (missingSuffixes == [ ]);

  alt-agent-parameterization =
    mkCheck "alt-agent-parameterization"
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
    mkCheck "agent-binaries-not-in-path" "Raw agent binaries not in agent-compute.nix systemPackages"
      "SECURITY: raw agent binaries found in agent-compute.nix systemPackages — use sandboxed wrappers only"
      (
        !(lib.hasInfix "pkgs.claude-code" source)
        && !(lib.hasInfix "pkgs.codex" source)
        && !(lib.hasInfix "pkgs.pi-coding-agent" source)
      );

  agent-slice-exists-dev =
    mkCheck "agent-slice-exists-dev" "tsurf-agents systemd slice defined on dev host"
      "tsurf-agents slice missing from dev host"
      (builtins.hasAttr "tsurf-agents" devCfg.systemd.slices);

  # --- Phase 119/152: brokered launch model ---

  brokered-launch-launcher =
    let
      source = builtins.readFile ../../modules/agent-launcher.nix;
    in
    mkCheck "brokered-launch-launcher" "agent-launcher.nix defines immutable per-agent launchers"
      "agent-launcher.nix still relies on the generic tsurf-agent-launch boundary"
      (lib.hasInfix "tsurf-launch-" source && !(lib.hasInfix "tsurf-agent-launch" source));

  brokered-launch-systemd-run =
    let
      source = builtins.readFile ../../modules/agent-launcher.nix;
    in
    mkCheck "brokered-launch-systemd-run"
      "agent-launcher.nix uses systemd-run for privilege drop to agent user"
      "agent-launcher.nix missing systemd-run — wrapper runs as calling user (no privilege drop)"
      (lib.hasInfix "systemd-run" source);

  brokered-launch-sudoers =
    let
      source = builtins.readFile ../../modules/agent-launcher.nix;
    in
    mkCheck "brokered-launch-sudoers"
      "agent-launcher.nix configures sudo extraRules without SETENV or caller env passthrough"
      "agent-launcher.nix sudoers path still uses SETENV or preserve-env"
      (
        lib.hasInfix "security.sudo.extraRules" source
        && !(lib.hasInfix "\"SETENV\"" source)
        && !(lib.hasInfix "--preserve-env" source)
      );

  brokered-launch-agent-fallback =
    let
      source = builtins.readFile ../../modules/agent-launcher.nix;
    in
    mkCheck "brokered-launch-agent-fallback"
      "agent-launcher.nix keeps the launcher root-brokered and only short-circuits for root"
      "agent-launcher.nix still has an agent-user direct exec path that bypasses the root credential broker"
      (lib.hasInfix "id -u" source && lib.hasInfix "\"0\"" source && !lib.hasInfix "id -un" source);

  launcher-credential-proxy =
    let
      source = builtins.readFile ../../modules/agent-launcher.nix;
    in
    mkCheck "launcher-credential-proxy"
      "agent-launcher.nix generates nono custom_credentials with env:// URIs for credential proxy"
      "agent-launcher.nix missing custom_credentials or env:// wiring — credential proxy not configured"
      (
        lib.hasInfix "custom_credentials" source
        && lib.hasInfix "env://" source
        && lib.hasInfix "credentialServices" source
        && !lib.hasInfix "credential-proxy.py" source
      );

  launcher-extra-deny =
    let
      source = builtins.readFile ../../modules/agent-launcher.nix;
    in
    mkCheck "launcher-extra-deny" "agent-launcher.nix merges per-agent nonoProfile.extraDeny rules"
      "agent-launcher.nix defines extraDeny but does not write deny rules into generated profiles"
      (lib.hasInfix "extraDeny" source && lib.hasInfix "deny = agentDef.nonoProfile.extraDeny;" source);

  # --- Phase 120: agent API key ownership (SEC-04) ---

  agent-api-key-ownership-dev =
    mkCheck "agent-api-key-ownership-dev"
      "anthropic-api-key and openai-api-key owned by root on dev host"
      "SECURITY: anthropic-api-key or openai-api-key not owned by root — agent principal can read raw provider keys"
      (
        devCfg.sops.secrets."anthropic-api-key".owner == "root"
        && devCfg.sops.secrets."openai-api-key".owner == "root"
      );

  # --- Phase 124: Nix daemon user restrictions ---

  nix-allowed-users-services =
    mkCheck "nix-allowed-users-services"
      "services host nix.settings.allowed-users restricts daemon access"
      "services host nix.settings.allowed-users is not set or too permissive"
      (
        servicesCfg.nix.settings.allowed-users == [
          "root"
          servicesCfg.tsurf.agent.user
        ]
      );

  nix-trusted-users-services =
    mkCheck "nix-trusted-users-services" "services host nix.settings.trusted-users is root-only"
      "services host nix.settings.trusted-users includes non-root entries"
      (servicesCfg.nix.settings.trusted-users == [ "root" ]);

  # --- Phase 124: Clone-repos credential safety ---

  clone-repos-no-cli-credentials =
    let
      source = builtins.readFile ../../extras/scripts/clone-repos.sh;
    in
    mkCheck "clone-repos-no-cli-credentials" "clone-repos.sh uses GIT_ASKPASS (no credentials on CLI)"
      "clone-repos.sh passes credentials via git -c extraheader - use GIT_ASKPASS pattern instead"
      (lib.hasInfix "GIT_ASKPASS" source && !(lib.hasInfix "extraheader" source));

  home-profile-no-deprecated-options =
    let
      source = builtins.readFile ../../extras/home/default.nix;
    in
    mkCheck "home-profile-no-deprecated-options"
      "extras/home/default.nix avoids deprecated Home Manager git/ssh options"
      "extras/home/default.nix still uses deprecated Home Manager git/ssh options"
      (
        !(lib.hasInfix "programs.git.userName" source)
        && !(lib.hasInfix "programs.git.userEmail" source)
        && !(lib.hasInfix "programs.ssh.controlMaster" source)
        && !(lib.hasInfix "programs.ssh.controlPersist" source)
        && !(lib.hasInfix "programs.ssh.hashKnownHosts" source)
        && !(lib.hasInfix "programs.ssh.serverAliveInterval" source)
      );

  agent-scripts-avoid-global-tmp =
    let
      cloneSource = builtins.readFile ../../extras/scripts/clone-repos.sh;
      deploySource = builtins.readFile ../../scripts/deploy.sh;
    in
    mkCheck "agent-scripts-avoid-global-tmp" "agent helper scripts avoid /tmp for transient state"
      "agent helper scripts still write transient files under /tmp"
      (
        !(lib.hasInfix "mktemp /tmp" cloneSource)
        && !(lib.hasInfix " /tmp/" deploySource)
        && !(lib.hasInfix "=/tmp/" deploySource)
      );

  tsurf-status-persistent-services =
    let
      source = builtins.readFile ../../scripts/tsurf-status.sh;
    in
    mkCheck "tsurf-status-persistent-services"
      "tsurf-status checks only persistent units and documents supported arguments accurately"
      "scripts/tsurf-status.sh still references transient units or is missing expected persistent units"
      (
        !(lib.hasInfix "agent-launch-claude" source)
        && lib.hasInfix "all" source
        && lib.hasInfix "sshd.service" source
        && lib.hasInfix "nftables.service" source
        && lib.hasInfix "sops-install-secrets.service" source
        && lib.hasInfix "tsurf-cass-index.timer" source
      );

  # --- Phase 124: Cost-tracker least privilege ---

  cost-tracker-dynamic-user =
    let
      source = builtins.readFile ../../extras/cost-tracker.nix;
    in
    mkCheck "cost-tracker-dynamic-user" "cost-tracker uses DynamicUser for least privilege"
      "cost-tracker.nix missing DynamicUser = true — service runs as root"
      (lib.hasInfix "DynamicUser = true" source);

  example-code-review-uses-wrapper =
    let
      source = builtins.readFile ../../examples/private-overlay/modules/code-review.nix;
    in
    mkCheck "example-code-review-uses-wrapper"
      "example scheduled code-review agent uses the generated sandboxed wrapper"
      "examples/private-overlay/modules/code-review.nix bypasses the brokered wrapper path with a raw claude ExecStart"
      (
        lib.hasInfix "/run/current-system/sw/bin/code-review" source
        && !(lib.hasInfix "package}/bin/claude" source)
      );

  # --- Phase 125: systemd hardening baseline ---

  systemd-hardening-baseline =
    let
      costTrackerSource = builtins.readFile ../../extras/cost-tracker.nix;
      cassSource = builtins.readFile ../../extras/cass.nix;
    in
    mkCheck "systemd-hardening-baseline" "All project services have SystemCallArchitectures=native"
      "SECURITY: one or more services missing SystemCallArchitectures=native"
      (
        lib.hasInfix "SystemCallArchitectures = \"native\"" costTrackerSource
        && lib.hasInfix "SystemCallArchitectures = \"native\"" cassSource
      );

  cass-indexer-resource-limits =
    let
      source = builtins.readFile ../../extras/cass.nix;
    in
    mkCheck "cass-indexer-resource-limits" "cass indexer is throttled as a low-priority background task"
      "extras/cass.nix is missing the expected CASS resource limits or system timer"
      (
        lib.hasInfix "CPUQuota = \"25%\"" source
        && lib.hasInfix "MemoryMax = \"512M\"" source
        && lib.hasInfix "IOSchedulingClass = \"idle\"" source
        && lib.hasInfix "systemd.timers.tsurf-cass-index" source
      );

  cost-tracker-secret-capability =
    let
      source = builtins.readFile ../../extras/cost-tracker.nix;
    in
    mkCheck "cost-tracker-secret-capability"
      "cost-tracker explicitly grants CAP_DAC_READ_SEARCH ambiently for secret reads"
      "cost-tracker.nix bounds CAP_DAC_READ_SEARCH without AmbientCapabilities — DynamicUser service cannot read configured secret files"
      (
        lib.hasInfix "AmbientCapabilities = [ \"CAP_DAC_READ_SEARCH\" ]" source
        && lib.hasInfix "CapabilityBoundingSet = [ \"CAP_DAC_READ_SEARCH\" ]" source
      );

  cost-tracker-provider-label =
    let
      source = builtins.readFile ../../extras/cost-tracker.nix;
    in
    mkCheck "cost-tracker-provider-label" "cost-tracker exposes and serializes optional provider labels"
      "extras/cost-tracker.nix drops provider labels even though cost-tracker.py reads them"
      (lib.hasInfix "label = lib.mkOption" source && lib.hasInfix "label = p.label;" source);

  # --- Sandbox read-scope regression guards ---

  sandbox-workspace-root-fail-closed =
    let
      source = builtins.readFile ../../scripts/agent-wrapper.sh;
    in
    mkCheck "sandbox-workspace-root-fail-closed"
      "agent-wrapper.sh has fail-closed top-level workspace validation"
      "agent-wrapper.sh missing top-level workspace scoping — agents may read across workspaces"
      (
        lib.hasInfix "workspace_root=" source
        && lib.hasInfix "top-level workspace beneath" source
        && lib.hasInfix "exit 1" source
        && !(lib.hasInfix "rev-parse --show-toplevel" source)
      );

  sandbox-refuses-project-root-read =
    let
      source = builtins.readFile ../../scripts/agent-wrapper.sh;
    in
    mkCheck "sandbox-refuses-project-root-read"
      "agent-wrapper.sh refuses to grant read access to entire project root"
      "agent-wrapper.sh missing project-root refusal — agents could read all repos"
      (lib.hasInfix "refusing to grant read access to the entire project root" source);

  public-no-sandbox-removed =
    let
      wrapperSource = builtins.readFile ../../scripts/agent-wrapper.sh;
      launcherSource = builtins.readFile ../../modules/agent-launcher.nix;
    in
    mkCheck "public-no-sandbox-removed"
      "public wrapper/launcher no longer expose a --no-sandbox escape hatch"
      "SECURITY: public wrapper or launcher still reference --no-sandbox / AGENT_ALLOW_NOSANDBOX"
      (
        !(lib.hasInfix "no-sandbox" wrapperSource)
        && !(lib.hasInfix "AGENT_ALLOW_NOSANDBOX" wrapperSource)
        && !(lib.hasInfix "AGENT_ALLOW_NOSANDBOX" launcherSource)
      );

  # --- Phase 147: Spec-driven test coverage ---

  nix-channels-disabled =
    mkCheck "nix-channels-disabled" "Nix channels disabled on all hosts"
      "nix.channel.enable is true or nixPath is not empty"
      (!servicesCfg.nix.channel.enable && !devCfg.nix.channel.enable);

  default-packages-empty =
    mkCheck "default-packages-empty" "environment.defaultPackages is empty (declarative-only)"
      "environment.defaultPackages is non-empty"
      (servicesCfg.environment.defaultPackages == [ ] && devCfg.environment.defaultPackages == [ ]);

  mutable-users-disabled =
    mkCheck "mutable-users-disabled" "users.mutableUsers is false on all hosts"
      "users.mutableUsers is true — runtime user modification possible"
      (!servicesCfg.users.mutableUsers && !devCfg.users.mutableUsers);

  nftables-enabled =
    mkCheck "nftables-enabled" "nftables backend enabled on all hosts"
      "networking.nftables.enable is false"
      (servicesCfg.networking.nftables.enable && devCfg.networking.nftables.enable);

  fail2ban-disabled =
    mkCheck "fail2ban-disabled" "fail2ban is disabled (key-only auth + MaxAuthTries is sufficient)"
      "services.fail2ban.enable is true"
      (!servicesCfg.services.fail2ban.enable && !devCfg.services.fail2ban.enable);

  impermanence-hide-mounts =
    let
      source = builtins.readFile ../../modules/impermanence.nix;
    in
    mkCheck "impermanence-hide-mounts" "impermanence hideMounts is true"
      "modules/impermanence.nix missing hideMounts = true"
      (lib.hasInfix "hideMounts = true" source);

  secrets-depend-on-persist =
    let
      source = builtins.readFile ../../modules/impermanence.nix;
    in
    mkCheck "secrets-depend-on-persist" "setupSecrets activation depends on persist-files"
      "modules/impermanence.nix missing setupSecrets.deps persist-files dependency"
      (lib.hasInfix "setupSecrets" source && lib.hasInfix "persist-files" source);

  no-linger-persistence =
    let
      source = builtins.readFile ../../modules/impermanence.nix;
    in
    mkCheck "no-linger-persistence" "impermanence no longer persists systemd linger state"
      "modules/impermanence.nix still persists /var/lib/systemd/linger"
      (!(lib.hasInfix "/var/lib/systemd/linger" source));

  coredumps-disabled =
    mkCheck "coredumps-disabled" "systemd coredumps are disabled on both host fixtures"
      "systemd.coredump.enable is still true"
      (!servicesCfg.systemd.coredump.enable && !devCfg.systemd.coredump.enable);

  core-pattern-disabled =
    mkCheck "core-pattern-disabled" "kernel.core_pattern drops coredumps on both host fixtures"
      "boot.kernel.sysctl.\"kernel.core_pattern\" is not forced to |/bin/false"
      (
        servicesCfg.boot.kernel.sysctl."kernel.core_pattern" == "|/bin/false"
        && devCfg.boot.kernel.sysctl."kernel.core_pattern" == "|/bin/false"
      );

  wrapper-nix-store-guard =
    let
      source = builtins.readFile ../../scripts/agent-wrapper.sh;
    in
    mkCheck "wrapper-nix-store-guard" "agent-wrapper.sh validates AGENT_REAL_BINARY is in /nix/store"
      "agent-wrapper.sh missing /nix/store guard for AGENT_REAL_BINARY"
      (lib.hasInfix "/nix/store" source && lib.hasInfix "AGENT_REAL_BINARY must be in /nix/store" source);

  wrapper-credential-proxy-flow =
    let
      source = builtins.readFile ../../scripts/agent-wrapper.sh;
    in
    mkCheck "wrapper-credential-proxy-flow"
      "agent-wrapper.sh loads secrets into env vars for nono's built-in credential proxy"
      "agent-wrapper.sh missing credential loading flow (AGENT_CREDENTIAL_SECRETS, /run/secrets)"
      (
        lib.hasInfix "AGENT_CREDENTIAL_SECRETS" source
        && lib.hasInfix "/run/secrets/" source
        && lib.hasInfix "env://" source
      );

  wrapper-supply-chain-hardening =
    let
      source = builtins.readFile ../../scripts/agent-wrapper.sh;
    in
    mkCheck "wrapper-supply-chain-hardening" "agent-wrapper.sh sets supply chain hardening env vars"
      "agent-wrapper.sh missing NPM_CONFIG_IGNORE_SCRIPTS or NPM_CONFIG_AUDIT"
      (
        lib.hasInfix "NPM_CONFIG_IGNORE_SCRIPTS=true" source
        && lib.hasInfix "NPM_CONFIG_AUDIT=true" source
        && lib.hasInfix "NPM_CONFIG_SAVE_EXACT=true" source
      );

  wrapper-telemetry-suppression =
    let
      source = builtins.readFile ../../scripts/agent-wrapper.sh;
    in
    mkCheck "wrapper-telemetry-suppression" "agent-wrapper.sh suppresses telemetry"
      "agent-wrapper.sh missing DISABLE_TELEMETRY or DISABLE_ERROR_REPORTING"
      (lib.hasInfix "DISABLE_TELEMETRY=1" source && lib.hasInfix "DISABLE_ERROR_REPORTING=1" source);

  claude-settings-mcp-disabled =
    let
      source = builtins.readFile ../../modules/agent-sandbox.nix;
    in
    mkCheck "claude-settings-mcp-disabled" "Claude managed settings disable MCP auto-loading"
      "agent-sandbox.nix missing enableAllProjectMcpServers = false"
      (lib.hasInfix "enableAllProjectMcpServers" source && lib.hasInfix "false" source);

  launcher-seccomp-filter =
    let
      source = builtins.readFile ../../modules/agent-launcher.nix;
    in
    mkCheck "launcher-seccomp-filter" "agent-launcher.nix launcher includes seccomp SystemCallFilter"
      "agent-launcher.nix missing SystemCallFilter for @mount/@debug/bpf"
      (
        lib.hasInfix "SystemCallFilter" source && lib.hasInfix "@mount" source && lib.hasInfix "bpf" source
      );

  launcher-extra-deny-plumbed =
    let
      source = builtins.readFile ../../modules/agent-launcher.nix;
    in
    mkCheck "launcher-extra-deny-plumbed"
      "agent-launcher.nix propagates per-agent nonoProfile.extraDeny into generated profiles"
      "agent-launcher.nix declares extraDeny but does not render filesystem.deny overrides"
      (
        lib.hasInfix "agentDef.nonoProfile.extraDeny != []" source
        && lib.hasInfix "deny = agentDef.nonoProfile.extraDeny;" source
      );

  no-systemd-initrd =
    mkCheck "no-systemd-initrd" "boot.initrd.systemd.enable is false on all hosts"
      "boot.initrd.systemd.enable is true — non-systemd initrd required for BTRFS rollback"
      (!servicesCfg.boot.initrd.systemd.enable && !devCfg.boot.initrd.systemd.enable);

  # --- Phase 152: Generic launcher architecture ---

  generic-launcher-enabled =
    mkCheck "generic-launcher-enabled" "dev host has generic agent launcher enabled"
      "dev host services.agentLauncher.enable is false — no agent wrappers generated"
      devCfg.services.agentLauncher.enable;

  launcher-extra-deny-propagates =
    let
      profile = builtins.fromJSON (
        builtins.readFile extraDenyCfg.environment.etc."nono/profiles/tsurf-review-check.json".source
      );
    in
    mkCheck "launcher-extra-deny-propagates"
      "agent-launcher propagates per-agent extraDeny rules into generated nono profiles"
      "agent-launcher dropped extraDeny when rendering the generated nono profile"
      (builtins.elem "/custom-deny" (profile.filesystem.deny or [ ]));

  no-dev-user =
    mkCheck "no-dev-user" "dev user no longer exists in config"
      "users.users.dev still defined — remove the dev user (root+agent model)"
      (!(builtins.hasAttr "dev" devCfg.users.users) || !(devCfg.users.users.dev.isNormalUser or false));

}

# --- Private overlay test extension pattern ---
#
# The private overlay (private-tsurf) extends these checks by importing
# this file and appending private-specific assertions.
