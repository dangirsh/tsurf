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
  openRouterCfg = self.nixosConfigurations."eval-dev-openrouter".config;
  devAgentUser = devCfg.tsurf.agent.user;
  altAgentUser = altAgentCfg.tsurf.agent.user;
  altAgentHome = altAgentCfg.tsurf.agent.home;
  roleEvalModule = {
    tsurf.template.allowUnsafePlaceholders = true;
  };
  agentHostRoleCfg =
    (lib.nixosSystem {
      system = pkgs.stdenv.hostPlatform.system;
      modules = [
        self.nixosModules.agent-host
        roleEvalModule
      ];
    }).config;
  agentHostWithSecretsRoleCfg =
    (lib.nixosSystem {
      system = pkgs.stdenv.hostPlatform.system;
      modules = [
        self.nixosModules.agent-host-with-secrets
        roleEvalModule
      ];
    }).config;
  serviceHostRoleCfg =
    (lib.nixosSystem {
      system = pkgs.stdenv.hostPlatform.system;
      modules = [
        self.nixosModules.service-host
        roleEvalModule
      ];
    }).config;
  serviceHostWithSecretsRoleCfg =
    (lib.nixosSystem {
      system = pkgs.stdenv.hostPlatform.system;
      modules = [
        self.nixosModules.service-host-with-secrets
        roleEvalModule
      ];
    }).config;
  harmoniaServerCfg =
    (lib.nixosSystem {
      system = pkgs.stdenv.hostPlatform.system;
      modules = [
        self.nixosModules.core
        self.nixosModules.harmonia-cache
        roleEvalModule
        {
          tsurf.harmoniaCache = {
            enable = true;
            enableServer = true;
            allowInsecureHttp = true;
            host = "cache.example.invalid";
            publicKey = "cache.example.invalid-1:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
            signingKeySopsFile = ../../README.md;
            allowedClientIPv4s = [ "203.0.113.10" ];
          };
        }
      ];
    }).config;
  harmoniaLocalServerCfg =
    (lib.nixosSystem {
      system = pkgs.stdenv.hostPlatform.system;
      modules = [
        self.nixosModules.core
        self.nixosModules.harmonia-cache
        roleEvalModule
        {
          tsurf.harmoniaCache = {
            enableServer = true;
            signingKeySopsFile = ../../README.md;
          };
        }
      ];
    }).config;
  harmoniaHttpsClientCfg =
    (lib.nixosSystem {
      system = pkgs.stdenv.hostPlatform.system;
      modules = [
        self.nixosModules.core
        self.nixosModules.harmonia-cache
        roleEvalModule
        {
          tsurf.harmoniaCache = {
            enable = true;
            host = "cache.example.invalid";
            publicKey = "cache.example.invalid-1:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
          };
        }
      ];
    }).config;
  headscaleEnabledCfg =
    (lib.nixosSystem {
      system = pkgs.stdenv.hostPlatform.system;
      modules = [
        self.nixosModules.service-host
        roleEvalModule
        {
          tsurf.headscale = {
            enable = true;
            domain = "hs.example.invalid";
            publicIPv4 = "203.0.113.20";
            acmeEmail = "admin@example.invalid";
            nameservers = [ "198.51.100.53" ];
          };
        }
      ];
    }).config;
  resticEnabledCfg =
    (lib.nixosSystem {
      system = pkgs.stdenv.hostPlatform.system;
      modules = [
        self.nixosModules.service-host
        roleEvalModule
        {
          sops.defaultSopsFile = ../../tests/fixtures/sops-placeholder.yaml;
          services.resticStarter = {
            enable = true;
            repository = "s3:s3.example.invalid/tsurf-backups";
          };
        }
      ];
    }).config;
  mkCheck =
    name: passMessage: failMessage: condition:
    if condition then
      pkgs.runCommand name { } ''
        echo "PASS: ${passMessage}"
        touch "$out"
      ''
    else
      builtins.throw "${name}: ${failMessage}";
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

  eval-dev-openrouter = pkgs.runCommand "eval-dev-openrouter" { } ''
    echo "eval-dev-openrouter config evaluates: ${
      self.nixosConfigurations."eval-dev-openrouter".config.system.build.toplevel
    }"
    touch "$out"
  '';

  ci-workflows-hardened =
    let
      testWorkflow = builtins.readFile ../../.github/workflows/test.yml;
      updateWorkflow = builtins.readFile ../../.github/workflows/update-flake-lock.yml;
    in
    mkCheck "ci-workflows-hardened"
      "CI avoids accept-flake-config, builds both VM proofs, and schedules lock updates"
      "GitHub workflows must not accept flake config on PRs and must keep VM proof plus lock-update coverage"
      (
        !(lib.hasInfix "accept-flake-config" testWorkflow)
        && lib.hasInfix ".#vm-test-credential-proxy" testWorkflow
        && lib.hasInfix ".#vm-test-sandbox" testWorkflow
        && lib.hasInfix "DeterminateSystems/update-flake-lock@834c491b2ece4de0bbd00d85214bb5e83b4da5c6" updateWorkflow
        && lib.hasInfix "schedule:" updateWorkflow
      );

  public-hosts-use-test-sops-fixture =
    let
      devHost = builtins.readFile ../../hosts/dev/default.nix;
      servicesHost = builtins.readFile ../../hosts/services/default.nix;
      fixture = builtins.readFile ../../tests/fixtures/sops-placeholder.yaml;
    in
    mkCheck "public-hosts-use-test-sops-fixture"
      "public host fixtures use a neutral test-only SOPS placeholder"
      "public host fixtures must not point at tracked secrets/*.yaml placeholders"
      (
        lib.hasInfix "tests/fixtures/sops-placeholder.yaml" devHost
        && lib.hasInfix "tests/fixtures/sops-placeholder.yaml" servicesHost
        && !(lib.hasInfix "tailscale-authkey" fixture)
      );

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

  systemd-default-sysctl-disabled =
    mkCheck "systemd-default-sysctl-disabled"
      "systemd 50-default sysctl file is disabled before hardened sysctls are applied"
      "systemd 50-default.conf can still lower kernel.yama.ptrace_scope before 60-nixos.conf"
      (
        servicesCfg.environment.etc."sysctl.d/50-default.conf".enable == false
        && devCfg.environment.etc."sysctl.d/50-default.conf".enable == false
        && toString servicesCfg.boot.kernel.sysctl."kernel.yama.ptrace_scope" == "3"
        && toString devCfg.boot.kernel.sysctl."kernel.yama.ptrace_scope" == "3"
      );

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

  ssh-host-key-persisted-path =
    let
      hostKeyPaths = map (k: k.path) servicesCfg.services.openssh.hostKeys;
      expected = [ "/persist/etc/ssh/ssh_host_ed25519_key" ];
    in
    mkCheck "ssh-host-key-persisted-path"
      "OpenSSH and sops-nix use the direct persisted SSH host key path"
      "SSH host key paths=${builtins.toJSON hostKeyPaths}; sops age paths must use /persist directly"
      (
        hostKeyPaths == expected
        && devCfg.sops.age.sshKeyPaths == expected
        && servicesCfg.sops.age.sshKeyPaths == expected
      );

  metadata-block =
    mkCheck "metadata-block" "agent-metadata-block nftables table is defined"
      "agent-metadata-block nftables table not found"
      (
        builtins.hasAttr "agent-metadata-block" servicesCfg.networking.nftables.tables
        && servicesCfg.networking.nftables.tables.agent-metadata-block.family == "inet"
      );

  agent-egress-table =
    mkCheck "agent-egress-table" "agent-egress nftables table is defined"
      "agent-egress nftables table not found"
      (builtins.hasAttr "agent-egress" servicesCfg.networking.nftables.tables);

  agent-egress-policy =
    let
      content = servicesCfg.networking.nftables.tables.agent-egress.content;
      agentUid = toString servicesCfg.tsurf.agent.uid;
    in
    mkCheck "agent-egress-policy"
      "agent-egress policy scopes by agent UID, allows only intended paths, and logs drops"
      "agent-egress policy missing UID scoping, private-range drops, HTTPS allowlist, nono proxy range, or logged drops"
      (
        lib.hasInfix "meta skuid ${agentUid}" content
        && lib.hasInfix "100.64.0.0/10" content
        && lib.hasInfix "443" content
        && lib.hasInfix "20000-20199" content
        && lib.hasInfix ''oifname "lo" counter log prefix "tsurf-agent-egress-loopback-drop " drop'' content
        && lib.hasInfix ''counter log prefix "tsurf-agent-egress-private-ipv4-drop " drop'' content
        && lib.hasInfix ''counter log prefix "tsurf-agent-egress-default-drop " drop'' content
        && !(lib.hasInfix ''oifname "lo" accept'' content)
        && lib.hasInfix "drop" content
      );

  agent-egress-iron-mediated-dev =
    let
      content = devCfg.networking.nftables.tables.agent-egress.content;
      agentUid = toString devCfg.tsurf.agent.uid;
    in
    mkCheck "agent-egress-iron-mediated-dev"
      "Iron-enabled dev host allows only loopback proxy ports for agent UID egress"
      "Iron-enabled dev host should not retain direct DNS or public 22/80/443 egress for the agent UID"
      (
        devCfg.services.agentEgressProxy.enable
        && devCfg.tsurf.agentEgress.mediatedOnly
        && lib.hasInfix "meta skuid ${agentUid}" content
        && lib.hasInfix "20208" content
        && lib.hasInfix "20243" content
        && lib.hasInfix "20280" content
        && !(lib.hasInfix "udp dport 53 accept" content)
        && !(lib.hasInfix "tcp dport @tsurf_agent_egress_tcp_ports accept" content)
        && lib.hasInfix ''counter log prefix "tsurf-agent-egress-default-drop " drop'' content
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

  repo-ownership-guards =
    let
      codeowners = builtins.readFile ../../.github/CODEOWNERS;
      flakeSource = builtins.readFile ../../flake.nix;
    in
    mkCheck "repo-ownership-guards" "CODEOWNERS and formatting/static-analysis checks are present"
      "repository owner review and nixfmt/deadnix gates must stay wired"
      (
        lib.hasInfix "* @dangirsh" codeowners
        && lib.hasInfix "nixfmt-check" flakeSource
        && lib.hasInfix "deadnix-check" flakeSource
      );

  public-nixos-modules-exported =
    let
      names = builtins.attrNames (self.nixosModules or { });
      expected = [
        "agent-host"
        "agent-host-with-secrets"
        "agent-compute"
        "agent-egress-proxy"
        "agent-launcher"
        "agent-sandbox"
        "base"
        "boot"
        "common"
        "core"
        "headscale"
        "harmonia-cache"
        "impermanence"
        "networking"
        "nono"
        "secrets"
        "service-host"
        "service-host-with-secrets"
        "users"
      ];
    in
    mkCheck "public-nixos-modules-exported" "public flake exports stable NixOS module and role names"
      "public flake missing expected nixosModules exports for private overlays"
      (builtins.all (name: builtins.elem name names) expected);

  public-role-secrets-explicit =
    mkCheck "public-role-secrets-explicit"
      "role modules keep secrets explicit through with-secrets variants"
      "agent-host/service-host should not import public secrets unless the with-secrets variant is used"
      (
        !(builtins.hasAttr "anthropic-api-key" agentHostRoleCfg.sops.secrets)
        && !(builtins.hasAttr "anthropic-api-key" serviceHostRoleCfg.sops.secrets)
        && builtins.hasAttr "anthropic-api-key" agentHostWithSecretsRoleCfg.sops.secrets
        && builtins.hasAttr "anthropic-api-key" serviceHostWithSecretsRoleCfg.sops.secrets
      );

  cass-default-disabled =
    let
      source = builtins.readFile ../../extras/cass.nix;
    in
    mkCheck "cass-default-disabled" "CASS indexer defaults to disabled when imported"
      "extras/cass.nix still has default = true — CASS must be opt-in"
      (!(lib.hasInfix "default = true" source));

  restic-opt-in =
    mkCheck "restic-opt-in" "restic backup and B2 secrets are inactive until the extra is enabled"
      "restic backup or B2/restic secrets are active in the public template"
      (
        !servicesCfg.services.resticStarter.enable
        && !(builtins.hasAttr "b2-account-id" serviceHostWithSecretsRoleCfg.sops.secrets)
        && !(builtins.hasAttr "b2-account-key" serviceHostWithSecretsRoleCfg.sops.secrets)
        && !(builtins.hasAttr "restic-password" serviceHostWithSecretsRoleCfg.sops.secrets)
      );

  restic-extra-owns-secrets =
    mkCheck "restic-extra-owns-secrets"
      "Restic extra declares its own B2/restic secrets and environment template"
      "Restic secrets/template must live with extras/restic.nix and appear only when resticStarter is enabled"
      (
        resticEnabledCfg.services.resticStarter.enable
        && builtins.hasAttr "b2-account-id" resticEnabledCfg.sops.secrets
        && builtins.hasAttr "b2-account-key" resticEnabledCfg.sops.secrets
        && builtins.hasAttr "restic-password" resticEnabledCfg.sops.secrets
        && builtins.hasAttr "restic-b2-env" resticEnabledCfg.sops.templates
        &&
          resticEnabledCfg.services.restic.backups.b2.passwordFile
          == resticEnabledCfg.sops.secrets."restic-password".path
        &&
          resticEnabledCfg.services.restic.backups.b2.environmentFile
          == resticEnabledCfg.sops.templates."restic-b2-env".path
      );

  headscale-opt-in =
    mkCheck "headscale-opt-in" "headscale not active in public services config (opt-in works)"
      "headscale active in public template — tsurf.headscale.enable should be false"
      (!(lib.attrByPath [ "tsurf" "headscale" "enable" ] false servicesCfg));

  headscale-required-settings =
    let
      source = builtins.readFile ../../modules/headscale.nix;
    in
    mkCheck "headscale-required-settings"
      "Headscale requires private-overlay domain, IP, ACME email, and nameserver settings"
      "Headscale must fail closed instead of shipping placeholder public defaults"
      (
        headscaleEnabledCfg.services.headscale.settings.server_url == "https://hs.example.invalid"
        && headscaleEnabledCfg.services.headscale.settings.derp.server.ipv4 == "203.0.113.20"
        && headscaleEnabledCfg.security.acme.defaults.email == "admin@example.invalid"
        && headscaleEnabledCfg.services.headscale.settings.dns.nameservers.global == [ "198.51.100.53" ]
        && builtins.hasAttr "hs.example.invalid" headscaleEnabledCfg.services.nginx.virtualHosts
        && lib.hasInfix "tsurf.headscale.domain must be set" source
        && lib.hasInfix "tsurf.headscale.publicIPv4 must be set" source
        && lib.hasInfix "tsurf.headscale.acmeEmail must be set" source
        && lib.hasInfix "tsurf.headscale.nameservers must be set" source
        && !(lib.hasInfix "default = \"hs.example.com\"" source)
        && !(lib.hasInfix "default = \"0.0.0.0\"" source)
        && !(lib.hasInfix "default = \"admin@example.com\"" source)
      );

  harmonia-cache-opt-in =
    mkCheck "harmonia-cache-opt-in" "harmonia cache is exported and disabled by default"
      "harmonia cache should be available as a public module but inactive in public fixtures"
      (
        builtins.hasAttr "harmonia-cache" (self.nixosModules or { })
        && !(lib.attrByPath [ "tsurf" "harmoniaCache" "enable" ] false servicesCfg)
        && !(lib.attrByPath [ "tsurf" "harmoniaCache" "enableServer" ] false servicesCfg)
      );

  harmonia-cache-https-default =
    let
      source = builtins.readFile ../../modules/harmonia-cache.nix;
    in
    mkCheck "harmonia-cache-https-default"
      "Harmonia clients default to HTTPS and HTTP requires an explicit opt-in"
      "Harmonia cache must not silently configure plaintext HTTP"
      (
        harmoniaHttpsClientCfg.tsurf.harmoniaCache.scheme == "https"
        && builtins.elem "https://cache.example.invalid:5000" harmoniaHttpsClientCfg.nix.settings.extra-substituters
        && !(builtins.elem "http://cache.example.invalid:5000" harmoniaHttpsClientCfg.nix.settings.extra-substituters)
        && lib.hasInfix "allowInsecureHttp" source
        && lib.hasInfix "must be true to use an http://" source
        && lib.hasInfix "must be true before exposing the Harmonia HTTP server directly" source
      );

  harmonia-cache-server-wiring =
    mkCheck "harmonia-cache-server-wiring"
      "harmonia server mode wires readable signing key and firewall exposure"
      "harmonia server mode must let the harmonia service read its signing key and must open the cache port coherently"
      (
        harmoniaServerCfg.services.harmonia.cache.enable
        &&
          harmoniaServerCfg.services.harmonia.cache.signKeyPaths == [
            harmoniaServerCfg.sops.secrets."harmonia-signing-key".path
          ]
        && harmoniaServerCfg.sops.secrets."harmonia-signing-key".owner == "harmonia"
        && harmoniaServerCfg.sops.secrets."harmonia-signing-key".group == "harmonia"
        && harmoniaServerCfg.sops.secrets."harmonia-signing-key".mode == "0400"
        && builtins.hasAttr "harmonia" harmoniaServerCfg.users.users
        && harmoniaServerCfg.users.users.harmonia.isSystemUser
        && harmoniaServerCfg.users.users.harmonia.group == "harmonia"
        && builtins.hasAttr "harmonia" harmoniaServerCfg.users.groups
        && harmoniaServerCfg.services.harmonia.cache.settings.bind == "0.0.0.0:5000"
        && builtins.elem harmoniaServerCfg.tsurf.harmoniaCache.port harmoniaServerCfg.networking.firewall.allowedTCPPorts
        && builtins.hasAttr "harmonia-cache-ingress" harmoniaServerCfg.networking.nftables.tables
        && lib.hasInfix "203.0.113.10" harmoniaServerCfg.networking.nftables.tables.harmonia-cache-ingress.content
      );

  harmonia-cache-loopback-default =
    mkCheck "harmonia-cache-loopback-default"
      "harmonia server without explicit clients stays loopback-only"
      "harmonia server should not bind publicly or open the firewall without allowedClientIPv4s"
      (
        harmoniaLocalServerCfg.services.harmonia.cache.settings.bind == "127.0.0.1:5000"
        && !(builtins.elem 5000 harmoniaLocalServerCfg.networking.firewall.allowedTCPPorts)
        && !(builtins.hasAttr "harmonia-cache-ingress" harmoniaLocalServerCfg.networking.nftables.tables)
      );

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
    mkCheck "headscale-dns-nameservers" "headscale sets dns.nameservers.global"
      "modules/headscale.nix missing dns.nameservers.global — headscale 0.26+ requires explicit nameservers"
      (headscaleEnabledCfg.services.headscale.settings.dns.nameservers.global == [ "198.51.100.53" ]);

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

  headscale-default-deny =
    let
      source = builtins.readFile ../../modules/headscale.nix;
    in
    mkCheck "headscale-default-deny" "headscale default ACL fails closed"
      "modules/headscale.nix still ships an allow-all default ACL"
      (
        lib.hasInfix "aclPolicy" source
        && lib.hasInfix "acls = [ ]" source
        && !(lib.hasInfix "dst = [ \"*:*\" ]" source)
      );

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

  nono-package-has-checks =
    let
      source = builtins.readFile ../../packages/nono.nix;
    in
    mkCheck "nono-package-has-checks"
      "nono source build has bounded patch-behavior checks and an install smoke check"
      "packages/nono.nix must keep targeted env:// tests and a post-install CLI smoke check"
      (
        lib.hasInfix "test_validate_custom_credential_env_uri_accepted" source
        && lib.hasInfix "linux_runtime_state" source
        && lib.hasInfix "grep -E" source
        && lib.hasInfix "doInstallCheck = true" source
        && lib.hasInfix "--help" source
      );

  nono-package-has-tsurf-patches =
    let
      source = builtins.readFile ../../packages/nono.nix;
      runPatch = builtins.readFile ../../packages/nono-no-run.patch;
    in
    mkCheck "nono-package-has-tsurf-patches"
      "nono source build carries the tsurf /run policy patch and relies on upstream env:// support"
      "packages/nono.nix must keep upstream env:// test coverage and remove upstream /run read grants"
      (
        !(lib.hasInfix "./nono-env-uri.patch" source)
        && lib.hasInfix "./nono-no-run.patch" source
        && lib.hasInfix "test_validate_custom_credential_env_uri_accepted" source
        && lib.hasInfix ''-          "/run",'' runPatch
        && lib.hasInfix ''-          "/var/run"'' runPatch
      );

  proxy-credential-profile =
    let
      profile = builtins.fromJSON devCfg.environment.etc."nono/profiles/tsurf.json".text;
    in
    mkCheck "proxy-credential-profile"
      "base nono profile has no credential wiring (credentials live in per-agent profiles)"
      "base tsurf.json nono profile should not contain network.custom_credentials — those belong in per-agent profiles"
      (
        !(builtins.hasAttr "custom_credentials" (profile.network or { }))
        && !(builtins.hasAttr "credentials" (profile.network or { }))
      );

  nono-profile-blocks-direct-network =
    let
      baseProfile = builtins.fromJSON devCfg.environment.etc."nono/profiles/tsurf.json".text;
      claudeProfile = builtins.fromJSON devCfg.environment.etc."nono/profiles/tsurf-claude.json".text;
    in
    mkCheck "nono-profile-blocks-direct-network"
      "base nono profile blocks network; Iron-backed generated profiles delegate network mediation to nftables/Iron"
      "nono base profile must block network, and Iron-backed profiles must disable nono network blocking for loopback proxy access"
      (
        (baseProfile.network.block or false)
        && !(claudeProfile.network.block or true)
        && !devCfg.services.nonoSandbox.allowDirectNetwork
      );

  claude-profile-iron-proxy =
    let
      profile = builtins.fromJSON devCfg.environment.etc."nono/profiles/tsurf-claude.json".text;
      creds = profile.network.credentials or [ ];
      customCreds = profile.network.custom_credentials or { };
    in
    mkCheck "claude-profile-iron-proxy"
      "generated Claude profile uses nono for sandboxing and Iron for proxy credentials"
      "tsurf-claude should not wire nono credentials when Iron is the default credential proxy"
      (
        devCfg.services.agentEgressProxy.enable
        && devCfg.services.agentLauncher.defaultCredentialProxy == "iron"
        && devCfg.services.agentLauncher.egressProxy.url == "http://127.0.0.1:20208"
        && devCfg.services.agentLauncher.egressProxy.caCert == "/var/lib/tsurf-agent-egress-proxy/ca.crt"
        && creds == [ ]
        && customCreds == { }
        && devCfg.services.agentLauncher.agents.claude.credentialServices == [ "anthropic" ]
        && builtins.hasAttr "tsurf-agent-egress-proxy" devCfg.systemd.services
        && builtins.hasAttr "iron-agent-egress-env" devCfg.sops.templates
      );

  agent-launcher-child-environment =
    let
      source = builtins.readFile ../../modules/agent-launcher.nix;
      wrapper = builtins.readFile ../../scripts/agent-wrapper.sh;
    in
    mkCheck "agent-launcher-child-environment"
      "agent-launcher supports non-secret child environment injection"
      "agent-launcher is missing childEnvironment support for isolated agent state dirs"
      (
        lib.hasInfix "childEnvironment" source
        && lib.hasInfix "AGENT_CHILD_ENVIRONMENT_FILE" source
        && lib.hasInfix "AGENT_CHILD_ENVIRONMENT_FILE" wrapper
        && lib.hasInfix "/nix/store/*" wrapper
      );

  codex-openrouter-extra =
    let
      profile =
        builtins.fromJSON
          openRouterCfg.environment.etc."nono/profiles/tsurf-codex-openrouter.json".text;
      agent = openRouterCfg.services.agentLauncher.agents."codex-openrouter";
      creds = profile.network.credentials or [ ];
      customCreds = profile.network.custom_credentials or { };
      codexHome = "${openRouterCfg.tsurf.agent.home}/.codex-openrouter";
      codexOpenRouterSource = builtins.readFile ../../extras/codex-openrouter.nix;
    in
    mkCheck "codex-openrouter-extra"
      "OpenRouter Codex extra exposes codex-openrouter with GLM 5.2 through the configured credential proxy"
      "OpenRouter Codex extra missing wrapper, GLM 5.2 default, or credential proxy wiring"
      (
        openRouterCfg.services.codexOpenRouterAgent.enable
        && openRouterCfg.services.codexOpenRouterAgent.wrapperName == "codex-openrouter"
        && openRouterCfg.services.codexOpenRouterAgent.model == "z-ai/glm-5.2"
        && agent.command == "codex-openrouter-child"
        && agent.credentialServices == [ "openrouter" ]
        && agent.credentialOverrides.openrouter.upstream == "https://openrouter.ai/api/v1"
        && agent.credentialOverrides.openrouter.secretName == "openrouter-api-key"
        && agent.childEnvironment.CODEX_HOME == codexHome
        && builtins.elem "codex-openrouter" (
          map (pkg: pkg.meta.mainProgram or pkg.pname or pkg.name) openRouterCfg.environment.systemPackages
        )
        && creds == [ ]
        && customCreds == { }
        && openRouterCfg.services.agentLauncher.defaultCredentialProxy == "iron"
        && lib.hasInfix "OPENROUTER_API_KEY" codexOpenRouterSource
        && lib.hasInfix "NONO_PROXY_TOKEN" codexOpenRouterSource
        && openRouterCfg.sops.secrets."openrouter-api-key".owner == "root"
        && builtins.elem codexHome (profile.filesystem.allow or [ ])
        && !(builtins.elem "${openRouterCfg.tsurf.agent.home}/.codex" (profile.filesystem.allow or [ ]))
        && builtins.elem "d ${codexHome} 0700 ${openRouterCfg.tsurf.agent.user} ${openRouterCfg.tsurf.agent.user} -" openRouterCfg.systemd.tmpfiles.rules
      );

  nono-profile-denies-run-secrets =
    mkCheck "nono-profile-denies-run-secrets" "generated nono profile explicitly denies /run/secrets"
      "nono profile deny list is missing /run/secrets"
      (
        let
          baseProfile = builtins.fromJSON devCfg.environment.etc."nono/profiles/tsurf.json".text;
          claudeProfile = builtins.fromJSON devCfg.environment.etc."nono/profiles/tsurf-claude.json".text;
        in
        builtins.elem "/run/secrets" baseProfile.filesystem.deny
        && builtins.elem "/run/secrets" claudeProfile.filesystem.deny
      );

  nono-base-profile-generic =
    let
      profile = builtins.fromJSON devCfg.environment.etc."nono/profiles/tsurf.json".text;
      allow = profile.filesystem.allow or [ ];
      allowFile = profile.filesystem.allow_file or [ ];
      deny = profile.filesystem.deny or [ ];
      groups = profile.groups.include or [ ];
      home = devCfg.tsurf.agent.home;
    in
    mkCheck "nono-base-profile-generic" "base tsurf nono profile is generic and not Claude-shaped"
      "modules/nono.nix still bakes Claude-specific paths, groups, or extends into the base profile"
      (
        !(builtins.hasAttr "extends" profile)
        && !(builtins.hasAttr "groups" (profile.security or { }))
        && !(builtins.elem "${home}/.claude" allow)
        && !(builtins.elem "${home}/.config/claude" allow)
        && !(builtins.elem "${home}/.claude.json" allowFile)
        && !(builtins.elem "${home}/.claude.json.lock" allowFile)
        && builtins.elem "${home}/.claude" deny
        && builtins.elem "${home}/.config/claude" deny
        && builtins.elem "${home}/.claude.json" deny
        && builtins.elem "${home}/.claude.json.lock" deny
        && builtins.elem "${home}/.codex" deny
        && builtins.elem "${home}/.agents" deny
        && !(builtins.elem "claude_code_linux" groups)
        && !(builtins.elem "claude_cache_linux" groups)
      );

  claude-profile-denies-raw-agent-auth-state =
    let
      profile = builtins.fromJSON devCfg.environment.etc."nono/profiles/tsurf-claude.json".text;
      allow = profile.filesystem.allow or [ ];
      allowFile = profile.filesystem.allow_file or [ ];
      deny = profile.filesystem.deny or [ ];
      home = devCfg.tsurf.agent.home;
    in
    mkCheck "claude-profile-denies-raw-agent-auth-state"
      "Claude wrapper uses brokered API credentials without exposing raw Claude auth state"
      "generated tsurf-claude nono profile still allows raw Claude auth/session state"
      (
        !(builtins.hasAttr "extends" profile)
        && builtins.elem "/etc/ssl" allow
        && builtins.elem "/run/secrets" profile.filesystem.deny
        && !(builtins.elem "${home}/.claude" allow)
        && !(builtins.elem "${home}/.config/claude" allow)
        && !(builtins.elem "${home}/.claude.json" allowFile)
        && !(builtins.elem "${home}/.claude.json.lock" allowFile)
        && builtins.elem "${home}/.claude" deny
        && builtins.elem "${home}/.config/claude" deny
        && builtins.elem "${home}/.claude.json" deny
        && builtins.elem "${home}/.claude.json.lock" deny
      );

  agent-launcher-extra-deny-wired =
    let
      source = builtins.readFile ../../modules/agent-launcher.nix;
    in
    mkCheck "agent-launcher-extra-deny-wired"
      "agent-launcher wires per-agent extraDeny entries into generated nono profiles"
      "modules/agent-launcher.nix defines extraDeny but does not merge it into filesystem.deny"
      (
        lib.hasInfix "agentDef.nonoProfile.extraDeny" source
        && lib.hasInfix "baseFilesystem.deny" source
        && lib.hasInfix "lib.unique" source
      );

  deploy-no-repo-source =
    let
      deploySrc = builtins.readFile ../../scripts/deploy.sh;
    in
    mkCheck "deploy-no-repo-source" "deploy.sh has no repo-controlled source calls"
      "deploy.sh sources repo-controlled scripts — remove source calls for deploy-post.sh or similar"
      (!(lib.hasInfix "source \"$FLAKE_DIR" deploySrc));

  deploy-magic-rollback-default =
    let
      deploySrc = builtins.readFile ../../scripts/deploy.sh;
    in
    mkCheck "deploy-magic-rollback-default" "deploy.sh enables deploy-rs magic rollback by default"
      "deploy.sh defaulted MAGIC_ROLLBACK away from true"
      (lib.hasInfix "MAGIC_ROLLBACK=true" deploySrc && lib.hasInfix "--confirm-timeout 300" deploySrc);

  deploy-remote-detached-mode =
    let
      deploySrc = builtins.readFile ../../scripts/deploy.sh;
      detachedSrc = builtins.readFile ../../scripts/deploy-detached.sh;
    in
    mkCheck "deploy-remote-detached-mode" "deploy.sh delegates detached remote activation mode"
      "deploy.sh or deploy-detached.sh is missing remote-detached mode for hosts with unreliable long SSH sessions"
      (
        lib.hasInfix "remote-detached" deploySrc
        && lib.hasInfix "deploy-detached.sh" deploySrc
        && lib.hasInfix "systemd-run --unit=" detachedSrc
        && lib.hasInfix "deploy-rs-activate" detachedSrc
        && lib.hasInfix "rollback_old_system" detachedSrc
      );

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

  agent-user-no-subids =
    let
      agentUser = builtins.getAttr devAgentUser devCfg.users.users;
    in
    mkCheck "agent-user-no-subids" "agent user has no subordinate UID/GID ranges"
      "SECURITY: agent user should not receive user-namespace subuid/subgid ranges by default"
      ((agentUser.subUidRanges or [ ]) == [ ] && (agentUser.subGidRanges or [ ]) == [ ]);

  root-docker-state-not-persisted =
    let
      persistedDirs = map (d: d.directory) devCfg.environment.persistence."/persist".directories;
    in
    mkCheck "root-docker-state-not-persisted" "root Docker client state is not persisted by default"
      "SECURITY: /root/.docker should not be persisted in the public base"
      (!(builtins.elem "/root/.docker" persistedDirs));

  agent-uid-explicit =
    mkCheck "agent-uid-explicit" "agent user has explicit UID defined"
      "agent user uid is not set (required for stable sandbox policy references)"
      (devCfg.users.users.${devCfg.tsurf.agent.user}.uid != null);

  impermanence-agent-home =
    let
      source = builtins.readFile ../../modules/agent-sandbox.nix;
      expectedSuffixes = [
        ".config/git"
        ".local/share/direnv"
        ".gitconfig"
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
      "agent-launcher.nix missing custom_credentials, env://, or env_var wiring — credential proxy not configured"
      (
        lib.hasInfix "custom_credentials" source
        && lib.hasInfix "env://" source
        && lib.hasInfix "env_var" source
        && lib.hasInfix "credentialServices" source
        && !lib.hasInfix "credential-proxy.py" source
      );

  launcher-extra-deny =
    let
      source = builtins.readFile ../../modules/agent-launcher.nix;
    in
    mkCheck "launcher-extra-deny" "agent-launcher.nix merges per-agent nonoProfile.extraDeny rules"
      "agent-launcher.nix defines extraDeny but does not write deny rules into generated profiles"
      (
        lib.hasInfix "agentDef.nonoProfile.extraDeny" source
        && lib.hasInfix "baseFilesystem.deny" source
        && lib.hasInfix "lib.unique" source
      );

  # --- Phase 120: agent API key ownership (SEC-04) ---

  agent-api-key-ownership-dev =
    mkCheck "agent-api-key-ownership-dev" "brokered provider API keys are owned by root on dev host"
      "SECURITY: a brokered provider API key is not owned by root — agent principal can read raw provider keys"
      (
        devCfg.sops.secrets."anthropic-api-key".owner == "root"
        && devCfg.sops.secrets."openai-api-key".owner == "root"
        && devCfg.sops.secrets."xai-api-key".owner == "root"
        && devCfg.sops.secrets."openrouter-api-key".owner == "root"
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

  home-profile-current-options =
    let
      source = builtins.readFile ../../extras/home/default.nix;
    in
    mkCheck "home-profile-current-options"
      "extras/home/default.nix uses current Home Manager git/ssh options"
      "extras/home/default.nix uses unsupported Home Manager git/ssh options"
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
      deploySource = builtins.readFile ../../scripts/deploy.sh;
      detachedSource = builtins.readFile ../../scripts/deploy-detached.sh;
    in
    mkCheck "agent-scripts-avoid-global-tmp" "deploy helper avoids /tmp for transient state"
      "deploy helper still writes transient files under /tmp"
      (
        !(lib.hasInfix " /tmp/" deploySource)
        && !(lib.hasInfix "=/tmp/" deploySource)
        && !(lib.hasInfix "\"/tmp/" deploySource)
        && !(lib.hasInfix " /tmp/" detachedSource)
        && !(lib.hasInfix "=/tmp/" detachedSource)
        && !(lib.hasInfix "\"/tmp/" detachedSource)
      );

  tsurf-init-passphrase-default =
    let
      source = builtins.readFile ../../scripts/tsurf-init.sh;
    in
    mkCheck "tsurf-init-passphrase-default"
      "tsurf-init refuses silent unencrypted key generation unless explicitly requested"
      "tsurf-init must prompt or require an explicit passphrase mode when generating root keys"
      (
        lib.hasInfix "--passphrase-file" source
        && lib.hasInfix "--no-passphrase" source
        && lib.hasInfix "Refusing to generate an unencrypted root SSH key noninteractively" source
        && lib.hasInfix "Passphrase file is empty" source
        && lib.hasInfix "Choose either --passphrase-file or --no-passphrase" source
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
      cassSource = builtins.readFile ../../extras/cass.nix;
    in
    mkCheck "systemd-hardening-baseline"
      "Project background services have SystemCallArchitectures=native"
      "SECURITY: CASS service missing SystemCallArchitectures=native"
      (lib.hasInfix "SystemCallArchitectures = \"native\"" cassSource);

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

  wrapper-sets-agent-env-for-nono =
    let
      source = builtins.readFile ../../scripts/agent-wrapper.sh;
    in
    mkCheck "wrapper-sets-agent-env-for-nono" "agent-wrapper.sh exports agent HOME before invoking nono"
      "agent-wrapper.sh leaves HOME unset for nono profile validation"
      (
        lib.hasInfix ''export HOME="$AGENT_RUN_AS_HOME"'' source
        && lib.hasInfix ''export USER="$AGENT_RUN_AS_USER"'' source
        && lib.hasInfix ''export LOGNAME="$AGENT_RUN_AS_USER"'' source
      );

  wrapper-no-credential-drop-before-nono =
    let
      source = builtins.readFile ../../scripts/agent-wrapper.sh;
    in
    mkCheck "wrapper-no-credential-drop-before-nono"
      "agent-wrapper.sh drops to the agent UID before nono when no root-brokered credentials are needed"
      "agent-wrapper.sh applies nono before setpriv even for no-credential subscription-auth agents"
      (
        lib.hasInfix "cred_pairs[@]" source
        && lib.hasInfix "== 0" source
        && lib.hasInfix "nono_args[@]" source
        && lib.hasInfix ''--reuid "$AGENT_RUN_AS_UID"'' source
      );

  wrapper-credential-proxy-flow =
    let
      source = builtins.readFile ../../scripts/agent-wrapper.sh;
    in
    mkCheck "wrapper-credential-proxy-flow"
      "agent-wrapper.sh loads secrets for nono but forwards only phantom proxy env to children"
      "agent-wrapper.sh credential flow must not re-export raw credential env vars to the child"
      (
        lib.hasInfix "AGENT_CREDENTIAL_SECRETS" source
        && lib.hasInfix "/run/secrets/" source
        && lib.hasInfix "env://" source
        && lib.hasInfix "env_var%_API_KEY" source
        && !(lib.hasInfix ''credential_env_names+=("$env_var")'' source)
      );

  wrapper-supply-chain-hardening =
    let
      source = builtins.readFile ../../scripts/agent-wrapper.sh;
    in
    mkCheck "wrapper-supply-chain-hardening" "agent-wrapper.sh sets supply chain hardening env vars"
      "agent-wrapper.sh missing npm/pnpm supply-chain hardening env vars"
      (
        lib.hasInfix "NPM_CONFIG_IGNORE_SCRIPTS=true" source
        && lib.hasInfix "NPM_CONFIG_AUDIT=true" source
        && lib.hasInfix "NPM_CONFIG_SAVE_EXACT=true" source
        && lib.hasInfix "NPM_CONFIG_MIN_RELEASE_AGE" source
        && lib.hasInfix "PNPM_CONFIG_MINIMUM_RELEASE_AGE" source
      );

  deploy-skip-checks-explicit =
    let
      source = builtins.readFile ../../scripts/deploy.sh;
    in
    mkCheck "deploy-skip-checks-explicit"
      "deploy.sh only passes --skip-checks when explicitly requested"
      "deploy.sh must default to deploy-rs checks and require the explicit --skip-checks flag for the unsafe path"
      (
        lib.hasInfix "SKIP_CHECKS=false" source
        && lib.hasInfix "--skip-checks)" source
        && lib.hasInfix ''if [[ "$SKIP_CHECKS" == true ]]'' source
        && !(lib.hasInfix ''
          "$FLAKE_DIR#$NODE"
            --skip-checks'' source)
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
    mkCheck "claude-settings-mcp-disabled"
      "Claude managed settings disable MCP auto-loading and deny CI/settings edits"
      "agent-sandbox.nix missing enableAllProjectMcpServers = false or CI/settings deny rules"
      (
        lib.hasInfix "enableAllProjectMcpServers" source
        && lib.hasInfix "false" source
        && lib.hasInfix "Edit(.github/workflows/**)" source
        && lib.hasInfix "Edit(.claude/**)" source
      );

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
        lib.hasInfix "agentDef.nonoProfile.extraDeny" source
        && lib.hasInfix "baseFilesystem.deny" source
        && lib.hasInfix "lib.unique" source
      );

  systemd-initrd-rollback =
    mkCheck "systemd-initrd-rollback" "BTRFS rollback runs as a systemd initrd service"
      "missing tsurf-btrfs-rollback systemd initrd service"
      (
        servicesCfg.boot.initrd.systemd.enable
        && devCfg.boot.initrd.systemd.enable
        && builtins.hasAttr "tsurf-btrfs-rollback" servicesCfg.boot.initrd.systemd.services
        && builtins.hasAttr "tsurf-btrfs-rollback" devCfg.boot.initrd.systemd.services
        && builtins.elem "sysroot.mount" servicesCfg.boot.initrd.systemd.services.tsurf-btrfs-rollback.before
        && builtins.elem "sysroot.mount" devCfg.boot.initrd.systemd.services.tsurf-btrfs-rollback.before
      );

  # --- Phase 152: Generic launcher architecture ---

  generic-launcher-enabled =
    mkCheck "generic-launcher-enabled" "dev host has generic agent launcher enabled"
      "dev host services.agentLauncher.enable is false — no agent wrappers generated"
      devCfg.services.agentLauncher.enable;

  launcher-scope-default-read =
    mkCheck "launcher-scope-default-read"
      "agent launcher defaults to read-only top-level workspace scope"
      "services.agentLauncher.scopeAccess default changed — public base must stay conservative"
      (devCfg.services.agentLauncher.scopeAccess == "read");

  launcher-private-hooks =
    let
      source = builtins.readFile ../../modules/agent-launcher.nix;
      wrapperSource = builtins.readFile ../../scripts/agent-wrapper.sh;
    in
    mkCheck "launcher-private-hooks"
      "agent launcher exposes explicit private-overlay hooks without changing public defaults"
      "agent launcher missing scope/sudo/extra path hooks needed to avoid private forks"
      (
        lib.hasInfix "sudoGroups" source
        && lib.hasInfix "scopeAccess" source
        && lib.hasInfix "extraReadPaths" source
        && lib.hasInfix "AGENT_SCOPE_ACCESS" wrapperSource
        && lib.hasInfix "AGENT_EXTRA_READ_PATHS_FILE" wrapperSource
        && lib.hasInfix "AGENT_NONO_PROXY_PORT_START" wrapperSource
      );

  launcher-can-drop-agent-uid =
    let
      source = builtins.readFile ../../modules/agent-launcher.nix;
    in
    mkCheck "launcher-can-drop-agent-uid"
      "agent launcher keeps only CAP_SETUID/CAP_SETGID so wrappers can drop to the agent UID"
      "agent launcher strips the capabilities needed for setpriv to drop to the agent UID"
      (lib.hasInfix ''"--property=CapabilityBoundingSet=CAP_SETUID CAP_SETGID"'' source);

  launcher-persistence-dedupes =
    let
      source = builtins.readFile ../../modules/agent-launcher.nix;
    in
    mkCheck "launcher-persistence-dedupes"
      "agent launcher deduplicates shared persistence paths across wrappers"
      "agent launcher can emit duplicate environment.persistence paths when two wrappers share auth state"
      (
        lib.hasInfix ''environment.persistence."/persist".directories = lib.unique'' source
        && lib.hasInfix ''environment.persistence."/persist".files = lib.unique'' source
      );

  launcher-extra-deny-propagates =
    let
      profile =
        builtins.fromJSON
          extraDenyCfg.environment.etc."nono/profiles/tsurf-review-check.json".text;
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
