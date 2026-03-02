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
{ config, lib, pkgs, ... }:

let
  openclawPkg = pkgs.callPackage ../packages/openclaw.nix { };

  instances = {
    mark = {
      port = 18789;
      gatewaySecret = "openclaw-mark-gateway-token";
    };
    lou = {
      port = 18790;
      gatewaySecret = "openclaw-lou-gateway-token";
    };
    alexia = {
      port = 18791;
      gatewaySecret = "openclaw-alexia-gateway-token";
    };
    ari = {
      port = 18792;
      gatewaySecret = "openclaw-ari-gateway-token";
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

  mkOpenclawConfig = _name: builtins.toJSON {
    gateway = {
      port = 18789;
      bind = "lan";
      trustedProxies = [ "127.0.0.1" ];
      auth = {
        rateLimit = {
          maxAttempts = 10;
          windowMs = 60000;
          lockoutMs = 300000;
        };
      };
      controlUi = {
        dangerouslyAllowHostHeaderOriginFallback = true;
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

  system.activationScripts.openclaw-state = {
    text = ''
      set -euo pipefail

${lib.concatMapStringsSep "\n"
  (name: ''
      state_dir="/var/lib/openclaw-${name}"
      instance_user="openclaw-${name}"

      mkdir -p "''${state_dir}"
      chmod 0750 "''${state_dir}"

      if [ -L "''${state_dir}/.openclaw" ]; then
        if [ "$(readlink "''${state_dir}/.openclaw")" != "." ]; then
          rm -f "''${state_dir}/.openclaw"
          ln -s . "''${state_dir}/.openclaw"
        fi
      elif [ ! -e "''${state_dir}/.openclaw" ]; then
        ln -s . "''${state_dir}/.openclaw"
      fi

      target="''${state_dir}/openclaw.json"
      if [ ! -f "''${target}" ] || grep -q '"model":\|"user":' "''${target}" 2>/dev/null; then
        cp ${openclawConfigFiles.${name}} "''${target}"
        echo "openclaw: seeded/fixed openclaw.json for ${name}"
      fi

      chown -h "''${instance_user}:''${instance_user}" "''${state_dir}/.openclaw" 2>/dev/null || true
      chown -R "''${instance_user}:''${instance_user}" "''${state_dir}"
      chmod 0640 "''${target}"
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
        wants = [ "network-online.target" ];
        after = [ "network-online.target" "setupSecrets" ];

        serviceConfig = {
          Type = "simple";
          User = "openclaw-${name}";
          Group = "openclaw-${name}";
          WorkingDirectory = "/var/lib/openclaw-${name}";
          StateDirectory = "openclaw-${name}";
          StateDirectoryMode = "0750";
          Environment = [
            "HOME=/var/lib/openclaw-${name}"
          ];
          EnvironmentFile = config.sops.templates."openclaw-${name}-env".path;
          ExecStart = "${openclawPkg}/bin/openclaw gateway --allow-unconfigured --port ${toString instance.port}";
          Restart = "always";
          RestartSec = 5;
          NoNewPrivileges = true;
        };
      })
    instances;
}
