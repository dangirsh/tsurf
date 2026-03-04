# modules/openclaw.nix
# OpenClaw - self-hosted AI assistant with messaging integrations.
# Six isolated instances: mark, lou, alexia, ari, jordan-claw, tal-claw.
#
# @decision OCL-01: Define instances in a parametric attrset (lib.mapAttrs').
# @rationale: The instance fleet is fixed but repetitive. A single map keeps ports,
#   secrets, users, services, and seeded config in sync.
#
# @decision OCL-02: Use npm tarball package built by ../packages/openclaw.nix.
# @rationale: Published tarball includes dist/ and keeps packaging independent of
#   upstream pnpm workspace layout.
#
# @decision OCL-03: Native systemd services pass per-instance --port directly.
# @rationale: Docker host:container port translation is removed; each service
#   listens on its own real host port (18789-18794).
#
# @decision OCL-05: Seed openclaw.json from activation if absent/invalid only.
# @rationale: Preserve user edits while replacing known-invalid legacy keys.
#
# @decision OCL-06: Migrate state ownership from UID/GID 1000 to per-instance users.
# @rationale: Existing Docker-hosted state was owned by container UID 1000.
#   Native services must own persistent state under dedicated principals.
#
# @decision OCL-11: trustedProxies include loopback only.
# @rationale: Docker bridge proxies are removed; nginx local proxy traffic is
#   trusted via 127.0.0.1 only.
#
# @decision OCL-12: One system user per instance.
# @rationale: Limits blast radius between instances and allows per-template file
#   ownership with mode 0400.
#
# @decision OCL-13: HOME points at instance state directory.
# @rationale: OpenClaw resolves data root via HOME when OPENCLAW_HOME is unset.
#
# @decision OCL-14: Keep Docker-era state layout via .openclaw -> . symlink.
# @rationale: Existing data is flat in /var/lib/openclaw-<name>/; symlink avoids
#   data moves while satisfying native HOME/.openclaw resolution.
#
# @decision OCL-15: bind = "loopback" for native systemd (was "lan" for Docker).
# @rationale: Docker port mapping required lan binding inside the container. Native
#   services run directly on the host; loopback binding ensures each process is only
#   reachable via nginx on localhost — not directly from Tailscale or the internet.
#
# @decision OCL-16: MemoryDenyWriteExecute = false (explicit).
# @rationale: Node.js V8 JIT compilation requires writable+executable memory pages.
#   Setting true crashes the process immediately. Explicit false signals intentional override.
#
# @decision OCL-19: alexia=18800, ari=18810 (not 18791/18792).
# @rationale: openclaw spawns a child gateway process that binds port N (gateway), N+2 (browser-control),
#   N+3 (internal) — even with bind=loopback. Ports 18791 and 18792 are mark's (18789) auxiliary ports;
#   when alexia/ari try to start on those ports, openclaw detects "another gateway instance already listening"
#   and exits. Moved to 18800/18810 which have clean auxiliary ranges (18802/18803 and 18812/18813).
#
# @decision OCL-18: NODE_OPTIONS heap 4GB, MemoryHigh 6GB, MemoryMax 8GB, CPUQuota 150%.
# @rationale: Resource limits set to 50% of neurosys total ÷ 6 instances (18 vCPU, 96 GB RAM).
#   Each instance: 1.5 vCPU (9 vCPU fleet total) and 8 GB RAM (48 GB fleet total).
#   V8 heap capped at 4 GB (50% of MemoryMax), leaving 4 GB for native heap/threads.
#
# @decision OCL-17: No SystemCallFilter; AF_NETLINK required in RestrictAddressFamilies.
# @rationale: Node.js + native sqlite3 addons use an unpredictable syscall surface.
#   Other hardening (PrivateTmp, ProtectSystem, RestrictAddressFamilies, CapabilityBoundingSet)
#   provides isolation without risking a missed syscall causing silent failures.
#   AF_NETLINK is required because Node.js os.networkInterfaces() calls uv_interface_addresses
#   which uses Netlink sockets to enumerate network interfaces — even with bind=loopback.
#
# @decision OCL-20: allowedOrigins replaces dangerouslyAllowHostHeaderOriginFallback.
# @rationale: Security audit (2026-03-02) flagged Host-header origin fallback as a DNS rebinding
#   weakness. Each instance has a fixed public HTTPS domain; use it as the explicit allowedOrigin.
#   Existing configs are patched in-place via jq to preserve user channel config (Discord, etc.).
#
# @decision OCL-21: StateDirectoryMode 0700, openclaw.json 0600, credentials/ 0700.
# @rationale: Security audit flagged 750/640/755 modes. State dir and config contain session keys
#   and channel tokens; restrict to owner-only.
#
# @decision OCL-22: Set SHELL=/bin/sh and PATH=/run/current-system/sw/bin for agent exec.
# @rationale: Service users have nologin as login shell (/etc/passwd) and systemd's default PATH
#   only includes coreutils/findutils/grep/sed. OpenClaw's resolveShell() falls back to /bin/sh
#   when SHELL is nologin, but agent-spawned commands need access to bash, node, git, curl, npm
#   etc. Adding the system sw/bin to PATH makes these discoverable without relaxing any other
#   hardening (ProtectSystem=strict, NoNewPrivileges, CapabilityBoundingSet="" all remain).
{ config, lib, pkgs, ... }:

let
  openclawPkg = pkgs.callPackage ../packages/openclaw.nix { };

  instances = {
    mark = {
      port = 18789;
      gatewaySecret = "openclaw-mark-gateway-token";
      defaultModel = "claude-sonnet-4-6";
    };
    lou = {
      port = 18790;
      gatewaySecret = "openclaw-lou-gateway-token";
      defaultModel = "claude-sonnet-4-6";
    };
    alexia = {
      port = 18800;  # OCL-19: 18791 conflicts with mark's auxiliary ports (gateway +2); moved to 18800
      gatewaySecret = "openclaw-alexia-gateway-token";
      defaultModel = "claude-sonnet-4-6";
    };
    ari = {
      port = 18810;  # OCL-19: 18792 conflicts with mark's auxiliary ports (gateway +3); moved to 18810
      gatewaySecret = "openclaw-ari-gateway-token";
      defaultModel = "claude-sonnet-4-6";
    };
    "jordan-claw" = {
      port = 18793;
      gatewaySecret = "openclaw-jordan-claw-gateway-token";
      defaultModel = "claude-sonnet-4-6";
    };
    "tal-claw" = {
      port = 18794;
      gatewaySecret = "openclaw-tal-claw-gateway-token";
      defaultModel = "claude-sonnet-4-6";
    };
  };

  mkOpenclawConfig = name: builtins.toJSON {
    gateway = {
      bind = "loopback";            # OCL-15: loopback only — nginx-proxied, not directly reachable
      trustedProxies = [ "127.0.0.1" ];
      auth = {
        rateLimit = {
          maxAttempts = 10;
          windowMs = 60000;
          lockoutMs = 300000;
        };
      };
      controlUi = {
        # OCL-20: explicit allowedOrigins instead of Host-header fallback
        root = "/var/lib/openclaw-${name}/.openclaw/control-ui";
        allowedOrigins = [ "https://${name}.openclaw.dangirsh.org" ];
      };
    };
  };

  openclawConfigFiles = lib.mapAttrs
    (name: _instance: pkgs.writeText "openclaw-${name}.json" (mkOpenclawConfig name))
    instances;

  instanceList = lib.mapAttrsToList (name: _instance: name) instances;
in
{
  sops.templates = lib.mapAttrs'
    (name: instance:
      lib.nameValuePair "openclaw-${name}-env" {
        content = ''
          OPENCLAW_GATEWAY_TOKEN=${config.sops.placeholder.${instance.gatewaySecret}}
          ANTHROPIC_API_KEY=${config.sops.placeholder."anthropic-api-key"}
          ${lib.optionalString (instance ? defaultModel) "ANTHROPIC_DEFAULT_MODEL=${instance.defaultModel}"}
        '';
        owner = "openclaw-${name}";
        mode = "0400";
      })
    instances;

  users.groups = lib.mapAttrs'
    (name: _instance: lib.nameValuePair "openclaw-${name}" { })
    instances;

  users.users = lib.mapAttrs'
    (name: _instance:
      lib.nameValuePair "openclaw-${name}" {
        isSystemUser = true;
        group = "openclaw-${name}";
        home = "/var/lib/openclaw-${name}";
        createHome = false;
        description = "OpenClaw service user (${name})";
      })
    instances;

  services.dashboard.entries = lib.mapAttrs'
    (name: instance:
      lib.nameValuePair "openclaw-${name}" {
        name = "OpenClaw ${name}";
        module = "openclaw.nix";
        description = "AI assistant gateway (port ${toString instance.port})";
        port = instance.port;
        url = "http://${config.networking.hostName}:${toString instance.port}";
        systemdUnit = "openclaw-${name}.service";
        icon = "openclaw";
        order = 40;
      })
    instances;

  system.activationScripts.openclaw-state = {
    text = ''
      set -euo pipefail

${lib.concatMapStringsSep "\n"
  (name: ''
      state_dir="/var/lib/openclaw-${name}"
      instance_user="openclaw-${name}"

      mkdir -p "''${state_dir}"
      chmod 0700 "''${state_dir}"  # OCL-21

      if [ -L "''${state_dir}/.openclaw" ]; then
        if [ "$(readlink "''${state_dir}/.openclaw")" != "." ]; then
          rm -f "''${state_dir}/.openclaw"
          ln -s . "''${state_dir}/.openclaw"
        fi
      elif [ ! -e "''${state_dir}/.openclaw" ]; then
        ln -s . "''${state_dir}/.openclaw"
      fi

      target="''${state_dir}/openclaw.json"
      if [ ! -f "''${target}" ] || grep -q '"model":\|"user":\|"bind":.*"lan"\|"mode":.*"local"' "''${target}" 2>/dev/null; then
        cp ${openclawConfigFiles.${name}} "''${target}"
        echo "openclaw: seeded/fixed openclaw.json for ${name}"
      fi

      # OCL-20: patch out dangerouslyAllowHostHeaderOriginFallback; set allowedOrigins if unset.
      # OCL-22: ensure tools.exec.host=gateway (not Docker sandbox) with security=full for headless.
      # jq-based in-place patch preserves user channel config (Discord tokens, etc.).
      if tmpout=$(${pkgs.jq}/bin/jq \
        'del(.gateway.controlUi.dangerouslyAllowHostHeaderOriginFallback) | .gateway.controlUi.allowedOrigins //= ["https://${name}.openclaw.dangirsh.org"] | .tools.exec.host //= "gateway" | .tools.exec.security //= "full"' \
        "''${target}" 2>/dev/null); then
        printf '%s\n' "''${tmpout}" > "''${target}.tmp" && mv "''${target}.tmp" "''${target}"
      fi

      chown -h "''${instance_user}:''${instance_user}" "''${state_dir}/.openclaw" 2>/dev/null || true
      chown -R "''${instance_user}:''${instance_user}" "''${state_dir}"
      chmod 0600 "''${target}"  # OCL-21
      if [ -d "''${state_dir}/credentials" ]; then
        chmod 0700 "''${state_dir}/credentials"  # OCL-21
      fi
  '')
  instanceList}
    '';
    deps = [ "setupSecrets" ];
  };

  systemd.services = lib.mapAttrs'
    (name: instance:
      lib.nameValuePair "openclaw-${name}" {
        description = "OpenClaw gateway (${name})";
        wantedBy = [ "multi-user.target" ];
        wants = [ "network-online.target" "sops-install-secrets.service" ];
        after = [ "network-online.target" "sops-install-secrets.service" ];

        serviceConfig = {
          Type = "simple";
          User = "openclaw-${name}";
          Group = "openclaw-${name}";
          WorkingDirectory = "/var/lib/openclaw-${name}";
          StateDirectory = "openclaw-${name}";
          StateDirectoryMode = "0700";  # OCL-21
          Environment = [
            "HOME=/var/lib/openclaw-${name}"
            "NODE_OPTIONS=--max-old-space-size=4096"  # OCL-18: 4GB V8 heap (50% of 8G MemoryMax)
            "SHELL=/bin/sh"                           # OCL-22: override nologin from /etc/passwd
            "PATH=/run/current-system/sw/bin"          # OCL-22: system binaries for agent exec
          ];
          EnvironmentFile = config.sops.templates."openclaw-${name}-env".path;
          ExecStart = "${openclawPkg}/bin/openclaw gateway --allow-unconfigured --port ${toString instance.port}";
          Restart = "always";
          RestartSec = 5;

          # --- Security hardening ---
          NoNewPrivileges = true;
          PrivateTmp = true;
          ProtectSystem = "strict";
          # StateDirectory auto-adds /var/lib/openclaw-${name} to ReadWritePaths
          PrivateDevices = true;
          ProtectHome = true;
          ProtectClock = true;
          ProtectKernelTunables = true;
          ProtectKernelModules = true;
          ProtectKernelLogs = true;
          ProtectControlGroups = true;
          RestrictAddressFamilies = [ "AF_INET" "AF_INET6" "AF_UNIX" "AF_NETLINK" ];  # AF_NETLINK required for os.networkInterfaces() (uv_interface_addresses)
          RestrictNamespaces = true;
          LockPersonality = true;
          MemoryDenyWriteExecute = false;  # OCL-16: Node.js V8 JIT requires W^X pages
          CapabilityBoundingSet = "";      # no capabilities needed — port > 1024

          # --- Resource limits (OCL-18: 50% of neurosys total ÷ 6 instances) ---
          MemoryHigh = "6G";
          MemoryMax = "8G";
          CPUQuota = "150%";
          TasksMax = 200;
        };
      })
    instances;
}
