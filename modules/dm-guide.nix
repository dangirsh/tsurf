# modules/dm-guide.nix
# DM Pairing Guide: self-hosted bridge login helper for Matrix DM onboarding.
#
# @decision DMG-01: Standalone Python HTTP service (stdlib only, no framework).
# @rationale: Minimal dependency surface and predictable packaging via
#   pkgs.writers.writePython3Bin. A single binary serves HTML + proxy API.
#
# @decision DMG-02: Shared provisioning secret read at runtime via LoadCredential.
# @rationale: Secret never enters the Nix store and is not exposed in process args.
#   systemd injects a root-readable credential file scoped to the service.
#
# @decision DMG-03: One local guide service proxies all bridge login flows.
# @rationale: Browser never talks to bridge ports directly; auth header injection
#   remains server-side. This centralizes provisioning API compatibility logic.
#
# @decision DMG-04: Port 8086 binds 0.0.0.0 with firewall closed.
# @rationale: Matches existing internal tooling pattern: reachable over trusted
#   interfaces (Tailscale), not publicly exposed via allowedTCPPorts.
{ config, pkgs, lib, ... }:

let
  port = 8086;

  htmlPage = pkgs.writeText "dm-guide.html" ''
    <!DOCTYPE html>
    <html lang="en">
    <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>DM Pairing Guide</title>
    <script src="https://cdn.jsdelivr.net/npm/qrcode-generator@1.4.4/qrcode.min.js"></script>
    <style>
    :root { --bg: #1a1a2e; --surface: #16213e; --border: #0f3460; --text: #e0e0e0; --accent: #e94560; --ok: #4ecca3; }
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; background: var(--bg); color: var(--text); padding: 1.5rem; max-width: 980px; margin: 0 auto; }
    h1 { font-size: 1.5rem; margin-bottom: 1rem; color: var(--ok); }
    h2 { font-size: 1.1rem; color: var(--accent); margin-bottom: 0.6rem; }
    p { margin-bottom: 0.7rem; color: #c8c8d8; }
    .section { background: var(--surface); border: 1px solid var(--border); border-radius: 8px; padding: 1rem; margin-bottom: 1rem; }
    .row { display: flex; gap: 0.6rem; flex-wrap: wrap; align-items: center; margin-bottom: 0.6rem; }
    .field { flex: 1 1 280px; }
    label { display: block; margin-bottom: 0.3rem; font-size: 0.85rem; color: var(--accent); }
    input[type="text"], input[type="password"], input[type="tel"] {
      background: var(--surface); color: var(--text); border: 1px solid var(--border);
      padding: 0.45rem; border-radius: 4px; width: 100%;
    }
    button { padding: 0.45rem 0.9rem; border: none; border-radius: 4px; cursor: pointer; background: var(--border); color: var(--text); }
    button.primary { background: var(--ok); color: var(--bg); font-weight: bold; }
    .status { font-size: 0.85rem; min-height: 1.2rem; }
    .status.ok { color: var(--ok); }
    .status.err { color: var(--accent); }
    .qr { background: white; display: inline-flex; padding: 0.6rem; border-radius: 6px; min-height: 160px; min-width: 160px; align-items: center; justify-content: center; }
    pre { background: #0f1226; border: 1px solid var(--border); border-radius: 6px; padding: 0.7rem; max-height: 230px; overflow: auto; font-size: 0.8rem; }
    .small { font-size: 0.8rem; color: #a9a9bc; }
    </style>
    </head>
    <body>
    <h1>DM Pairing Guide</h1>
    <p>Use this page to pair Matrix bridges for direct messaging.</p>

    <div class="section">
      <div class="row">
        <div class="field">
          <label for="mxid">Matrix user ID</label>
          <input id="mxid" type="text" value="@admin:neurosys.local">
        </div>
      </div>
      <div class="small">Provisioning calls are proxied locally and authenticated by a service credential.</div>
    </div>

    <div class="section">
      <h2>Signal</h2>
      <p>Start login and scan the QR code from Signal on your phone.</p>
      <div class="row">
        <button class="primary" onclick="startQr('signal')">Start Signal Pairing</button>
      </div>
      <div id="status-signal" class="status"></div>
      <div id="qr-signal" class="qr"></div>
    </div>

    <div class="section">
      <h2>WhatsApp</h2>
      <p>Start login and scan the QR code from WhatsApp linked-devices settings.</p>
      <div class="row">
        <button class="primary" onclick="startQr('whatsapp')">Start WhatsApp Pairing</button>
      </div>
      <div id="status-whatsapp" class="status"></div>
      <div id="qr-whatsapp" class="qr"></div>
    </div>

    <div class="section">
      <h2>Telegram</h2>
      <p>Enter your phone number, then submit code and optional 2FA password.</p>
      <div class="row">
        <div class="field">
          <label for="tg-phone">Phone number (E.164)</label>
          <input id="tg-phone" type="tel" placeholder="+491234567890">
        </div>
        <button class="primary" onclick="telegramPhone()">Send Code</button>
      </div>
      <div class="row">
        <div class="field">
          <label for="tg-code">SMS / Telegram code</label>
          <input id="tg-code" type="text" placeholder="12345">
        </div>
        <button onclick="telegramCode()">Submit Code</button>
      </div>
      <div class="row">
        <div class="field">
          <label for="tg-password">2FA password (if required)</label>
          <input id="tg-password" type="password">
        </div>
        <button onclick="telegramPassword()">Submit 2FA</button>
      </div>
      <div id="status-telegram" class="status"></div>
      <pre id="telegram-response">{}</pre>
    </div>

    <script>
    const sessionState = {
      signal: {},
      whatsapp: {},
      telegram: {}
    };

    const pollers = {
      signal: null,
      whatsapp: null
    };

    function matrixUserId() {
      return document.getElementById('mxid').value.trim();
    }

    function setStatus(bridge, text, ok) {
      const el = document.getElementById('status-' + bridge);
      el.textContent = text;
      el.className = ok === null ? 'status' : (ok ? 'status ok' : 'status err');
    }

    function renderQr(bridge, qrText) {
      const container = document.getElementById('qr-' + bridge);
      if (!qrText) {
        container.textContent = 'No QR data yet';
        return;
      }
      try {
        const qr = qrcode(0, 'M');
        qr.addData(qrText);
        qr.make();
        container.innerHTML = qr.createImgTag(5, 8);
      } catch (err) {
        container.textContent = 'QR render failed: ' + err;
      }
    }

    function basePayload(extra) {
      return Object.assign({ user_id: matrixUserId() }, extra || {});
    }

    async function postBridge(bridge, action, payload) {
      const resp = await fetch('/api/bridge/' + bridge + '/login/' + action, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(basePayload(payload))
      });
      return await resp.json();
    }

    function loginComplete(data) {
      if (!data || typeof data !== 'object') return false;
      if (data.logged_in === true) return true;
      if (data.connected === true) return true;
      const text = String(data.state || data.status || '').toLowerCase();
      return ['done', 'success', 'connected', 'complete', 'logged_in'].includes(text);
    }

    function updateSession(bridge, data) {
      if (!data || typeof data !== 'object') return;
      const next = Object.assign({}, sessionState[bridge]);
      const keys = ['flow_id', 'login_id', 'session_id', 'token', 'txn_id', 'phone_number'];
      keys.forEach((k) => {
        if (data[k]) next[k] = data[k];
      });
      if (data.raw && typeof data.raw === 'object') {
        keys.forEach((k) => {
          if (data.raw[k]) next[k] = data.raw[k];
        });
      }
      sessionState[bridge] = next;
    }

    function stopPolling(bridge) {
      if (pollers[bridge]) {
        clearInterval(pollers[bridge]);
        pollers[bridge] = null;
      }
    }

    function startPolling(bridge) {
      stopPolling(bridge);
      pollers[bridge] = setInterval(async () => {
        const result = await postBridge(bridge, 'wait', sessionState[bridge]);
        if (!result.ok) {
          setStatus(bridge, result.error || 'Waiting for scan...', null);
          return;
        }
        updateSession(bridge, result);
        if (result.qr_data) {
          renderQr(bridge, result.qr_data);
        }
        if (loginComplete(result)) {
          setStatus(bridge, 'Pairing complete', true);
          stopPolling(bridge);
          return;
        }
        setStatus(bridge, 'Waiting for scan/confirmation...', null);
      }, 2500);
    }

    async function startQr(bridge) {
      setStatus(bridge, 'Starting login...', null);
      const result = await postBridge(bridge, 'start', {});
      if (!result.ok) {
        setStatus(bridge, result.error || 'Start failed', false);
        return;
      }
      updateSession(bridge, result);
      renderQr(bridge, result.qr_data || '');
      if (result.qr_data) {
        setStatus(bridge, 'QR ready - scan from your phone', true);
      } else {
        setStatus(bridge, 'Login started (no QR returned yet)', null);
      }
      startPolling(bridge);
    }

    function setTelegram(result) {
      const pre = document.getElementById('telegram-response');
      pre.textContent = JSON.stringify(result || {}, null, 2);
      setStatus('telegram', result.ok ? 'Step accepted' : (result.error || 'Step failed'), !!result.ok);
      updateSession('telegram', result);
      if (result.raw && typeof result.raw === 'object') {
        updateSession('telegram', result.raw);
      }
    }

    async function telegramPhone() {
      const phone = document.getElementById('tg-phone').value.trim();
      const result = await postBridge('telegram', 'phone', { phone_number: phone });
      sessionState.telegram.phone_number = phone;
      setTelegram(result);
    }

    async function telegramCode() {
      const code = document.getElementById('tg-code').value.trim();
      const payload = Object.assign({}, sessionState.telegram, { code: code });
      const result = await postBridge('telegram', 'code', payload);
      setTelegram(result);
    }

    async function telegramPassword() {
      const password = document.getElementById('tg-password').value;
      const payload = Object.assign({}, sessionState.telegram, { password: password });
      const result = await postBridge('telegram', 'password', payload);
      setTelegram(result);
    }

    ['signal', 'whatsapp'].forEach((bridge) => renderQr(bridge, ''));
    </script>
    </body>
    </html>
  '';

  dmGuideServer = pkgs.writers.writePython3Bin "dm-guide-server"
    {
      flakeIgnore = [ "E501" ];
    }
    ''
    import http.server
    import json
    import os
    import socketserver
    import urllib.error
    import urllib.parse
    import urllib.request

    PORT = ${toString port}
    HTML_FILE = "${htmlPage}"
    CREDS_DIR = os.environ.get("CREDENTIALS_DIRECTORY", "/run/secrets")
    SECRET_FILE = os.path.join(CREDS_DIR, "dm-provisioning-secret")

    BRIDGE_BASE_URLS = {
        "whatsapp": "http://localhost:29318/_matrix/provision",
        "signal": "http://localhost:29328/_matrix/provision",
        "telegram": "http://localhost:29317/_matrix/provision",
    }


    def read_secret():
        try:
            with open(SECRET_FILE) as f:
                return f.read().strip()
        except FileNotFoundError:
            return ""


    def normalize_endpoint(endpoint):
        if endpoint.startswith("/"):
            return endpoint
        return "/" + endpoint


    def decode_body(data):
        if not data:
            return {}
        try:
            return json.loads(data.decode())
        except Exception:
            return {"raw": data.decode(errors="replace")}


    def bridge_request(bridge, method, endpoint, payload=None, query_string=""):
        base = BRIDGE_BASE_URLS[bridge]
        path = normalize_endpoint(endpoint)
        url = base + path
        if query_string:
            url = url + "?" + query_string

        body = None
        if payload is not None:
            body = json.dumps(payload).encode()

        req = urllib.request.Request(url, method=method, data=body)
        req.add_header("Authorization", "Bearer " + read_secret())
        req.add_header("Accept", "application/json")
        if body is not None:
            req.add_header("Content-Type", "application/json")

        try:
            with urllib.request.urlopen(req, timeout=20) as resp:
                data = decode_body(resp.read())
                return {"ok": True, "status": resp.getcode(), "data": data}
        except urllib.error.HTTPError as err:
            response = decode_body(err.read())
            error = response.get("error") if isinstance(response, dict) else str(response)
            return {"ok": False, "status": err.code, "error": error or err.reason, "data": response}
        except urllib.error.URLError as err:
            return {"ok": False, "status": 502, "error": str(err.reason), "data": {}}
        except Exception as err:
            return {"ok": False, "status": 500, "error": str(err), "data": {}}


    def first_value(data, keys):
        if not isinstance(data, dict):
            return None
        for key in keys:
            value = data.get(key)
            if value:
                return value
        return None


    def extract_qr_data(data):
        if isinstance(data, dict):
            for key in ["qr_data", "qrData", "qr", "qr_code", "qrcode", "code"]:
                value = data.get(key)
                if isinstance(value, str) and value.strip():
                    return value
            nested = data.get("data")
            if isinstance(nested, dict):
                return extract_qr_data(nested)
        return None


    def request_candidates(bridge, method, endpoints, payload=None, query_string=""):
        errors = []
        for endpoint in endpoints:
            result = bridge_request(bridge, method, endpoint, payload, query_string)
            if result["ok"]:
                return result
            errors.append(
                {
                    "endpoint": endpoint,
                    "status": result.get("status"),
                    "error": result.get("error"),
                }
            )
        return {"ok": False, "status": 502, "error": "no candidate endpoint succeeded", "errors": errors}


    def normalize_flows(data):
        if isinstance(data, dict):
            flows = data.get("flows")
            if isinstance(flows, list):
                return flows
        if isinstance(data, list):
            return data
        return []


    def start_qr_login(bridge, payload):
        user_id = payload.get("user_id", "@admin:neurosys.local")
        query = urllib.parse.urlencode({"user_id": user_id})
        flows_result = request_candidates(
            bridge,
            "GET",
            ["/v3/login/flows", "/v2/login/flows", "/v1/login/flows", "/login/flows"],
            query_string=query,
        )
        if not flows_result["ok"]:
            flows_result = request_candidates(
                bridge,
                "GET",
                ["/v3/login/flows", "/v2/login/flows", "/v1/login/flows", "/login/flows"],
            )

        flows = normalize_flows(flows_result.get("data", {})) if flows_result["ok"] else []
        qr_flow = None
        for flow in flows:
            flow_type = str(flow.get("type", "")).lower()
            if "qr" in flow_type:
                qr_flow = flow
                break

        start_payload = dict(payload)
        start_payload["user_id"] = user_id
        flow_id = None
        if isinstance(qr_flow, dict):
            flow_id = first_value(qr_flow, ["flow_id", "id", "type"])
            if flow_id and "flow_id" not in start_payload:
                start_payload["flow_id"] = flow_id

        start_result = request_candidates(
            bridge,
            "POST",
            ["/v3/login/start", "/v2/login/start", "/v1/login/start", "/login/start"],
            payload=start_payload,
        )
        if not start_result["ok"] and flow_id:
            start_result = request_candidates(
                bridge,
                "POST",
                [
                    "/v3/login/" + str(flow_id) + "/start",
                    "/v2/login/" + str(flow_id) + "/start",
                    "/v1/login/" + str(flow_id) + "/start",
                    "/login/" + str(flow_id) + "/start",
                ],
                payload=start_payload,
            )

        if not start_result["ok"]:
            return {
                "ok": False,
                "status": start_result.get("status", 502),
                "error": start_result.get("error", "unable to start login flow"),
                "errors": start_result.get("errors", []),
                "flows": flows,
            }

        data = start_result.get("data", {})
        qr_data = extract_qr_data(data)
        response = {
            "ok": True,
            "status": start_result.get("status", 200),
            "raw": data,
            "flows": flows,
            "flow_id": flow_id or first_value(data, ["flow_id", "id"]),
            "login_id": first_value(data, ["login_id", "session_id"]),
            "token": first_value(data, ["token", "txn_id"]),
            "qr_data": qr_data,
        }
        if not qr_data:
            response["error"] = "login started but provisioning API returned no QR payload"
        return response


    def wait_qr_login(bridge, payload):
        wait_payload = dict(payload)
        if "user_id" not in wait_payload:
            wait_payload["user_id"] = "@admin:neurosys.local"

        wait_result = request_candidates(
            bridge,
            "POST",
            ["/v3/login/wait", "/v2/login/wait", "/v1/login/wait", "/login/wait"],
            payload=wait_payload,
        )
        if not wait_result["ok"]:
            query = urllib.parse.urlencode(
                {k: str(v) for k, v in wait_payload.items() if v is not None}
            )
            wait_result = request_candidates(
                bridge,
                "GET",
                ["/v3/login/wait", "/v2/login/wait", "/v1/login/wait", "/login/wait"],
                query_string=query,
            )

        if not wait_result["ok"]:
            return {
                "ok": False,
                "status": wait_result.get("status", 502),
                "error": wait_result.get("error", "unable to poll login state"),
                "errors": wait_result.get("errors", []),
            }

        data = wait_result.get("data", {})
        state = ""
        if isinstance(data, dict):
            state = str(data.get("state", data.get("status", ""))).lower()
        complete = state in ["done", "success", "connected", "complete", "logged_in"]
        if isinstance(data, dict) and (data.get("logged_in") or data.get("connected")):
            complete = True

        return {
            "ok": True,
            "status": wait_result.get("status", 200),
            "raw": data,
            "state": state,
            "connected": complete,
            "flow_id": first_value(data, ["flow_id", "id"]),
            "login_id": first_value(data, ["login_id", "session_id"]),
            "token": first_value(data, ["token", "txn_id"]),
            "qr_data": extract_qr_data(data),
        }


    def telegram_step(step, payload):
        step_payload = dict(payload)
        step_payload.setdefault("user_id", "@admin:neurosys.local")
        if step == "phone":
            phone_number = step_payload.get("phone_number") or step_payload.get("phone")
            if not phone_number:
                return {"ok": False, "status": 400, "error": "phone_number is required"}
            step_payload["phone_number"] = phone_number

        result = request_candidates(
            "telegram",
            "POST",
            [
                "/v3/login/" + step,
                "/v2/login/" + step,
                "/v1/login/" + step,
                "/login/" + step,
            ],
            payload=step_payload,
        )
        if not result["ok"]:
            return {
                "ok": False,
                "status": result.get("status", 502),
                "error": result.get("error", "telegram provisioning step failed"),
                "errors": result.get("errors", []),
            }

        data = result.get("data", {})
        return {
            "ok": True,
            "status": result.get("status", 200),
            "raw": data,
            "session_id": first_value(data, ["session_id", "login_id"]),
            "login_id": first_value(data, ["login_id", "session_id"]),
            "token": first_value(data, ["token", "txn_id"]),
            "phone_number": first_value(data, ["phone_number", "phone"]),
            "state": first_value(data, ["state", "status"]),
        }


    def proxy_login_request(bridge, method, tail, query_string, payload):
        endpoint = "/login"
        if tail:
            endpoint = endpoint + "/" + tail
        result = bridge_request(bridge, method, endpoint, payload, query_string)
        if not result["ok"]:
            return {
                "ok": False,
                "status": result.get("status", 502),
                "error": result.get("error", "provisioning request failed"),
                "raw": result.get("data", {}),
            }
        return {"ok": True, "status": result.get("status", 200), "raw": result.get("data", {})}


    class Handler(http.server.BaseHTTPRequestHandler):
        def log_message(self, fmt, *args):
            pass

        def send_json(self, data, status=200):
            body = json.dumps(data).encode()
            self.send_response(status)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def parse_bridge_path(self):
            parsed = urllib.parse.urlparse(self.path)
            parts = [p for p in parsed.path.split("/") if p]
            if len(parts) < 4:
                return None
            if parts[0] != "api" or parts[1] != "bridge":
                return None
            bridge = parts[2]
            if bridge not in BRIDGE_BASE_URLS:
                return None
            if parts[3] != "login":
                return None
            tail = "/".join(parts[4:])
            return {
                "bridge": bridge,
                "tail": tail,
                "query": parsed.query,
            }

        def read_json_body(self):
            length = int(self.headers.get("Content-Length", 0))
            if length <= 0:
                return {}
            body = self.rfile.read(length)
            try:
                return json.loads(body)
            except json.JSONDecodeError:
                return None

        def do_GET(self):
            if self.path == "/":
                with open(HTML_FILE, "rb") as f:
                    content = f.read()
                self.send_response(200)
                self.send_header("Content-Type", "text/html; charset=utf-8")
                self.send_header("Content-Length", str(len(content)))
                self.end_headers()
                self.wfile.write(content)
                return

            parsed = self.parse_bridge_path()
            if not parsed:
                self.send_error(404)
                return

            result = proxy_login_request(
                parsed["bridge"],
                "GET",
                parsed["tail"],
                parsed["query"],
                None,
            )
            self.send_json(result, result.get("status", 200))

        def do_POST(self):
            parsed = self.parse_bridge_path()
            if not parsed:
                self.send_error(404)
                return

            payload = self.read_json_body()
            if payload is None:
                self.send_json({"ok": False, "error": "invalid JSON body"}, 400)
                return

            bridge = parsed["bridge"]
            tail = parsed["tail"]

            if bridge in ["signal", "whatsapp"] and tail == "start":
                result = start_qr_login(bridge, payload)
            elif bridge in ["signal", "whatsapp"] and tail == "wait":
                result = wait_qr_login(bridge, payload)
            elif bridge == "telegram" and tail in ["phone", "code", "password"]:
                result = telegram_step(tail, payload)
            else:
                result = proxy_login_request(
                    bridge,
                    "POST",
                    tail,
                    parsed["query"],
                    payload,
                )

            self.send_json(result, result.get("status", 200))


    class ReusableServer(socketserver.TCPServer):
        allow_reuse_address = True


    if __name__ == "__main__":
        with ReusableServer(("0.0.0.0", PORT), Handler) as httpd:
            print(f"DM guide server on port {PORT}")
            httpd.serve_forever()
    '';

in {
  sops.secrets."dm-provisioning-secret" = {
    sopsFile = lib.mkDefault ../secrets/neurosys.yaml;
  };

  systemd.services.dm-guide = {
    description = "DM Guide — Matrix bridge pairing page";
    after = [
      "network.target"
      "mautrix-telegram.service"
      "mautrix-whatsapp.service"
      "mautrix-signal.service"
    ];
    wants = [
      "mautrix-telegram.service"
      "mautrix-whatsapp.service"
      "mautrix-signal.service"
    ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      ExecStart = "${dmGuideServer}/bin/dm-guide-server";
      DynamicUser = true;
      StateDirectory = "dm-guide";
      LoadCredential = [ "dm-provisioning-secret:${config.sops.secrets."dm-provisioning-secret".path}" ];
      Restart = "on-failure";
      RestartSec = 5;
      # Hardening
      NoNewPrivileges = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      ProtectKernelTunables = true;
      ProtectKernelModules = true;
      ProtectControlGroups = true;
      RestrictSUIDSGID = true;
      PrivateDevices = true;
      PrivateTmp = true;
    };
  };
}
