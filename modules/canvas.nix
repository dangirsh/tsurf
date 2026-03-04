# modules/canvas.nix
{ config, lib, pkgs, ... }:
let
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
in
{
}
