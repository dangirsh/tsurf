# tests/vm/credential-proxy.nix — E2E proof for nono brokered credentials.
#
# This test runs through the real wrapper path:
#   credential-probe -> sudo launcher -> systemd-run -> nono credential proxy
#     -> setpriv drop -> fake child
#
# It proves the child receives only phantom credentials while a fake upstream
# receives the real root-owned secret injected by nono.
{
  pkgs,
  lib,
  impermanenceModule,
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
      [ -z "''${OPENROUTER_API_KEY:-}" ] || fail "raw OpenRouter key leaked into child env"
      [ -n "''${NONO_PROXY_TOKEN:-}" ] || fail "missing NONO_PROXY_TOKEN"
      [ -n "''${OPENROUTER_BASE_URL:-}" ] || fail "missing OPENROUTER_BASE_URL"
      [ -z "''${HTTP_PROXY:-}" ] || fail "HTTP_PROXY leaked into child env"
      [ -z "''${HTTPS_PROXY:-}" ] || fail "HTTPS_PROXY leaked into child env"
      [ -z "''${ALL_PROXY:-}" ] || fail "ALL_PROXY leaked into child env"
      [ -z "''${NO_PROXY:-}" ] || fail "NO_PROXY leaked into child env"
      case "$OPENROUTER_BASE_URL" in
        http://127.0.0.1:*|http://localhost:*) ;;
        *) fail "proxy base URL is not loopback: $OPENROUTER_BASE_URL" ;;
      esac
      proxy_authority="''${OPENROUTER_BASE_URL#http://}"
      proxy_authority="''${proxy_authority%%/*}"
      if [ -r /run/secrets/openrouter-api-key ]; then
        fail "raw secret file is readable from child"
      fi

      if curl -fsS -x "http://$proxy_authority" http://127.0.0.1:18080/health >/tmp/generic-proxy-response 2>&1; then
        fail "nono credential proxy allowed generic HTTP proxy traffic"
      fi

      http_code="$(
        curl -sS -o "$PWD/upstream-response.json" -w '%{http_code}' \
          -X POST \
          -H "Authorization: Bearer $NONO_PROXY_TOKEN" \
          -H "Content-Type: application/json" \
          --data '{"probe":true}' \
          "$OPENROUTER_BASE_URL/responses"
      )"
      [ "$http_code" = "200" ] || fail "upstream returned HTTP $http_code"

      {
        printf 'PASS: credential proxy child boundary held\n'
        printf 'uid=%s\n' "$(id -u)"
        printf 'user=%s\n' "$(whoami)"
        printf 'token_len=%s\n' "''${#NONO_PROXY_TOKEN}"
        printf 'base_url=%s\n' "$OPENROUTER_BASE_URL"
      } > "$result"
    '';
  };
in
pkgs.testers.nixosTest {
  name = "credential-proxy";

  nodes.machine =
    { config, pkgs, lib, ... }:
    {
      imports = [
        impermanenceModule
        ../../modules/users.nix
        ../../modules/networking.nix
        ../../modules/agent-compute.nix
        ../../modules/nono.nix
        ../../modules/agent-launcher.nix
      ];

      options.sops.secrets = lib.mkOption {
        type = lib.types.attrsOf lib.types.attrs;
        default = { };
        description = "Minimal test-only sops secret option stub.";
      };

      config = {
        tsurf.template.allowUnsafePlaceholders = true;

        networking.hostName = "credential-proxy";
        services.agentCompute.enable = true;
        services.agentLauncher.enable = true;
        services.agentLauncher.scopeAccess = "allow";
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
          install -d -m 0700 -o root -g ${config.tsurf.agent.user} ${config.tsurf.agent.home}/.nono/rollbacks

          install -d -m 0755 /run/secrets
          printf 'test-openrouter-secret' > /run/secrets/openrouter-api-key
          chown root:root /run/secrets/openrouter-api-key
          chmod 0400 /run/secrets/openrouter-api-key
        '';

        system.stateVersion = "26.11";
      };
    };

  testScript = ''
    import json
    import textwrap

    machine.wait_for_unit("multi-user.target")

    machine.succeed(
        "cat > /tmp/fake-provider.py <<'PY'\n"
        + textwrap.dedent(
            r'''
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

                def log_message(self, fmt, *args):
                    return

            HTTPServer(("127.0.0.1", 18080), Handler).serve_forever()
            '''
        )
        + "\nPY"
    )
    machine.succeed(
        "python3 /tmp/fake-provider.py >/tmp/fake-provider.log 2>&1 & echo $! >/tmp/fake-provider.pid"
    )
    machine.wait_until_succeeds("curl -fsS http://127.0.0.1:18080/health")

    machine.succeed(
        "sudo -u agent bash -lc 'cd /data/projects/credential-probe && credential-probe exec probe'"
    )

    result = machine.succeed("cat /data/projects/credential-probe/credential-proxy-result.env")
    assert "PASS: credential proxy child boundary held" in result, result
    assert "user=agent" in result, result

    request = json.loads(machine.succeed("cat /tmp/fake-provider-request.json"))
    assert request["path"] == "/v1/responses", request
    assert request["authorization"] == "Bearer test-openrouter-secret", request
    assert request["body"] == '{"probe":true}', request

    machine.fail("sudo -u agent cat /run/secrets/openrouter-api-key")
  '';
}
