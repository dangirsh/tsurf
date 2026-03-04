# modules/dashboard.nix
# @decision DASH-01: Custom NixOS option namespace for dashboard entries.
# @rationale: Each module self-describes via services.dashboard.entries.
#   NixOS module system merges attrsOf across public + private overlays.
#   No disabledModules needed — private modules just add entries.
#
# @decision DASH-02: Build-time JSON manifest via builtins.toJSON.
# @rationale: Manifest represents declared config, not runtime state.
#   Reproducible, cached, testable via nix eval.
#
# @decision DASH-03: Single Python stdlib HTTP server (writePython3Bin).
# @rationale: Matches dm-guide.nix and restic-status-server patterns.
#   One process, one port, one systemd unit. No framework dependencies.
#
# @decision DASH-04: DynamicUser for the dashboard service.
# @rationale: Dashboard needs no persistent state and no secrets.
#   systemctl show is unprivileged. DynamicUser provides isolation.
#
# @decision DASH-05: Status via systemctl show (batch, <100ms).
# @rationale: Decision locked: systemd unit status only, no HTTP checks.
{ config, lib, pkgs, ... }:
let
  cfg = config.services.dashboard;

  entrySort = a: b:
    if a.order == b.order then a.name < b.name else a.order < b.order;

  entryList =
    lib.mapAttrsToList (id: entry: entry // { inherit id; })
      cfg.entries;

  groupedEntries =
    builtins.groupBy (entry: entry.module)
      (builtins.sort entrySort entryList);

  # Parse extra manifests, extract modules per remote host
  extraHosts = builtins.mapAttrs (hostName: jsonStr:
    let
      parsed = builtins.fromJSON jsonStr;
      hostData =
        if parsed ? hosts
        then parsed.hosts.${hostName} or {}
        else {};
    in {
      modules = hostData.modules or (parsed.modules or {});
    }
  ) cfg.extraManifests;

  manifestJson = builtins.toJSON {
    primary = config.networking.hostName;
    hosts = extraHosts // {
      ${config.networking.hostName} = {
        modules = groupedEntries;
      };
    };
  };

  dashboardHtml = pkgs.writeText "dashboard.html" ''
    <!doctype html>
    <html lang="en">
      <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>Neurosys</title>
        <style>
          :root {
            color-scheme: dark;
            --bg: #1a1a2e;
            --panel: #232340;
            --panel-alt: #2c2c4d;
            --text: #f1f2f8;
            --muted: #a3a8c0;
            --border: #3c3f66;
            --ok: #33d17a;
            --warn: #f8e45c;
            --bad: #ff6b6b;
            --unknown: #8b8fa8;
          }

          * {
            box-sizing: border-box;
          }

          body {
            margin: 0;
            font-family: "Iosevka Aile", "JetBrains Mono", monospace;
            background: radial-gradient(circle at top, #24244a, var(--bg));
            color: var(--text);
            min-height: 100vh;
          }

          main {
            max-width: 980px;
            margin: 0 auto;
            padding: 2rem 1rem 3rem;
          }

          h1 {
            margin: 0 0 0.5rem;
            font-size: 1.8rem;
          }

          .subtitle {
            color: var(--muted);
            margin-bottom: 1rem;
          }

          .filters {
            display: flex;
            gap: 0.6rem;
            margin-bottom: 1.2rem;
            align-items: center;
          }

          .search-input {
            flex: 1;
            padding: 0.55rem 0.8rem;
            border: 1px solid var(--border);
            border-radius: 8px;
            background: var(--panel);
            color: var(--text);
            font: inherit;
            font-size: 0.95rem;
            outline: none;
          }

          .search-input:focus {
            border-color: #8ad8ff;
          }

          .search-input::placeholder {
            color: var(--muted);
          }

          .filter-btn {
            padding: 0.55rem 0.9rem;
            border: 1px solid var(--border);
            border-radius: 8px;
            background: var(--panel);
            color: var(--muted);
            font: inherit;
            font-size: 0.9rem;
            cursor: pointer;
            white-space: nowrap;
            transition: all 0.15s ease;
          }

          .filter-btn:hover {
            border-color: var(--bad);
            color: var(--text);
          }

          .filter-btn.active {
            background: rgba(255, 107, 107, 0.15);
            border-color: var(--bad);
            color: var(--bad);
          }

          .hidden {
            display: none !important;
          }

          .match-count {
            color: var(--muted);
            font-size: 0.85rem;
            white-space: nowrap;
          }

          .host-badge {
            font-size: 0.7rem;
            padding: 0.05rem 0.35rem;
            border-radius: 3px;
            margin-left: 0.3rem;
            font-weight: 400;
            vertical-align: middle;
          }

          .host-local {
            background: rgba(138, 216, 255, 0.12);
            color: #8ad8ff;
          }

          .host-remote {
            background: rgba(163, 168, 192, 0.12);
            color: var(--muted);
          }

          .module-group {
            border: 1px solid var(--border);
            border-radius: 10px;
            background: rgba(35, 35, 64, 0.85);
            margin-bottom: 1rem;
            overflow: hidden;
          }

          .module-group > summary {
            cursor: pointer;
            padding: 0.85rem 1rem;
            list-style: none;
            font-weight: 700;
            background: rgba(44, 44, 77, 0.95);
          }

          .module-group > summary::-webkit-details-marker {
            display: none;
          }

          .entries {
            padding: 0.4rem 0.75rem 0.75rem;
          }

          .entry {
            border: 1px solid var(--border);
            border-radius: 8px;
            background: var(--panel);
            margin-top: 0.5rem;
            overflow: hidden;
          }

          .entry-btn {
            width: 100%;
            border: 0;
            background: transparent;
            color: inherit;
            cursor: pointer;
            text-align: left;
            padding: 0.7rem 0.8rem;
            display: flex;
            align-items: center;
            justify-content: space-between;
            gap: 0.7rem;
            font: inherit;
          }

          .entry-title {
            display: flex;
            align-items: center;
            gap: 0.55rem;
            min-width: 0;
          }

          .entry-name {
            font-weight: 600;
          }

          .entry-desc {
            color: var(--muted);
            margin-left: 0.35rem;
            font-size: 0.9rem;
          }

          .entry-arrow {
            color: var(--muted);
            transition: transform 0.15s ease;
          }

          .entry.open .entry-arrow {
            transform: rotate(90deg);
          }

          .status-dot {
            width: 0.68rem;
            height: 0.68rem;
            border-radius: 50%;
            flex: 0 0 auto;
            background: var(--unknown);
            box-shadow: 0 0 0 2px rgba(0, 0, 0, 0.2);
          }

          .status-ok {
            background: var(--ok);
          }

          .status-warn {
            background: var(--warn);
          }

          .status-bad {
            background: var(--bad);
          }

          .status-unknown {
            background: var(--unknown);
          }

          .details {
            display: none;
            padding: 0 0.8rem 0.8rem 2rem;
            font-size: 0.93rem;
            color: var(--muted);
          }

          .entry.open .details {
            display: block;
          }

          .details dl {
            display: grid;
            grid-template-columns: 6rem 1fr;
            gap: 0.35rem 0.8rem;
            margin: 0;
          }

          .details dt {
            color: var(--text);
            font-weight: 600;
          }

          .details dd {
            margin: 0;
            word-break: break-word;
          }

          a {
            color: #8ad8ff;
          }

          .footer {
            margin-top: 1.5rem;
            color: var(--muted);
            font-size: 0.85rem;
          }
        </style>
      </head>
      <body>
        <main>
          <h1>Neurosys</h1>
          <div id="subtitle" class="subtitle">Loading manifest...</div>
          <div class="filters">
            <input type="text" id="search" class="search-input"
              placeholder="Filter services..." autocomplete="off">
            <button type="button" id="failingBtn" class="filter-btn"
              >Failing</button>
            <span id="matchCount" class="match-count"></span>
          </div>
          <div id="tree"></div>
          <div class="footer">Status refresh: every 10 seconds</div>
        </main>
        <script>
          let currentManifest = null;
          const statusByUnit = {};

          function statusClass(active, sub, external, local) {
            if (external || local === false) {
              return "status-unknown";
            }

            if (!active) {
              return "status-unknown";
            }

            if (active === "active" &&
                (sub === "running" || sub === "waiting" || sub === "exited")) {
              return "status-ok";
            }

            if (
              active === "activating" ||
              active === "reloading" ||
              sub === "activating" ||
              sub === "reloading"
            ) {
              return "status-warn";
            }

            if (
              active === "failed" ||
              active === "inactive" ||
              active === "deactivating"
            ) {
              return "status-bad";
            }

            return "status-unknown";
          }

          function statusText(entry, state) {
            if (entry.external) {
              return "external service";
            }

            if (!entry.isLocal) {
              return "remote";
            }

            if (!entry.systemdUnit) {
              return "no systemd unit";
            }

            if (!state) {
              return "unknown";
            }

            return state.active + "/" + state.sub;
          }

          function makeDetailRow(label, value, cls) {
            if (!value && value !== 0) {
              return "";
            }
            var ddAttr = cls ? ' class="' + cls + '"' : "";
            return "<dt>" + label + "</dt><dd" + ddAttr + ">" + value + "</dd>";
          }

          function renderTree() {
            if (!currentManifest) {
              return;
            }

            const tree = document.getElementById("tree");
            tree.innerHTML = "";

            const primary = currentManifest.primary || "";
            const hosts = currentManifest.hosts || {};
            const hostNames = Object.keys(hosts);
            const multiHost = hostNames.length > 1;

            const byModule = {};
            hostNames.forEach((hostName) => {
              const modules = hosts[hostName].modules || {};
              Object.keys(modules).forEach((modName) => {
                if (!byModule[modName]) byModule[modName] = [];
                modules[modName].forEach((entry) => {
                  byModule[modName].push(
                    Object.assign({}, entry, {
                      host: hostName,
                      isLocal: hostName === primary,
                    })
                  );
                });
              });
            });

            const names = Object.keys(byModule).sort();

            names.forEach((moduleName) => {
              const moduleWrap = document.createElement("details");
              moduleWrap.className = "module-group";
              moduleWrap.open = true;

              const summary = document.createElement("summary");
              summary.textContent = moduleName;
              moduleWrap.appendChild(summary);

              const entriesWrap = document.createElement("div");
              entriesWrap.className = "entries";

              byModule[moduleName].forEach((entry) => {
                const row = document.createElement("div");
                row.className = "entry";
                row.dataset.entryId = entry.id;
                row.dataset.host = entry.host;

                const button = document.createElement("button");
                button.className = "entry-btn";
                button.type = "button";

                const title = document.createElement("div");
                title.className = "entry-title";

                const dot = document.createElement("span");
                dot.className = "status-dot status-unknown";
                dot.dataset.unit = entry.systemdUnit || "";
                dot.dataset.external = entry.external ? "1" : "0";
                dot.dataset.local = entry.isLocal ? "1" : "0";

                const name = document.createElement("span");
                name.className = "entry-name";
                name.textContent = entry.name;

                title.appendChild(dot);
                title.appendChild(name);

                if (multiHost) {
                  const badge = document.createElement("span");
                  badge.className = "host-badge " +
                    (entry.isLocal ? "host-local" : "host-remote");
                  badge.textContent = entry.host;
                  title.appendChild(badge);
                }

                if (entry.description) {
                  const desc = document.createElement("span");
                  desc.className = "entry-desc";
                  desc.textContent = entry.description;
                  title.appendChild(desc);
                }

                const arrow = document.createElement("span");
                arrow.className = "entry-arrow";
                arrow.textContent = ">";

                button.appendChild(title);
                button.appendChild(arrow);
                row.appendChild(button);

                const details = document.createElement("div");
                details.className = "details";
                details.dataset.status =
                  entry.systemdUnit || entry.id;

                const link = entry.url
                  ? "<a href=\"" + entry.url + "\" target=\"_blank\" " +
                    "rel=\"noreferrer\">open</a>"
                  : "";

                details.innerHTML =
                  "<dl>" +
                  makeDetailRow("Host", entry.host) +
                  makeDetailRow("Port", entry.port) +
                  makeDetailRow("Unit", entry.systemdUnit) +
                  makeDetailRow("Status", "loading...", "status-val") +
                  makeDetailRow("URL", link) +
                  "</dl>";

                row.appendChild(details);

                button.addEventListener("click", () => {
                  row.classList.toggle("open");
                });

                entriesWrap.appendChild(row);
              });

              moduleWrap.appendChild(entriesWrap);
              tree.appendChild(moduleWrap);
            });

            updateStatusUi();
          }

          function updateStatusUi() {
            if (!currentManifest) {
              return;
            }

            const dots = document.querySelectorAll(".status-dot");
            dots.forEach((dot) => {
              const unit = dot.dataset.unit;
              const external = dot.dataset.external === "1";
              const local = dot.dataset.local === "1";
              const state = unit ? statusByUnit[unit] : null;
              const active = state ? state.active : null;
              const sub = state ? state.sub : null;
              dot.className = "status-dot " +
                statusClass(active, sub, external, local);
            });

            const statusCells = document.querySelectorAll(".details");
            statusCells.forEach((details) => {
              const parent = details.closest(".entry");
              if (!parent) {
                return;
              }
              const dot = parent.querySelector(".status-dot");
              const unit = dot ? dot.dataset.unit : "";
              const external = dot
                ? dot.dataset.external === "1" : false;
              const local = dot
                ? dot.dataset.local === "1" : true;
              const text = statusText(
                {
                  external: external,
                  systemdUnit: unit,
                  isLocal: local,
                },
                unit ? statusByUnit[unit] : null
              );
              const cell = details.querySelector("dd.status-val");
              if (cell) {
                cell.textContent = text;
              }
            });
          }

          async function fetchManifest() {
            const response = await fetch("/manifest.json");
            if (!response.ok) {
              throw new Error("manifest fetch failed");
            }
            currentManifest = await response.json();
            const hosts = Object.keys(
              currentManifest.hosts || {}
            );
            document.getElementById("subtitle").textContent =
              hosts.join(" + ");
            renderTree();
          }

          async function fetchStatus() {
            const response = await fetch("/api/status");
            if (!response.ok) {
              return;
            }
            const data = await response.json();
            const units = data.units || {};
            Object.keys(units).forEach((name) => {
              statusByUnit[name] = units[name];
            });
            updateStatusUi();
          }

          async function run() {
            try {
              await fetchManifest();
              await fetchStatus();
              setInterval(fetchStatus, 10000);
            } catch (error) {
              document.getElementById("subtitle").textContent =
                "Failed to load dashboard data";
            }
          }

          run();

          let failingOnly = false;
          const searchEl = document.getElementById("search");
          const failBtn = document.getElementById("failingBtn");
          const countEl = document.getElementById("matchCount");

          function applyFilters() {
            const query = searchEl.value.toLowerCase().trim();
            const entries = document.querySelectorAll(".entry");
            let visible = 0;
            let total = entries.length;

            entries.forEach((entry) => {
              const btn = entry.querySelector(".entry-btn");
              const name = btn ? btn.textContent.toLowerCase() : "";
              const matchesText = !query || name.indexOf(query) !== -1;

              let matchesFailing = true;
              if (failingOnly) {
                const dot = entry.querySelector(".status-dot");
                if (dot) {
                  const cls = dot.className;
                  matchesFailing = cls.indexOf("status-bad") !== -1
                    || cls.indexOf("status-warn") !== -1;
                } else {
                  matchesFailing = false;
                }
              }

              const show = matchesText && matchesFailing;
              entry.classList.toggle("hidden", !show);
              if (show) visible++;
            });

            document.querySelectorAll(".module-group").forEach((group) => {
              const visEntries = group.querySelectorAll(
                ".entry:not(.hidden)"
              );
              group.classList.toggle("hidden", visEntries.length === 0);
            });

            if (query || failingOnly) {
              countEl.textContent = visible + "/" + total;
            } else {
              countEl.textContent = "";
            }
          }

          searchEl.addEventListener("input", applyFilters);
          failBtn.addEventListener("click", () => {
            failingOnly = !failingOnly;
            failBtn.classList.toggle("active", failingOnly);
            applyFilters();
          });

          const origUpdate = updateStatusUi;
          updateStatusUi = function() {
            origUpdate();
            applyFilters();
          };
        </script>
      </body>
    </html>
  '';

  dashboardBin = pkgs.writers.writePython3Bin "nix-dashboard" { } ''
    import argparse
    import json
    import subprocess
    from http.server import BaseHTTPRequestHandler
    from http.server import ThreadingHTTPServer
    from pathlib import Path
    from urllib.parse import urlparse


    UNKNOWN = {"active": "unknown", "sub": "unknown"}


    def load_manifest(manifest_path):
        try:
            text = Path(manifest_path).read_text(
                encoding="utf-8"
            )
        except OSError:
            return {"primary": "unknown", "hosts": {}}

        try:
            return json.loads(text)
        except json.JSONDecodeError:
            return {"primary": "unknown", "hosts": {}}


    def collect_units(manifest):
        units = []
        primary = manifest.get("primary", "")
        hosts = manifest.get("hosts", {})
        host_data = hosts.get(primary, {})
        modules = host_data.get("modules", {})
        for entries in modules.values():
            for entry in entries:
                unit = entry.get("systemdUnit")
                if unit and unit not in units:
                    units.append(unit)
        return units


    def parse_status_blocks(stdout):
        statuses = {}
        current = {}
        lines = stdout.splitlines()
        lines.append("")
        for line in lines:
            if line.strip() == "":
                if current:
                    unit = current.get("Id")
                    if unit:
                        statuses[unit] = {
                            "active": current.get("ActiveState", "unknown"),
                            "sub": current.get("SubState", "unknown"),
                        }
                    current = {}
                continue
            if "=" not in line:
                continue
            key, value = line.split("=", 1)
            current[key] = value
        return statuses


    def query_status(units):
        if not units:
            return {}

        cmd = [
            "systemctl",
            "show",
            "--property=Id,ActiveState,SubState",
        ] + units
        try:
            result = subprocess.run(
                cmd,
                capture_output=True,
                text=True,
                timeout=5,
                check=False,
            )
        except (subprocess.SubprocessError, OSError):
            return {unit: dict(UNKNOWN) for unit in units}

        parsed = parse_status_blocks(result.stdout)
        return {unit: parsed.get(unit, dict(UNKNOWN)) for unit in units}


    def build_status_payload(manifest_path):
        manifest = load_manifest(manifest_path)
        units = collect_units(manifest)
        return {"units": query_status(units)}


    def read_html(html_path):
        try:
            return Path(html_path).read_bytes()
        except OSError:
            return b"<h1>Dashboard HTML missing</h1>"


    def make_handler(manifest_path, html_path):
        class Handler(BaseHTTPRequestHandler):
            def _send_bytes(self, payload, content_type, status=200):
                self.send_response(status)
                self.send_header("Content-Type", content_type)
                self.send_header("Content-Length", str(len(payload)))
                self.end_headers()
                self.wfile.write(payload)

            def _send_json(self, payload, status=200):
                data = json.dumps(payload).encode("utf-8")
                self._send_bytes(
                    data,
                    "application/json; charset=utf-8",
                    status=status,
                )

            def do_GET(self):
                route = urlparse(self.path).path
                if route == "/":
                    self._send_bytes(
                        read_html(html_path),
                        "text/html; charset=utf-8",
                    )
                    return
                if route == "/manifest.json":
                    self._send_json(load_manifest(manifest_path))
                    return
                if route == "/api/status":
                    self._send_json(build_status_payload(manifest_path))
                    return
                self._send_json({"error": "not_found"}, status=404)

            def log_message(self, format_text, *args):
                return

        return Handler


    def main():
        parser = argparse.ArgumentParser(description="nix dashboard server")
        parser.add_argument("--port", type=int, required=True)
        parser.add_argument("--manifest", required=True)
        parser.add_argument("--html", required=True)
        args = parser.parse_args()

        handler = make_handler(args.manifest, args.html)
        server = ThreadingHTTPServer(("0.0.0.0", args.port), handler)
        print("nix-dashboard listening on 0.0.0.0:%d" % args.port)
        server.serve_forever()


    if __name__ == "__main__":
        main()
  '';
in
{
  options.services.dashboard = {
    enable = lib.mkEnableOption "Nix-derived dynamic dashboard";

    listenPort = lib.mkOption {
      type = lib.types.port;
      default = 8082;
      description = "Port for the dashboard HTTP server";
    };

    entries = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule {
        options = {
          name = lib.mkOption {
            type = lib.types.str;
            description = "Display name";
          };
          module = lib.mkOption {
            type = lib.types.str;
            description = "Module filename used for grouping";
          };
          description = lib.mkOption {
            type = lib.types.str;
            default = "";
            description = "Short description";
          };
          port = lib.mkOption {
            type = lib.types.nullOr lib.types.port;
            default = null;
            description = "Optional listening port";
          };
          url = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = "Web URL for clickable links";
          };
          systemdUnit = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = "Systemd unit for status checks";
          };
          icon = lib.mkOption {
            type = lib.types.str;
            default = "";
            description = "Icon identifier or emoji";
          };
          external = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = "External service with no local unit";
          };
          order = lib.mkOption {
            type = lib.types.int;
            default = 50;
            description = "Sort order within module";
          };
        };
      });
      default = { };
      description = "Dashboard entries declared across modules";
    };

    extraManifests = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      description = "JSON manifests from remote hosts (hostname -> JSON text)";
    };
  };

  config = lib.mkMerge [
    {
      # Always generate manifest so other hosts can reference it
      # via services.dashboard.extraManifests
      environment.etc."dashboard/manifest.json".text = manifestJson;
    }
    (lib.mkIf cfg.enable {
    services.dashboard.entries.dashboard = lib.mkDefault {
      name = "Dashboard";
      module = "dashboard.nix";
      description = "This dashboard — Nix-derived service tree";
      port = cfg.listenPort;
      url = "http://${config.networking.hostName}:${toString cfg.listenPort}";
      systemdUnit = "nix-dashboard.service";
      icon = "dashboard";
      order = 99;
    };

    systemd.services.nix-dashboard = {
      description = "Nix-derived dynamic dashboard";
      wantedBy = [ "multi-user.target" ];
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ];

      serviceConfig = {
        ExecStart =
          "${dashboardBin}/bin/nix-dashboard --port "
          + "${toString cfg.listenPort} --manifest "
          + "/etc/dashboard/manifest.json --html ${dashboardHtml}";
        DynamicUser = true;
        Restart = "on-failure";
        RestartSec = "5s";
        ProtectHome = true;
        PrivateTmp = true;
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectClock = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectKernelLogs = true;
        ProtectControlGroups = true;
        RestrictAddressFamilies = [ "AF_INET" "AF_INET6" "AF_UNIX" ];
        RestrictNamespaces = true;
        LockPersonality = true;
        MemoryDenyWriteExecute = true;
        CapabilityBoundingSet = "";
      };
    };
    })
  ];
}
