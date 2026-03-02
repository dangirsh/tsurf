# modules/sun-schedule.nix
# Sun Schedule — circadian light schedule editor for Hue lights via Home Assistant
#
# @decision SUN-01: Standalone Python HTTP service (stdlib only, no Flask).
# @rationale: Minimal dependency surface. pkgs.writers.writePython3Bin enforces
#   flake8 style. Single-page HTML served inline — no static file complexity.
#
# @decision SUN-02: Automations managed via HA REST API, not file-based YAML.
# @rationale: Decoupled from the existing config-repo automations. HA stores
#   API-created automations in .storage/ separately. No git repo modification needed.
#
# @decision SUN-03: Config persisted as JSON in /var/lib/sun-schedule/config.json.
# @rationale: Service can restart without losing schedule. JSON is trivially
#   read/written from Python stdlib and the browser.
#
# Security model:
# - Port 8085 listens on 0.0.0.0 (Tailscale-only via trustedInterfaces, same as HA).
# - HA token read from sops secret file at runtime — never in Nix store or CLI args.
# - openFirewall = false (standard pattern).
{ config, pkgs, lib, ... }:

let
  port = 8085;

  defaultConfig = builtins.toJSON {
    entries = [
      { time = "05:00"; color_temp = 6500; brightness = 100; fade_minutes = 30; label = "Full"; }
      { time = "06:00"; color_temp = 3500; brightness = 60; fade_minutes = 30; label = "Wake"; }
      { time = "08:00"; color_temp = 5000; brightness = 80; fade_minutes = 30; label = "Morning"; }
      { time = "12:00"; color_temp = 6500; brightness = 100; fade_minutes = 30; label = "Noon"; }
      { time = "17:00"; color_temp = 4500; brightness = 80; fade_minutes = 30; label = "Afternoon"; }
      { time = "20:00"; color_temp = 3000; brightness = 50; fade_minutes = 45; label = "Evening"; }
      { time = "22:00"; color_temp = 2000; brightness = 10; fade_minutes = 30; label = "Night"; }
    ];
    target_entities = [];
  };

  htmlPage = pkgs.writeText "sun-schedule.html" ''
    <!DOCTYPE html>
    <html lang="en">
    <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>Sun Schedule</title>
    <style>
    :root { --bg: #1a1a2e; --surface: #16213e; --border: #0f3460; --text: #e0e0e0; --accent: #e94560; --ok: #4ecca3; }
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; background: var(--bg); color: var(--text); padding: 1.5rem; max-width: 900px; margin: 0 auto; }
    h1 { font-size: 1.5rem; margin-bottom: 1rem; color: var(--ok); }
    table { width: 100%; border-collapse: collapse; margin-bottom: 1rem; }
    th, td { padding: 0.5rem; text-align: left; border-bottom: 1px solid var(--border); }
    th { color: var(--accent); font-size: 0.85rem; text-transform: uppercase; }
    input[type="time"], input[type="number"], input[type="text"] {
      background: var(--surface); color: var(--text); border: 1px solid var(--border);
      padding: 0.4rem; border-radius: 4px; width: 100%;
    }
    input[type="range"] { width: 100%; accent-color: var(--accent); }
    select { background: var(--surface); color: var(--text); border: 1px solid var(--border); padding: 0.4rem; border-radius: 4px; width: 100%; }
    select[multiple] { height: 120px; }
    button { padding: 0.5rem 1.2rem; border: none; border-radius: 4px; cursor: pointer; font-size: 0.9rem; }
    .btn-add { background: var(--border); color: var(--text); margin-right: 0.5rem; }
    .btn-save { background: var(--ok); color: var(--bg); font-weight: bold; }
    .btn-del { background: var(--accent); color: white; padding: 0.3rem 0.6rem; font-size: 0.8rem; }
    .controls { display: flex; align-items: center; gap: 0.5rem; margin-bottom: 1rem; }
    .status { margin-left: auto; font-size: 0.85rem; }
    .status.ok { color: var(--ok); }
    .status.err { color: var(--accent); }
    .range-wrap { display: flex; align-items: center; gap: 0.5rem; }
    .range-wrap span { min-width: 3.5rem; text-align: right; font-size: 0.85rem; }
    .section { margin-bottom: 1.5rem; }
    label { display: block; margin-bottom: 0.3rem; font-size: 0.85rem; color: var(--accent); }
    </style>
    </head>
    <body>
    <h1>Sun Schedule</h1>

    <div class="section">
      <label for="lights">Target lights / groups</label>
      <select id="lights" multiple></select>
    </div>

    <table>
      <thead>
        <tr>
          <th>Label</th>
          <th>Time</th>
          <th>Color Temp</th>
          <th>Brightness</th>
          <th>Fade</th>
          <th></th>
        </tr>
      </thead>
      <tbody id="entries"></tbody>
    </table>

    <div class="controls">
      <button class="btn-add" onclick="addEntry()">+ Add Entry</button>
      <button class="btn-save" onclick="save()">Save &amp; Apply</button>
      <span id="status" class="status"></span>
    </div>

    <script>
    let config = {entries: [], target_entities: []};

    function renderEntry(e, i) {
      return '<tr>'
        + '<td><input type="text" value="' + esc(e.label) + '" onchange="upd(' + i + ',\'label\',this.value)"></td>'
        + '<td><input type="time" value="' + esc(e.time) + '" onchange="upd(' + i + ',\'time\',this.value)"></td>'
        + '<td><div class="range-wrap"><input type="range" min="2000" max="6500" step="100" value="' + e.color_temp + '" oninput="upd(' + i + ',\'color_temp\',+this.value);this.nextElementSibling.textContent=this.value+\' K\'"><span>' + e.color_temp + ' K</span></div></td>'
        + '<td><div class="range-wrap"><input type="range" min="0" max="100" value="' + e.brightness + '" oninput="upd(' + i + ',\'brightness\',+this.value);this.nextElementSibling.textContent=this.value+\' %\'"><span>' + e.brightness + ' %</span></div></td>'
        + '<td><input type="number" min="1" max="120" value="' + e.fade_minutes + '" onchange="upd(' + i + ',\'fade_minutes\',+this.value)" style="width:60px"> min</td>'
        + '<td><button class="btn-del" onclick="del(' + i + ')">X</button></td>'
        + '</tr>';
    }

    function esc(s) { return String(s).replace(/&/g,'&amp;').replace(/"/g,'&quot;').replace(/</g,'&lt;'); }

    function render() {
      document.getElementById('entries').innerHTML = config.entries.map(renderEntry).join("");
      var sel = document.getElementById('lights');
      for (var i = 0; i < sel.options.length; i++) {
        sel.options[i].selected = config.target_entities.indexOf(sel.options[i].value) >= 0;
      }
    }

    function upd(i, k, v) { config.entries[i][k] = v; }

    function del(i) { config.entries.splice(i, 1); render(); }

    function addEntry() {
      config.entries.push({time: '12:00', color_temp: 4000, brightness: 50, fade_minutes: 30, label: 'New'});
      render();
    }

    function save() {
      var sel = document.getElementById('lights');
      config.target_entities = [];
      for (var i = 0; i < sel.options.length; i++) {
        if (sel.options[i].selected) config.target_entities.push(sel.options[i].value);
      }
      var st = document.getElementById('status');
      st.textContent = 'Saving...';
      st.className = 'status';
      fetch('/api/config', {method: 'POST', headers: {'Content-Type': 'application/json'}, body: JSON.stringify(config)})
        .then(function(r) { return r.json(); })
        .then(function(d) {
          if (d.ok) { st.textContent = 'Saved + applied'; st.className = 'status ok'; }
          else { st.textContent = 'Error: ' + (d.error || 'unknown'); st.className = 'status err'; }
        })
        .catch(function(e) { st.textContent = 'Error: ' + e; st.className = 'status err'; });
    }

    fetch('/api/lights').then(function(r){return r.json();}).then(function(lights) {
      var sel = document.getElementById('lights');
      lights.forEach(function(l) {
        var opt = document.createElement('option');
        opt.value = l.entity_id;
        opt.textContent = l.name + ' (' + l.entity_id + ')';
        sel.appendChild(opt);
      });
      return fetch('/api/config');
    }).then(function(r){return r.json();}).then(function(c) {
      config = c;
      render();
    });
    </script>
    </body>
    </html>
  '';

  sunScheduleServer = pkgs.writers.writePython3Bin "sun-schedule-server"
    {
      flakeIgnore = [ "E501" ];
    }
    ''
    import http.server
    import json
    import os
    import socketserver
    import urllib.request
    import urllib.error

    PORT = ${toString port}
    DATA_DIR = "/var/lib/sun-schedule"
    CONFIG_FILE = os.path.join(DATA_DIR, "config.json")
    HTML_FILE = "${htmlPage}"
    HA_URL = "http://127.0.0.1:8123"
    CREDS_DIR = os.environ.get("CREDENTIALS_DIRECTORY", "/run/secrets")
    TOKEN_FILE = os.path.join(CREDS_DIR, "ha-token")

    DEFAULT_CONFIG = json.loads(r"""${defaultConfig}""")


    def read_token():
        try:
            with open(TOKEN_FILE) as f:
                return f.read().strip()
        except FileNotFoundError:
            return ""


    def load_config():
        if os.path.exists(CONFIG_FILE):
            with open(CONFIG_FILE) as f:
                return json.load(f)
        return dict(DEFAULT_CONFIG)


    def save_config(cfg):
        os.makedirs(DATA_DIR, exist_ok=True)
        with open(CONFIG_FILE, "w") as f:
            json.dump(cfg, f, indent=2)


    def ha_request(method, path, data=None):
        token = read_token()
        url = HA_URL + path
        body = json.dumps(data).encode() if data else None
        req = urllib.request.Request(url, data=body, method=method)
        req.add_header("Authorization", "Bearer " + token)
        req.add_header("Content-Type", "application/json")
        try:
            with urllib.request.urlopen(req, timeout=10) as resp:
                return json.loads(resp.read().decode())
        except urllib.error.HTTPError as e:
            return {"error": f"HA API {e.code}: {e.reason}"}
        except Exception as e:
            return {"error": str(e)}


    def get_lights():
        states = ha_request("GET", "/api/states")
        if isinstance(states, dict) and "error" in states:
            return []
        lights = []
        for s in states:
            eid = s.get("entity_id", "")
            if eid.startswith("light."):
                name = s.get("attributes", {}).get("friendly_name", eid)
                lights.append({"entity_id": eid, "name": name})
        lights.sort(key=lambda x: x["name"])
        return lights


    def delete_sun_automations():
        automations = ha_request("GET", "/api/states")
        if isinstance(automations, dict) and "error" in automations:
            return
        for s in automations:
            eid = s.get("entity_id", "")
            if eid.startswith("automation.sun_schedule_"):
                uid = s.get("attributes", {}).get("id", "")
                if uid:
                    ha_request("DELETE", f"/api/config/automation/config/{uid}")


    def push_automations(cfg):
        delete_sun_automations()
        errors = []
        entities = cfg.get("target_entities", [])
        if not entities:
            return errors
        for i, entry in enumerate(cfg.get("entries", [])):
            label = entry.get("label", f"Step {i}")
            auto_id = f"sun_schedule_{i:02d}_{label.lower().replace(' ', '_')}"
            transition_secs = entry.get("fade_minutes", 30) * 60
            automation = {
                "alias": f"Sun Schedule: {label}",
                "description": f"Circadian schedule step: {label}",
                "trigger": [{"platform": "time", "at": entry["time"] + ":00"}],
                "action": [{
                    "service": "light.turn_on",
                    "target": {"entity_id": entities},
                    "data": {
                        "color_temp_kelvin": entry["color_temp"],
                        "brightness_pct": entry["brightness"],
                        "transition": transition_secs,
                    },
                }],
                "mode": "single",
            }
            result = ha_request("PUT", f"/api/config/automation/config/{auto_id}", automation)
            if isinstance(result, dict) and "error" in result:
                errors.append(f"{label}: {result['error']}")
        return errors


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

        def do_GET(self):
            if self.path == "/":
                with open(HTML_FILE, "rb") as f:
                    content = f.read()
                self.send_response(200)
                self.send_header("Content-Type", "text/html; charset=utf-8")
                self.send_header("Content-Length", str(len(content)))
                self.end_headers()
                self.wfile.write(content)
            elif self.path == "/api/config":
                self.send_json(load_config())
            elif self.path == "/api/lights":
                self.send_json(get_lights())
            else:
                self.send_error(404)

        def do_POST(self):
            if self.path == "/api/config":
                length = int(self.headers.get("Content-Length", 0))
                body = self.rfile.read(length)
                try:
                    cfg = json.loads(body)
                except json.JSONDecodeError:
                    self.send_json({"ok": False, "error": "invalid JSON"}, 400)
                    return
                save_config(cfg)
                errors = push_automations(cfg)
                if errors:
                    self.send_json({"ok": False, "error": "; ".join(errors)})
                else:
                    self.send_json({"ok": True})
            else:
                self.send_error(404)


    class ReusableServer(socketserver.TCPServer):
        allow_reuse_address = True


    if __name__ == "__main__":
        with ReusableServer(("0.0.0.0", PORT), Handler) as httpd:
            print(f"Sun Schedule server on port {PORT}")
            httpd.serve_forever()
    '';

in {
  # @decision SUN-04: ha-token owned by root, passed to service via LoadCredential.
  # @rationale: The hass user only exists when home-assistant.nix is imported (private overlay).
  #   LoadCredential lets systemd read the root-owned secret and pass it to the DynamicUser.
  sops.secrets."ha-token" = {};

  systemd.services.sun-schedule = {
    description = "Sun Schedule — circadian light schedule editor";
    after = [ "network.target" "home-assistant.service" ];
    wants = [ "home-assistant.service" ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      ExecStart = "${sunScheduleServer}/bin/sun-schedule-server";
      DynamicUser = true;
      StateDirectory = "sun-schedule";
      LoadCredential = [ "ha-token:${config.sops.secrets."ha-token".path}" ];
      Restart = "on-failure";
      RestartSec = 5;
      # Hardening
      NoNewPrivileges = true;
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
