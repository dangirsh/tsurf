# scripts/dashboard-server.py — HTTP server for the NixOS dashboard.
# Serves dashboard HTML and provides JSON API endpoints for
# service status, deploy status, and cost data.
import argparse
import json
import subprocess
import time
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


DEPLOY_STATUS_PATH = "/var/lib/deploy-status/status.json"


def build_deploy_payload():
    try:
        text = Path(DEPLOY_STATUS_PATH).read_text(
            encoding="utf-8"
        )
        return json.loads(text)
    except Exception:
        return {"status": "unknown"}


_cost_cache = {}
COST_CACHE_PATH = "/run/tsurf-cost.json"


def build_cost_payload():
    cached = _cost_cache.get("data")
    if cached and time.time() - _cost_cache.get("ts", 0) < 300:
        return cached
    try:
        text = Path(COST_CACHE_PATH).read_text(encoding="utf-8")
        payload = json.loads(text)
    except Exception as exc:
        payload = {"error": str(exc), "instances": []}
    _cost_cache["data"] = payload
    _cost_cache["ts"] = time.time()
    return payload


def make_handler(manifest_path, html_path):
    class Handler(BaseHTTPRequestHandler):
        def _security_headers(self):
            self.send_header(
                "X-Content-Type-Options", "nosniff"
            )
            self.send_header(
                "Referrer-Policy", "no-referrer"
            )
            self.send_header(
                "Permissions-Policy",
                "camera=(), microphone=(), geolocation=()"
            )
            self.send_header(
                "Cross-Origin-Opener-Policy", "same-origin"
            )
            self.send_header(
                "X-Frame-Options", "DENY"
            )

        def _send_bytes(self, payload, content_type, status=200):
            self.send_response(status)
            self.send_header("Content-Type", content_type)
            self.send_header("Content-Length", str(len(payload)))
            self._security_headers()
            self.end_headers()
            self.wfile.write(payload)

        def _send_json(self, payload, status=200):
            data = json.dumps(payload).encode("utf-8")
            self._send_bytes(
                data,
                "application/json; charset=utf-8",
                status=status,
            )

        def _redirect(self, location, status=302):
            self.send_response(status)
            self.send_header("Location", location)
            self.send_header("Content-Length", "0")
            self._security_headers()
            self.end_headers()

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
                self._send_json(
                    build_status_payload(manifest_path)
                )
                return
            if route == "/cost":
                self._redirect("/?tab=cost")
                return
            if route == "/api/cost-data":
                self._send_json(build_cost_payload())
                return
            if route == "/api/deploy-status":
                self._send_json(build_deploy_payload())
                return
            self._send_json({"error": "not_found"}, status=404)

        def log_message(self, format_text, *args):
            return

    return Handler


def main():
    parser = argparse.ArgumentParser(
        description="nix dashboard server"
    )
    parser.add_argument("--port", type=int, required=True)
    parser.add_argument("--bind", default="127.0.0.1")
    parser.add_argument("--manifest", required=True)
    parser.add_argument("--html", required=True)
    args = parser.parse_args()

    handler = make_handler(args.manifest, args.html)
    server = ThreadingHTTPServer(
        (args.bind, args.port), handler
    )
    print(
        "nix-dashboard listening on %s:%d"
        % (args.bind, args.port)
    )
    server.serve_forever()


if __name__ == "__main__":
    main()
