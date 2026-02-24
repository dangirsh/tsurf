# modules/secret-proxy.nix
# @decision PROXY-22-01: Header-only injection — real key replaced in Authorization header only,
#   never in response body, preventing key reflection attacks via LLM output.
# @decision PROXY-22-02: HTTP base URL (ANTHROPIC_BASE_URL) avoids TLS MITM complexity.
#   Proxy speaks plain HTTP from agent; forwards to https://api.anthropic.com upstream.
# @decision PROXY-22-03: Dedicated system user (secret-proxy) for least privilege.
#   sops template owned by this user; no other process can read the env file.
{ config, pkgs, ... }:
let
  proxy = pkgs.writers.writePython3Bin "anthropic-secret-proxy" {} ''
    import http.server
    import http.client
    import ssl
    import os
    import socketserver

    UPSTREAM = "api.anthropic.com"
    KEY = os.environ["REAL_ANTHROPIC_API_KEY"].strip()
    PORT = int(os.environ.get("SECRET_PROXY_PORT", "9091"))
    SKIP_REQ = ("x-api-key", "authorization", "host",
                "content-length", "transfer-encoding")
    SKIP_RESP = ("transfer-encoding", "connection")


    class Handler(http.server.BaseHTTPRequestHandler):
        def do_request(self):
            ctx = ssl.create_default_context()
            conn = http.client.HTTPSConnection(UPSTREAM, context=ctx)
            hdrs = {k: v for k, v in self.headers.items()
                    if k.lower() not in SKIP_REQ}
            hdrs["x-api-key"] = KEY
            hdrs["Host"] = UPSTREAM
            body_len = int(self.headers.get("Content-Length", 0))
            body = self.rfile.read(body_len) if body_len > 0 else None
            if body:
                hdrs["Content-Length"] = str(len(body))
            conn.request(self.command, self.path, body=body, headers=hdrs)
            resp = conn.getresponse()
            self.send_response(resp.status, resp.reason)
            for name, value in resp.getheaders():
                if name.lower() not in SKIP_RESP:
                    self.send_header(name, value)
            self.end_headers()
            while chunk := resp.read(4096):
                self.wfile.write(chunk)
                self.wfile.flush()
            conn.close()

        do_GET = do_request
        do_POST = do_request
        do_PUT = do_request
        do_DELETE = do_request
        do_PATCH = do_request
        do_HEAD = do_request
        do_OPTIONS = do_request

        def log_message(self, fmt, *args):
            pass


    socketserver.ThreadingTCPServer.allow_reuse_address = True
    with socketserver.ThreadingTCPServer(("127.0.0.1", PORT), Handler) as s:
        s.serve_forever()
  '';
in {
  users.users.secret-proxy = { isSystemUser = true; group = "secret-proxy"; };
  users.groups.secret-proxy = {};

  sops.templates."secret-proxy-env" = {
    content = "REAL_ANTHROPIC_API_KEY=${config.sops.placeholder."anthropic-api-key"}";
    owner = "secret-proxy";
  };

  systemd.services.anthropic-secret-proxy = {
    description = "Anthropic API secret proxy";
    after = [ "network.target" "sops-nix.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      ExecStart = "${proxy}/bin/anthropic-secret-proxy";
      EnvironmentFile = config.sops.templates."secret-proxy-env".path;
      User = "secret-proxy";
      Restart = "on-failure";
      RestartSec = "5s";
    };
  };
}
