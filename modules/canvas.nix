# modules/canvas.nix
# @decision CANVAS-01: Agent Canvas server uses writePython3Bin with stdlib only.
# @rationale: Keeps dependency surface minimal while preserving reproducible
# packaging and flake8 enforcement during evaluation.
#
# @decision CANVAS-02: Service runs with DynamicUser and StateDirectory.
# @rationale: Persistent panel storage stays under /var/lib/agent-canvas while
# the runtime account remains ephemeral and tightly sandboxed.
#
# @decision CANVAS-03: No application auth in this module.
# @rationale: Access control is network-layer only (internal-only/Tailscale),
# consistent with existing internal dashboards and tools.
{ config, lib, pkgs, ... }:
let
  cfg = config.services.agentCanvas;

  canvasServer = pkgs.writers.writePython3Bin "agent-canvas" { } ''
    import argparse
    import datetime
    import json
    import os
    import pathlib
    import queue
    import re
    import threading
    import time
    import uuid

    from http.server import BaseHTTPRequestHandler
    from http.server import ThreadingHTTPServer


    MAX_BODY_SIZE = 1024 * 1024
    PANEL_PATH_RE = re.compile(r"^/api/panels/([^/]+)$")
    PANEL_DATA_PATH_RE = re.compile(r"^/api/panels/([^/]+)/data$")


    def utc_now_iso():
        now = datetime.datetime.now(datetime.UTC)
        return now.replace(microsecond=0).isoformat().replace("+00:00", "Z")


    def make_panel_id():
        millis = int(time.time() * 1000)
        return "p-%d-%s" % (millis, uuid.uuid4().hex[:8])


    def clamp_int(value, field):
        if not isinstance(value, int):
            raise ValueError("%s must be an integer" % field)
        return value


    def validate_grid(grid):
        if not isinstance(grid, dict):
            raise ValueError("grid must be an object")

        x = clamp_int(grid.get("x"), "grid.x")
        y = clamp_int(grid.get("y"), "grid.y")
        w = clamp_int(grid.get("w"), "grid.w")
        h = clamp_int(grid.get("h"), "grid.h")

        if x < 0 or x > 11:
            raise ValueError("grid.x must be between 0 and 11")
        if y < 0:
            raise ValueError("grid.y must be >= 0")
        if w < 1 or w > 12:
            raise ValueError("grid.w must be between 1 and 12")
        if h < 1 or h > 20:
            raise ValueError("grid.h must be between 1 and 20")

        return {"x": x, "y": y, "w": w, "h": h}


    def default_grid():
        return {"x": 0, "y": 0, "w": 6, "h": 4}


    class PanelStore:
        def __init__(self, data_dir):
            self._dir = pathlib.Path(data_dir)
            self._path = self._dir / "panels.json"
            self._lock = threading.Lock()
            self._panels = {}
            self._dir.mkdir(parents=True, exist_ok=True)
            self._load()

        def _load(self):
            if not self._path.exists():
                self._panels = {}
                return

            try:
                content = self._path.read_text(encoding="utf-8")
                payload = json.loads(content)
            except (OSError, json.JSONDecodeError):
                self._panels = {}
                return

            if not isinstance(payload, list):
                self._panels = {}
                return

            loaded = {}
            for panel in payload:
                if isinstance(panel, dict) and "id" in panel:
                    loaded[str(panel["id"])] = panel

            self._panels = loaded

        def _save_locked(self):
            ordered = sorted(
                self._panels.values(),
                key=lambda panel: panel.get("created", ""),
            )
            temp_path = self._path.with_suffix(".json.tmp")
            raw = json.dumps(ordered, indent=2, sort_keys=True)
            with temp_path.open("w", encoding="utf-8") as handle:
                handle.write(raw)
                handle.write("\n")
            os.replace(temp_path, self._path)

        def list_panels(self):
            with self._lock:
                return [
                    dict(panel)
                    for panel in sorted(
                        self._panels.values(),
                        key=lambda value: value.get("created", ""),
                    )
                ]

        def get_panel(self, panel_id):
            with self._lock:
                panel = self._panels.get(panel_id)
                if panel is None:
                    return None
                return dict(panel)

        def create_panel(self, payload):
            panel_type = payload.get("type")
            if panel_type not in ["vega-lite", "markdown"]:
                raise ValueError("type must be vega-lite or markdown")

            title = payload.get("title")
            if not isinstance(title, str) or not title.strip():
                raise ValueError("title is required")

            grid = payload.get("grid", default_grid())
            grid = validate_grid(grid)

            now = utc_now_iso()
            panel = {
                "id": make_panel_id(),
                "title": title.strip(),
                "type": panel_type,
                "created": now,
                "updated": now,
                "grid": grid,
            }

            if panel_type == "vega-lite":
                spec = payload.get("spec")
                if spec is None:
                    spec = {}
                if not isinstance(spec, dict):
                    raise ValueError("spec must be an object for vega-lite")
                panel["spec"] = spec
            else:
                content = payload.get("content", "")
                if not isinstance(content, str):
                    raise ValueError("content must be a string for markdown")
                panel["content"] = content

            with self._lock:
                self._panels[panel["id"]] = panel
                self._save_locked()

            return dict(panel)

        def update_panel(self, panel_id, patch):
            with self._lock:
                current = self._panels.get(panel_id)
                if current is None:
                    return None

                updated = dict(current)

                if "title" in patch:
                    title = patch["title"]
                    if not isinstance(title, str) or not title.strip():
                        raise ValueError("title must be a non-empty string")
                    updated["title"] = title.strip()

                if "type" in patch:
                    panel_type = patch["type"]
                    if panel_type not in ["vega-lite", "markdown"]:
                        raise ValueError("type must be vega-lite or markdown")
                    updated["type"] = panel_type
                    if panel_type == "vega-lite":
                        updated.setdefault("spec", {})
                        updated.pop("content", None)
                    else:
                        updated.setdefault("content", "")
                        updated.pop("spec", None)

                if "grid" in patch:
                    updated["grid"] = validate_grid(patch["grid"])

                if "spec" in patch:
                    if updated.get("type") != "vega-lite":
                        raise ValueError(
                            "spec can only be set when type is vega-lite"
                        )
                    spec = patch["spec"]
                    if not isinstance(spec, dict):
                        raise ValueError("spec must be an object")
                    updated["spec"] = spec

                if "content" in patch:
                    if updated.get("type") != "markdown":
                        raise ValueError(
                            "content can only be set when type is markdown"
                        )
                    content = patch["content"]
                    if not isinstance(content, str):
                        raise ValueError("content must be a string")
                    updated["content"] = content

                updated["updated"] = utc_now_iso()
                self._panels[panel_id] = updated
                self._save_locked()
                return dict(updated)

        def delete_panel(self, panel_id):
            with self._lock:
                existing = self._panels.get(panel_id)
                if existing is None:
                    return None
                deleted = self._panels.pop(panel_id)
                self._save_locked()
                return dict(deleted)

        def update_panel_data(self, panel_id, values):
            with self._lock:
                current = self._panels.get(panel_id)
                if current is None:
                    return None

                if current.get("type") != "vega-lite":
                    raise ValueError(
                        "data refresh is only valid for vega-lite"
                    )

                if not isinstance(values, list):
                    raise ValueError("values must be an array")

                updated = dict(current)
                spec = dict(updated.get("spec", {}))
                spec_data = dict(spec.get("data", {}))
                spec_data["values"] = values
                spec["data"] = spec_data
                updated["spec"] = spec
                updated["updated"] = utc_now_iso()
                self._panels[panel_id] = updated
                self._save_locked()
                return dict(updated)


    class EventBus:
        def __init__(self):
            self._lock = threading.Lock()
            self._clients = []

        def subscribe(self):
            channel = queue.Queue(maxsize=128)
            with self._lock:
                self._clients.append(channel)
            return channel

        def unsubscribe(self, channel):
            with self._lock:
                self._clients = [
                    item for item in self._clients if item != channel
                ]

        def publish(self, event_name, payload):
            message = {"event": event_name, "payload": payload}
            stale = []
            with self._lock:
                for channel in self._clients:
                    try:
                        channel.put_nowait(message)
                    except queue.Full:
                        stale.append(channel)
                if stale:
                    self._clients = [
                        item for item in self._clients if item not in stale
                    ]


    def read_html(path):
        with open(path, "rb") as handle:
            return handle.read()


    def parse_json(handler):
        size_text = handler.headers.get("Content-Length")
        if size_text is None:
            raise ValueError("Content-Length header is required")

        try:
            size = int(size_text)
        except ValueError as err:
            raise ValueError("invalid Content-Length") from err

        if size < 0:
            raise ValueError("Content-Length must be positive")

        if size > MAX_BODY_SIZE:
            raise OverflowError("payload too large")

        body = handler.rfile.read(size)
        if len(body) != size:
            raise ValueError("request body truncated")

        try:
            payload = json.loads(body.decode("utf-8"))
        except (UnicodeDecodeError, json.JSONDecodeError) as err:
            raise ValueError("invalid JSON payload") from err

        if not isinstance(payload, dict):
            raise ValueError("JSON body must be an object")

        return payload


    class ReusableThreadingServer(ThreadingHTTPServer):
        allow_reuse_address = True


    class Handler(BaseHTTPRequestHandler):
        store = None
        bus = None
        html_path = None

        def _send_bytes(self, data, content_type, status=200):
            self.send_response(status)
            self.send_header("Content-Type", content_type)
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)

        def _send_json(self, payload, status=200):
            raw = json.dumps(payload).encode("utf-8")
            self._send_bytes(
                raw,
                "application/json; charset=utf-8",
                status=status,
            )

        def _publish(self, event_name, panel):
            self.bus.publish(event_name, panel)

        def _panel_id_for_path(self):
            match = PANEL_PATH_RE.match(self.path)
            if match is None:
                return None
            return match.group(1)

        def do_GET(self):
            route = self.path.split("?", 1)[0]

            if route == "/":
                self._send_bytes(
                    read_html(self.html_path),
                    "text/html; charset=utf-8",
                )
                return

            if route == "/api/panels":
                panels = self.store.list_panels()
                self._send_json(panels)
                return

            if route == "/api/events":
                self._handle_sse()
                return

            match = PANEL_PATH_RE.match(route)
            if match is not None:
                panel = self.store.get_panel(match.group(1))
                if panel is None:
                    self._send_json({"error": "not_found"}, status=404)
                    return
                self._send_json(panel)
                return

            self._send_json({"error": "not_found"}, status=404)

        def do_POST(self):
            route = self.path.split("?", 1)[0]

            try:
                payload = parse_json(self)
            except OverflowError:
                self._send_json(
                    {"error": "payload_too_large"},
                    status=413,
                )
                return
            except ValueError as err:
                self._send_json({"error": str(err)}, status=400)
                return

            if route == "/api/panels":
                try:
                    panel = self.store.create_panel(payload)
                except ValueError as err:
                    self._send_json({"error": str(err)}, status=400)
                    return

                self._publish("panel-created", panel)
                self._send_json(panel, status=201)
                return

            match = PANEL_DATA_PATH_RE.match(route)
            if match is not None:
                panel_id = match.group(1)
                values = payload.get("values")
                try:
                    panel = self.store.update_panel_data(panel_id, values)
                except ValueError as err:
                    self._send_json({"error": str(err)}, status=400)
                    return

                if panel is None:
                    self._send_json({"error": "not_found"}, status=404)
                    return

                self._publish("panel-updated", panel)
                self._send_json(panel)
                return

            self._send_json({"error": "not_found"}, status=404)

        def do_PATCH(self):
            route = self.path.split("?", 1)[0]
            match = PANEL_PATH_RE.match(route)
            if match is None:
                self._send_json({"error": "not_found"}, status=404)
                return

            try:
                patch = parse_json(self)
            except OverflowError:
                self._send_json(
                    {"error": "payload_too_large"},
                    status=413,
                )
                return
            except ValueError as err:
                self._send_json({"error": str(err)}, status=400)
                return

            try:
                panel = self.store.update_panel(match.group(1), patch)
            except ValueError as err:
                self._send_json({"error": str(err)}, status=400)
                return

            if panel is None:
                self._send_json({"error": "not_found"}, status=404)
                return

            self._publish("panel-updated", panel)
            self._send_json(panel)

        def do_DELETE(self):
            route = self.path.split("?", 1)[0]
            match = PANEL_PATH_RE.match(route)
            if match is None:
                self._send_json({"error": "not_found"}, status=404)
                return

            panel = self.store.delete_panel(match.group(1))
            if panel is None:
                self._send_json({"error": "not_found"}, status=404)
                return

            self._publish("panel-deleted", {"id": panel["id"]})
            self._send_json({"deleted": panel["id"]})

        def _handle_sse(self):
            channel = self.bus.subscribe()

            self.send_response(200)
            self.send_header("Content-Type", "text/event-stream")
            self.send_header("Cache-Control", "no-cache")
            self.send_header("Connection", "keep-alive")
            self.end_headers()

            try:
                self.wfile.write(b": connected\n\n")
                self.wfile.flush()

                while True:
                    try:
                        item = channel.get(timeout=30)
                        chunk = (
                            "event: %s\\n"
                            "data: %s\\n\\n"
                        ) % (item["event"], json.dumps(item["payload"]))
                    except queue.Empty:
                        chunk = ": heartbeat\\n\\n"

                    self.wfile.write(chunk.encode("utf-8"))
                    self.wfile.flush()
            except (BrokenPipeError, ConnectionResetError):
                return
            finally:
                self.bus.unsubscribe(channel)

        def log_message(self, format_text, *args):
            return


    def build_handler(store, bus, html_path):
        class CanvasHandler(Handler):
            pass

        CanvasHandler.store = store
        CanvasHandler.bus = bus
        CanvasHandler.html_path = html_path
        return CanvasHandler


    def main():
        parser = argparse.ArgumentParser(description="agent canvas server")
        parser.add_argument("--port", type=int, required=True)
        parser.add_argument("--data-dir", required=True)
        parser.add_argument("--html", required=True)
        args = parser.parse_args()

        pathlib.Path(args.data_dir).mkdir(parents=True, exist_ok=True)

        store = PanelStore(args.data_dir)
        bus = EventBus()
        handler = build_handler(store, bus, args.html)

        server = ReusableThreadingServer(("0.0.0.0", args.port), handler)
        print("agent-canvas listening on 0.0.0.0:%d" % args.port)
        server.serve_forever()


    if __name__ == "__main__":
        main()
  '';
  canvasHtml = pkgs.writeText "canvas.html" ''
    <!doctype html>
    <html lang="en">
      <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>Agent Canvas</title>
        <link rel="stylesheet"
          href="https://cdn.jsdelivr.net/npm/gridstack@12.3.3/dist/gridstack.min.css">
        <script src="https://cdn.jsdelivr.net/npm/vega@6"></script>
        <script src="https://cdn.jsdelivr.net/npm/vega-lite@6"></script>
        <script src="https://cdn.jsdelivr.net/npm/vega-embed@7"></script>
        <script src="https://cdn.jsdelivr.net/npm/marked@15"></script>
        <script src="https://cdn.jsdelivr.net/npm/gridstack@12.3.3/dist/gridstack-all.js"></script>
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
            --bad: #ff6b6b;
          }

          * {
            box-sizing: border-box;
          }

          body {
            margin: 0;
            min-height: 100vh;
            background: radial-gradient(circle at top, #24244a, var(--bg));
            color: var(--text);
            font-family: "Iosevka Aile", "JetBrains Mono", monospace;
          }

          .page {
            max-width: 1400px;
            margin: 0 auto;
            padding: 1.2rem 0.8rem 2rem;
          }

          .title {
            margin: 0;
            font-size: 1.7rem;
          }

          .subtitle {
            margin-top: 0.3rem;
            color: var(--muted);
            font-size: 0.95rem;
          }

          .status {
            margin-top: 0.8rem;
            color: var(--muted);
            font-size: 0.85rem;
          }

          .status.bad {
            color: var(--bad);
          }

          .status.ok {
            color: var(--ok);
          }

          .empty {
            margin-top: 1rem;
            border: 1px dashed var(--border);
            border-radius: 10px;
            padding: 1.2rem;
            background: rgba(35, 35, 64, 0.7);
            color: var(--muted);
          }

          .grid-stack {
            margin-top: 1rem;
            min-height: 320px;
          }

          .grid-stack-item-content.panel {
            border: 1px solid var(--border);
            border-radius: 10px;
            background: var(--panel);
            display: flex;
            flex-direction: column;
            overflow: hidden;
          }

          .panel-header {
            display: flex;
            align-items: center;
            justify-content: space-between;
            gap: 0.4rem;
            padding: 0.55rem 0.65rem;
            background: var(--panel-alt);
            border-bottom: 1px solid var(--border);
          }

          .panel-title {
            font-size: 0.95rem;
            font-weight: 700;
            min-width: 0;
            overflow: hidden;
            text-overflow: ellipsis;
            white-space: nowrap;
          }

          .panel-actions {
            display: flex;
            align-items: center;
          }

          .delete-btn {
            border: 0;
            border-radius: 6px;
            background: rgba(255, 107, 107, 0.12);
            color: var(--bad);
            font: inherit;
            line-height: 1;
            padding: 0.35rem 0.45rem;
            cursor: pointer;
          }

          .delete-btn:hover {
            background: rgba(255, 107, 107, 0.22);
          }

          .panel-body {
            flex: 1;
            overflow: auto;
            padding: 0.65rem;
          }

          .panel-body p {
            line-height: 1.35;
          }

          .panel-body pre {
            background: #0f1226;
            border: 1px solid var(--border);
            border-radius: 6px;
            padding: 0.6rem;
            overflow: auto;
          }
        </style>
      </head>
      <body>
        <main class="page">
          <h1 class="title">Agent Canvas</h1>
          <div class="subtitle">
            Live visualization canvas for agent-driven panels
          </div>
          <div id="status" class="status">Loading panels...</div>
          <div id="emptyState" class="empty" hidden>
            No panels yet. Agents can push visualizations via POST /api/panels.
          </div>
          <div class="grid-stack" id="canvasGrid"></div>
        </main>
        <script>
          var grid = GridStack.init({
            column: 12,
            float: true,
            margin: 8,
            cellHeight: 80,
            disableOneColumnMode: false
          }, "#canvasGrid");

          var panelCache = new Map();
          var patchTimer = null;
          var pendingLayouts = {};
          var reconnectMs = 1000;
          var reconnectHandle = null;
          var eventSource = null;
          var suppressLayoutEvents = 0;

          var statusEl = document.getElementById("status");
          var emptyStateEl = document.getElementById("emptyState");

          function setStatus(message, cls) {
            statusEl.textContent = message;
            statusEl.className = "status";
            if (cls) {
              statusEl.classList.add(cls);
            }
          }

          function updateEmptyState() {
            emptyStateEl.hidden = panelCache.size !== 0;
          }

          function withSuppressedLayout(work) {
            suppressLayoutEvents += 1;
            try {
              work();
            } finally {
              suppressLayoutEvents -= 1;
            }
          }

          function panelSelector(panelId) {
            return ".grid-stack-item[data-panel-id=\"" + panelId + "\"]";
          }

          function makePanelElement(panel) {
            var item = document.createElement("div");
            item.className = "grid-stack-item";
            item.dataset.panelId = panel.id;

            var content = document.createElement("div");
            content.className = "grid-stack-item-content panel";
            content.innerHTML =
              "<div class=\"panel-header\">" +
                "<div class=\"panel-title\"></div>" +
                "<div class=\"panel-actions\">" +
                  "<button class=\"delete-btn\" type=\"button\">X</button>" +
                "</div>" +
              "</div>" +
              "<div class=\"panel-body\"></div>";

            item.appendChild(content);
            item.querySelector(".delete-btn").addEventListener("click",
              function (event) {
                event.preventDefault();
                deletePanel(panel.id);
              });
            return item;
          }

          function renderPanelBody(panel, body) {
            body.innerHTML = "";
            if (panel.type === "vega-lite") {
              var spec = panel.spec || {};
              vegaEmbed(body, spec, { actions: false, renderer: "svg" })
                .catch(function (error) {
                  body.textContent = "Failed to render Vega-Lite panel: "
                    + String(error);
                });
              return;
            }

            if (panel.type === "markdown") {
              body.innerHTML = marked.parse(panel.content || "");
              return;
            }

            body.textContent = "Unsupported panel type: " + String(panel.type);
          }

          function upsertPanel(panel) {
            panelCache.set(panel.id, panel);
            updateEmptyState();

            withSuppressedLayout(function () {
              var existing = document.querySelector(panelSelector(panel.id));
              if (!existing) {
                var created = makePanelElement(panel);
                grid.addWidget(created, {
                  x: panel.grid.x,
                  y: panel.grid.y,
                  w: panel.grid.w,
                  h: panel.grid.h
                });
                existing = created;
              } else {
                grid.update(existing, {
                  x: panel.grid.x,
                  y: panel.grid.y,
                  w: panel.grid.w,
                  h: panel.grid.h
                });
              }

              var titleEl = existing.querySelector(".panel-title");
              var bodyEl = existing.querySelector(".panel-body");
              titleEl.textContent = panel.title;
              renderPanelBody(panel, bodyEl);
            });
          }

          function removePanel(panelId) {
            panelCache.delete(panelId);
            updateEmptyState();
            var item = document.querySelector(panelSelector(panelId));
            if (item) {
              withSuppressedLayout(function () {
                grid.removeWidget(item, true, false);
              });
            }
          }

          async function fetchJson(url, options) {
            var response = await fetch(url, options || {});
            if (!response.ok) {
              var text = await response.text();
              throw new Error("HTTP " + response.status + ": " + text);
            }
            return await response.json();
          }

          async function deletePanel(panelId) {
            try {
              await fetchJson("/api/panels/" + panelId, { method: "DELETE" });
              removePanel(panelId);
            } catch (error) {
              setStatus("Delete failed: " + String(error), "bad");
            }
          }

          function queueLayoutPatch(panelId, layout) {
            pendingLayouts[panelId] = layout;
            if (patchTimer) {
              clearTimeout(patchTimer);
            }
            patchTimer = setTimeout(flushLayoutPatches, 300);
          }

          async function flushLayoutPatches() {
            patchTimer = null;
            var entries = Object.entries(pendingLayouts);
            pendingLayouts = {};
            for (var i = 0; i < entries.length; i += 1) {
              var panelId = entries[i][0];
              var layout = entries[i][1];
              try {
                await fetchJson("/api/panels/" + panelId, {
                  method: "PATCH",
                  headers: { "Content-Type": "application/json" },
                  body: JSON.stringify({ grid: layout })
                });
              } catch (error) {
                setStatus(
                  "Layout sync failed for " + panelId + ": " + String(error),
                  "bad"
                );
              }
            }
          }

          function connectEvents() {
            if (eventSource) {
              eventSource.close();
            }

            eventSource = new EventSource("/api/events");
            eventSource.onopen = function () {
              reconnectMs = 1000;
              setStatus("Connected", "ok");
            };

            eventSource.addEventListener("panel-created", function (event) {
              var panel = JSON.parse(event.data);
              upsertPanel(panel);
            });

            eventSource.addEventListener("panel-updated", function (event) {
              var panel = JSON.parse(event.data);
              upsertPanel(panel);
            });

            eventSource.addEventListener("panel-deleted", function (event) {
              var payload = JSON.parse(event.data);
              removePanel(payload.id);
            });

            eventSource.onerror = function () {
              if (eventSource) {
                eventSource.close();
              }
              setStatus(
                "Events disconnected, retrying in "
                + String(reconnectMs / 1000) + "s",
                "bad"
              );
              if (reconnectHandle) {
                clearTimeout(reconnectHandle);
              }
              reconnectHandle = setTimeout(function () {
                connectEvents();
              }, reconnectMs);
              reconnectMs = Math.min(reconnectMs * 2, 30000);
            };
          }

          grid.on("change", function (event, changedItems) {
            if (suppressLayoutEvents > 0) {
              return;
            }
            if (!changedItems) {
              return;
            }
            for (var i = 0; i < changedItems.length; i += 1) {
              var item = changedItems[i];
              if (!item.el || !item.el.dataset.panelId) {
                continue;
              }
              queueLayoutPatch(item.el.dataset.panelId, {
                x: item.x,
                y: item.y,
                w: item.w,
                h: item.h
              });
            }
          });

          async function initialLoad() {
            try {
              var panels = await fetchJson("/api/panels");
              withSuppressedLayout(function () {
                for (var i = 0; i < panels.length; i += 1) {
                  upsertPanel(panels[i]);
                }
              });
              updateEmptyState();
              setStatus("Connected", "ok");
            } catch (error) {
              setStatus("Failed to load panels: " + String(error), "bad");
            }
          }

          initialLoad();
          connectEvents();
        </script>
      </body>
    </html>
  '';
in
{
  options.services.agentCanvas = {
    enable = lib.mkEnableOption "agent-driven visualization canvas";

    listenPort = lib.mkOption {
      type = lib.types.port;
      default = 8083;
      description = "Port for the agent canvas HTTP server";
    };
  };

  config = lib.mkIf cfg.enable {
    services.dashboard.entries.canvas = lib.mkDefault {
      name = "Agent Canvas";
      module = "canvas.nix";
      description = "Agent-driven Vega-Lite + markdown visualization canvas";
      port = cfg.listenPort;
      url = "http://${config.networking.hostName}:${toString cfg.listenPort}";
      systemdUnit = "agent-canvas.service";
      icon = "chart";
      order = 58;
    };

    systemd.services."agent-canvas" = {
      description = "Agent Canvas visualization server";
      wantedBy = [ "multi-user.target" ];
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ];

      serviceConfig = {
        ExecStart =
          "${canvasServer}/bin/agent-canvas --port "
          + "${toString cfg.listenPort} --data-dir /var/lib/agent-canvas "
          + "--html ${canvasHtml}";
        DynamicUser = true;
        StateDirectory = "agent-canvas";
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
  };
}
