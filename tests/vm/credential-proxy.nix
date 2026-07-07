# tests/vm/credential-proxy.nix - E2E proof for Iron-brokered credentials.
#
# This test runs through the real wrapper path:
#   credential-probe -> sudo launcher -> systemd-run -> setpriv drop
#     -> nono sandbox -> fake child -> iron-proxy -> fake provider
#
# It proves the child receives only Iron placeholder credentials while a fake
# upstream receives the real root-owned secret injected by iron-proxy.
{
  pkgs,
  impermanenceModule,
  ironProxyPackage,
  ...
}:
let
  fakeProbe = pkgs.writeShellApplication {
    name = "credential-probe";
    runtimeInputs = with pkgs; [
      coreutils
      curl
      gnugrep
    ];
    text = ''
      result="$PWD/credential-proxy-result.env"
      fail() {
        printf 'FAIL: %s\n' "$*" > "$result"
        exit 1
      }

      [ "$(id -u)" != "0" ] || fail "child still running as root"
      [ "$(whoami)" = "agent" ] || fail "child user is $(whoami), expected agent"
      [ -n "''${OPENROUTER_API_KEY:-}" ] || fail "missing OpenRouter Iron placeholder token"
      [ "$OPENROUTER_API_KEY" != "test-openrouter-secret" ] || fail "raw OpenRouter key leaked into child env"
      [ -z "''${NONO_PROXY_TOKEN:-}" ] || fail "legacy NONO_PROXY_TOKEN leaked into child env"
      [ -z "''${OPENROUTER_BASE_URL:-}" ] || fail "legacy OPENROUTER_BASE_URL leaked into child env"
      [ -n "''${HTTP_PROXY:-}" ] || fail "missing HTTP_PROXY"
      [ -n "''${HTTPS_PROXY:-}" ] || fail "missing HTTPS_PROXY"
      [ -n "''${ALL_PROXY:-}" ] || fail "missing ALL_PROXY"
      [ -n "''${NO_PROXY:-}" ] || fail "missing NO_PROXY"
      case "$HTTP_PROXY" in
        http://127.0.0.1:*|http://localhost:*) ;;
        *) fail "proxy URL is not loopback: $HTTP_PROXY" ;;
      esac
      proxy_authority="''${HTTP_PROXY#http://}"
      proxy_authority="''${proxy_authority%%/*}"
      proxy_port="''${proxy_authority##*:}"
      if [ -z "$proxy_port" ] || printf '%s' "$proxy_port" | grep -q '[^0-9]'; then
        fail "proxy port is not numeric: $HTTP_PROXY"
      fi
      [ "$proxy_port" = "20208" ] || fail "unexpected Iron tunnel port: $HTTP_PROXY"
      if [ -r /run/secrets/openrouter-api-key ]; then
        fail "raw secret file is readable from child"
      fi
      if [ -r /run/secrets-rendered/iron-agent-egress-env ]; then
        fail "Iron service environment file is readable from child"
      fi
      if [ -r /var/lib/tsurf-agent-egress-proxy/credential-tokens.env ]; then
        fail "Iron credential token file is readable from child"
      fi

      if curl --connect-timeout 2 --max-time 5 -fsS http://127.0.0.1:18080/health >/tmp/direct-loopback-response 2>&1; then
        fail "child reached direct loopback fake provider"
      fi

      http_code="$(
        curl --connect-timeout 2 --max-time 15 -sS -o "$PWD/upstream-response.json" -w '%{http_code}' \
          --noproxy "" \
          -x "$HTTP_PROXY" \
          -X POST \
          -H "Authorization: Bearer $OPENROUTER_API_KEY" \
          -H "Content-Type: application/json" \
          --data '{"probe":true}' \
          "http://127.0.0.1:18080/v1/responses"
      )"
      [ "$http_code" = "200" ] || fail "upstream returned HTTP $http_code"

      {
        printf 'PASS: Iron credential proxy child boundary held\n'
        printf 'uid=%s\n' "$(id -u)"
        printf 'user=%s\n' "$(whoami)"
        printf 'placeholder_len=%s\n' "''${#OPENROUTER_API_KEY}"
        printf 'proxy_url=%s\n' "$HTTP_PROXY"
      } > "$result"
    '';
  };
in
pkgs.testers.nixosTest {
  name = "credential-proxy";

  nodes.machine =
    {
      config,
      pkgs,
      lib,
      ...
    }:
    {
      imports = [
        impermanenceModule
        ../../modules/users.nix
        ../../modules/networking.nix
        ../../modules/agent-compute.nix
        ../../modules/nono.nix
        ../../modules/agent-launcher.nix
        ../../modules/agent-egress-proxy.nix
      ];

      options.sops = {
        secrets = lib.mkOption {
          type = lib.types.attrsOf lib.types.attrs;
          default = { };
          description = "Minimal test-only sops secret option stub.";
        };
        placeholder = lib.mkOption {
          type = lib.types.attrsOf lib.types.str;
          default = { };
          description = "Minimal test-only sops placeholder stub.";
        };
        templates = lib.mkOption {
          type = lib.types.attrsOf (
            lib.types.submodule (
              { name, ... }:
              {
                options = {
                  content = lib.mkOption {
                    type = lib.types.lines;
                    default = "";
                  };
                  owner = lib.mkOption {
                    type = lib.types.str;
                    default = "root";
                  };
                  group = lib.mkOption {
                    type = lib.types.str;
                    default = "root";
                  };
                  mode = lib.mkOption {
                    type = lib.types.str;
                    default = "0400";
                  };
                  path = lib.mkOption {
                    type = lib.types.str;
                    default = "/run/secrets-rendered/${name}";
                  };
                };
              }
            )
          );
          default = { };
          description = "Minimal test-only sops template option stub.";
        };
      };

      config = {
        tsurf.template.allowUnsafePlaceholders = true;

        networking.hostName = "credential-proxy";
        services.agentCompute.enable = true;
        services.agentLauncher.enable = true;
        services.agentLauncher.scopeAccess = "allow";
        services.agentEgressProxy.enable = true;
        services.agentEgressProxy.package = ironProxyPackage;
        services.nonoSandbox.enable = true;

        services.agentLauncher.agents.credential-probe = {
          command = "credential-probe";
          package = fakeProbe;
          wrapperName = "credential-probe";
          credentialServices = [ "openrouter" ];
          credentialOverrides.openrouter.upstream = "http://127.0.0.1:18080/v1";
        };

        sops.secrets."openrouter-api-key" = {
          owner = "root";
          group = "root";
          mode = "0400";
        };
        sops.placeholder."openrouter-api-key" = "test-openrouter-secret";

        environment.systemPackages = with pkgs; [
          curl
          python3
        ];

        system.activationScripts.credential-proxy-fixture = ''
          install -d -m 0755 /data /data/projects
          install -d -m 0755 -o ${config.tsurf.agent.user} -g ${config.tsurf.agent.user} /data/projects/credential-probe
          printf 'credential proxy workspace\n' > /data/projects/credential-probe/README.md
          chown ${config.tsurf.agent.user}:${config.tsurf.agent.user} /data/projects/credential-probe/README.md

          install -d -m 0755 -o ${config.tsurf.agent.user} -g ${config.tsurf.agent.user} ${config.tsurf.agent.home}
          install -d -m 0700 -o root -g ${config.tsurf.agent.user} ${config.tsurf.agent.home}/.nono
          install -d -m 0700 -o root -g ${config.tsurf.agent.user} ${config.tsurf.agent.home}/.nono/sessions
          install -d -m 0700 -o root -g ${config.tsurf.agent.user} ${config.tsurf.agent.home}/.nono/rollbacks

          install -d -m 0755 /run/secrets
          printf 'test-openrouter-secret' > /run/secrets/openrouter-api-key
          chown root:root /run/secrets/openrouter-api-key
          chmod 0400 /run/secrets/openrouter-api-key

          install -d -m 0755 /run/secrets-rendered
          printf '%s' ${lib.escapeShellArg config.sops.templates."iron-agent-egress-env".content} > ${
            config.sops.templates."iron-agent-egress-env".path
          }
          chown iron-proxy:iron-proxy ${config.sops.templates."iron-agent-egress-env".path}
          chmod 0400 ${config.sops.templates."iron-agent-egress-env".path}
        '';

        system.stateVersion = "26.11";
      };
    };

  testScript = ''
    import json
    import textwrap

    machine.wait_for_unit("multi-user.target")

    machine.succeed(
        textwrap.dedent(
            """
            install -d -m 0755 /data /data/projects
            install -d -m 0755 -o agent -g agent /data/projects/credential-probe
            printf 'credential proxy workspace\\n' > /data/projects/credential-probe/README.md
            chown agent:agent /data/projects/credential-probe/README.md
            install -d -m 0755 -o agent -g agent /home/agent
            install -d -m 0700 -o root -g agent /home/agent/.nono
            install -d -m 0700 -o root -g agent /home/agent/.nono/sessions
            install -d -m 0700 -o root -g agent /home/agent/.nono/rollbacks
            """
        )
    )

    machine.succeed(
        textwrap.dedent(
            r"""
            cat > /tmp/fake-provider.py <<'PY'
            import json
            from http.server import BaseHTTPRequestHandler, HTTPServer

            class Handler(BaseHTTPRequestHandler):
                def do_GET(self):
                    if self.path == "/health":
                        self.send_response(200)
                        self.end_headers()
                        self.wfile.write(b"ok")
                        return
                    self.send_response(404)
                    self.end_headers()

                def do_POST(self):
                    length = int(self.headers.get("Content-Length", "0"))
                    body = self.rfile.read(length).decode("utf-8", "replace")
                    observed = {
                        "path": self.path,
                        "authorization": self.headers.get("Authorization", ""),
                        "body": body,
                    }
                    with open("/tmp/fake-provider-request.json", "w") as f:
                        json.dump(observed, f, sort_keys=True)
                    self.send_response(200)
                    self.send_header("Content-Type", "application/json")
                    self.end_headers()
                    self.wfile.write(b'{"ok":true}')

                def log_message(self, format, *args):
                    return

            HTTPServer(("127.0.0.1", 18080), Handler).serve_forever()
            PY
            """
        )
    )
    machine.succeed(
        "python3 /tmp/fake-provider.py >/tmp/fake-provider.log 2>&1 & echo $! >/tmp/fake-provider.pid"
    )
    machine.wait_until_succeeds("curl -fsS http://127.0.0.1:18080/health")
    machine.wait_for_unit("tsurf-agent-egress-proxy.service")

    machine.succeed(
        "sudo -u agent bash -lc 'cd /data/projects/credential-probe && credential-probe exec probe'"
    )

    result = machine.succeed("cat /data/projects/credential-probe/credential-proxy-result.env")
    assert "PASS: Iron credential proxy child boundary held" in result, result
    assert "user=agent" in result, result

    request = json.loads(machine.succeed("cat /tmp/fake-provider-request.json"))
    assert request["path"] == "/v1/responses", request
    assert request["authorization"] == "Bearer test-openrouter-secret", request
    assert request["body"] == '{"probe":true}', request

    machine.fail("sudo -u agent cat /run/secrets/openrouter-api-key")
  '';
}
